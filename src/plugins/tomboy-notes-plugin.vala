/*
 * Copyright (C) 2011 Michael Aquilina <michaelaquilina@gmail.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301  USA.
 *
 * Authored by Michael Aquilina <michaelaquilina@gmail.com>
 *
 */

namespace Synapse
{
  public class TomboyNotesPlugin : Object, Activatable, ItemProvider
  {
    public bool enabled { get; set; default = true; }

    private List<TomboyNoteMatch> notes;
    private FileMonitor tomboy_monitor;
    private TomboyHistory history;

    public void activate ()
    {
      history = new TomboyHistory ();

      File note_storage = File.new_for_path (
        "%s/.local/share/tomboy".printf (Environment.get_home_dir ())
      );
      try {
        notes = list_tomboy_notes (note_storage);
      } catch (Error err) {
        warning ("%s", err.message);
      }

      tomboy_monitor = note_storage.monitor (FileMonitorFlags.SEND_MOVED, null);
      tomboy_monitor.set_rate_limit (500);
      tomboy_monitor.changed.connect ( (src, dest, event) => {
        string src_path = src.get_path ();
        if (src_path.has_suffix (".note")) {
          message ("Reloading notes due to change in %s (%s)", src_path, event.to_string ());
          try {
            notes = list_tomboy_notes (note_storage);
          } catch (Error err) {
            warning ("Unable to list tomboy notes: %s", err.message);
          }
        }
      });
    }

    public void deactivate ()
    {
      tomboy_monitor.cancel ();
      if (history != null) {
        history.save ();
      }
    }

    static void register_plugin ()
    {
      PluginRegistry.get_default ().register_plugin (
        typeof (TomboyNotesPlugin),
        _("Tomboy Notes"),
        _("Search for tomboy notes."),
        "tomboy",
        register_plugin,
        Environment.find_program_in_path ("tomboy") != null,
        _("Tomboy Notes is not installed")
      );
    }

    static construct
    {
      register_plugin ();
    }

    private static string unescape_xml (string text)
    {
      if (text.index_of_char ('&') == -1) return text;
      return text.replace ("&amp;", "&")
                 .replace ("&lt;", "<")
                 .replace ("&gt;", ">")
                 .replace ("&quot;", "\"")
                 .replace ("&apos;", "'");
    }

    public string? get_note_title (File note_file) throws Error {
      FileInputStream fis = note_file.read ();
      DataInputStream dis = new DataInputStream (fis);

      string? result = null;
      try {
        string? line;
        while ((line = dis.read_line ()) != null) {
          if ("<title>" in line && "</title>" in line) {
            int start = line.index_of ("<title>") + 7;
            int end = line.index_of ("</title>");
            if (end > start) {
              result = unescape_xml (line.substring (start, end - start).strip ());
              break;
            }
          }
        }
      } finally {
        try {
          dis.close ();
        } catch (Error e) {
        }
      }

      return result;
    }

    private List<TomboyNoteMatch> list_tomboy_notes (File directory) throws Error {
      List<TomboyNoteMatch> result = new List<TomboyNoteMatch> ();

      FileEnumerator enumerator = directory.enumerate_children (
        FileAttribute.STANDARD_NAME + "," +
        FileAttribute.STANDARD_TYPE + "," +
        FileAttribute.TIME_MODIFIED,
        FileQueryInfoFlags.NOFOLLOW_SYMLINKS,
        null
      );

      FileInfo? info = null;
      while ((info = enumerator.next_file (null)) != null) {
        string file_name = info.get_name ();
        File note_file = directory.get_child (file_name);

        if (info.get_file_type () == FileType.REGULAR && file_name.has_suffix (".note")) {
          try {
            string? title = get_note_title (note_file);
            if (title != null && title != "") {
              int64 mtime = (int64) info.get_attribute_uint64 (FileAttribute.TIME_MODIFIED);
              var match = new TomboyNoteMatch (
                title,
                note_file.get_path (),
                mtime,
                history
              );
              result.append (match);
            }
          } catch (Error err) {
            warning ("%s", err.message);
          }
        }
      }
      return result;
    }

    public bool handles_query (Query query)
    {
      return (QueryFlags.ACTIONS in query.query_type ||
              QueryFlags.DOCUMENTS in query.query_type ||
              QueryFlags.FILES in query.query_type);
    }

    public async ResultSet? search (Query query) throws SearchError
    {
      var matchers = Query.get_matchers_for_query (
        query.query_string, 0,
        RegexCompileFlags.OPTIMIZE | RegexCompileFlags.CASELESS
      );

      var results = new ResultSet ();
      int64 now = (int64) new DateTime.now_local ().to_unix ();

      foreach (unowned TomboyNoteMatch note in notes)
      {
        foreach (var matcher in matchers)
        {
          if (matcher.key.match (note.title)) {
            int bonus = 0;
            if (history.has_record (note.url))
            {
              bonus = history.get_relevancy_bonus (note.url);
            }
            else
            {
              int64 diff = now - note.mtime;
              if (diff >= 0)
              {
                if (diff < 86400) // 1 day
                  bonus = 8000;
                else if (diff < 604800) // 7 days
                  bonus = 4000;
                else if (diff < 2592000) // 30 days
                  bonus = 1000;
              }
            }

            int score = matcher.value + bonus;
            results.add (note, score);
            break;
          }
        }
      }

      // make sure this method is called before returning any results
      query.check_cancellable ();
      if (results.size > 0) {
        return results;
      } else {
        return null;
      }
    }

    private class TomboyHistory
    {
      private KeyFile keyfile;
      private string file_path;
      private bool dirty = false;

      public TomboyHistory ()
      {
        keyfile = new KeyFile ();
        string dir = Path.build_filename (Environment.get_user_cache_dir (), "synapse");
        DirUtils.create_with_parents (dir, 0755);
        file_path = Path.build_filename (dir, "tomboy_history.ini");
        try
        {
          keyfile.load_from_file (file_path, KeyFileFlags.NONE);
        }
        catch (Error e)
        {
          // First run or file doesn't exist yet
        }
      }

      public bool has_record (string note_path)
      {
        string group = Path.get_basename (note_path);
        return keyfile.has_group (group);
      }

      public void record_open (string note_path)
      {
        string group = Path.get_basename (note_path);
        int64 now = (int64) new DateTime.now_local ().to_unix ();
        int count = 0;
        try
        {
          count = keyfile.get_integer (group, "count");
        }
        catch (Error e)
        {
          count = 0;
        }
        count++;
        keyfile.set_int64 (group, "last_opened", now);
        keyfile.set_integer (group, "count", count);
        dirty = true;
        save ();
      }

      public int get_relevancy_bonus (string note_path)
      {
        string group = Path.get_basename (note_path);
        if (!keyfile.has_group (group)) return 0;

        int64 last_opened = 0;
        int count = 0;
        try
        {
          last_opened = keyfile.get_int64 (group, "last_opened");
          count = keyfile.get_integer (group, "count");
        }
        catch (Error e)
        {
          return 0;
        }

        int64 now = (int64) new DateTime.now_local ().to_unix ();
        int64 diff = now - last_opened;
        if (diff < 0) diff = 0;

        int bonus = 0;
        if (diff < 3600) // 1 hour
          bonus += 25000;
        else if (diff < 86400) // 24 hours
          bonus += 18000;
        else if (diff < 604800) // 7 days
          bonus += 12000;
        else if (diff < 2592000) // 30 days
          bonus += 6000;
        else
          bonus += 2000;

        bonus += int.min (count * 1000, 10000);
        return bonus;
      }

      public void save ()
      {
        if (!dirty) return;
        try
        {
          string data = keyfile.to_data ();
          FileUtils.set_contents (file_path, data);
          dirty = false;
        }
        catch (Error e)
        {
          warning ("Failed to save tomboy history: %s", e.message);
        }
      }
    }

    private class TomboyNoteMatch : ActionMatch
    {
      public string url { get; construct; }
      public int64 mtime { get; construct; }
      private TomboyHistory history;

      public TomboyNoteMatch (string note_title, string url, int64 mtime, TomboyHistory history)
      {
        Object (title: note_title,
                description: _("Open Tomboy Note"),
                has_thumbnail: false,
                icon_name: "tomboy",
                url: url,
                mtime: mtime);
        this.history = history;
      }

      public override void do_action ()
      {
        history.record_open (url);
        Utils.open_tomboy_note (url);
      }
    }
  }
}

# Synapse Indicator (Modernized Fork)

A fast, semantic launcher for Linux desktop environments (MATE, GNOME, XFCE, etc.), modernized and maintained for **Ubuntu 24.04 (Noble)**, **Linux Mint 22.3**, and newer distributions.

[![License: GPL v2 / LGPL v2.1](https://img.shields.io/badge/License-GPL%20v2%20%7C%20LGPL%20v2.1-blue.svg)](COPYING.md)

---

## 🌟 What's New in this Fork

This fork updates the classic [Synapse launcher](https://launchpad.net/synapse-project) with support for modern toolchains (GCC 13/14, Vala 0.56+) and includes critical fixes and enhancements for the **Tomboy Notes** plugin:

### 1. Modern Toolchain Compatibility
* **Vala 0.56+ & GCC 14 Ready**: Resolved strict syntax deprecations, nullable Gee iterator return types (`Gee.Iterator<...>?`), Gee collection instantiations, and JSON object node ownership.
* **Modern Package Dependencies**: Transitioned away from deprecated libraries (e.g., `consolekit`), added support for `libayatana-appindicator3-dev` alongside `libappindicator3-dev`.

### 2. Tomboy Notes Plugin Fixes & Enhancements
* **Resolved 3,600+ Notes File Descriptor Leak**:
  * In earlier versions, `get_note_title()` exited early upon matching `<title>` without closing file streams. In systems with large note libraries (e.g., 3,000+ notes), the system limit of 1024 open file descriptors was quickly exhausted, causing over 70% of notes to fail loading with `Too many open files`.
  * The file reading logic now uses a read-only stream and guarantees file descriptor closure via a `finally` block, reducing load time for **3,650+ notes to just ~20 milliseconds** with 100% success.
  * Added unescaping for standard XML entities (`&amp;`, `&lt;`, `&gt;`, `&quot;`, `&apos;`).
* **Direct DBus & Argument-Preserving Note Launcher**:
  * Fixed an issue where selecting a note in Synapse opened the generic "Search All Notes" window (`MainWindow`) instead of the specific note.
  * Synapse now directly calls Tomboy's native Session DBus interface (`org.gnome.Tomboy.RemoteControl.DisplayNote`), with a safe fallback to `tomboy --open-note <path/uri>`.
  * Added interception for `note://tomboy/` URIs originating from the Zeitgeist activity logger, preventing desktop launchers from stripping arguments.
* **Smart History & Recency Ranking Boost**:
  * Added persistent tracking in `~/.cache/synapse/tomboy_history.ini` via `GLib.KeyFile`.
  * Opening a note records its last-accessed timestamp and open count.
  * Search matches are dynamically boosted based on:
    * **Recency Bonus**: Up to +25,000 points (opened within 1 hr), +18,000 (within 24 hrs), +12,000 (within 7 days).
    * **Frequency Bonus**: +1,000 points per open (up to +10,000).
    * **Cold-Start Modtime Boost**: Notes recently modified in Tomboy receive an initial score bonus even before being opened via Synapse.
    * Recently and frequently accessed notes now reliably rank at the **very top** of search results!
* **Expanded Category Search**:
  * `handles_query` now registers `ACTIONS | DOCUMENTS | FILES`, enabling note searches when browsing specific category tabs.

---

## 🚀 Building & Packaging

### Method 1: Automated Debian Package Builder (`build_deb.sh`)

An automated script is provided to check dependencies, compile, and produce installable `.deb` packages in one command:

```bash
# 1. Clone the repository
git clone https://github.com/your-username/synapse-project.git
cd synapse-project

# 2. Automatically install missing build dependencies and build the .deb package:
./build_deb.sh --install-deps

# Or, if dependencies are already installed:
./build_deb.sh
```

The resulting packages will be placed in `dist/` and `../`:
* `dist/synapse_0.4.6_amd64.deb`
* `dist/synapse-dbg_0.4.6_amd64.deb`

To clean build artifacts:
```bash
./build_deb.sh --clean
```

### Method 2: Manual Installation from Source

To install directly to `/usr/local` (or custom prefix):

```bash
./autogen.sh --prefix=/usr
make
sudo make install
```

---

## 📦 Installing the `.deb` Package

```bash
sudo dpkg -i dist/synapse_0.4.6_amd64.deb
sudo apt-get install -f   # Fixes any missing runtime dependencies if required
```

To run Synapse:
```bash
synapse &
```

---

## 📄 License

Synapse is distributed under the GNU General Public License (GPL) version 2 or later, and GNU Lesser General Public License (LGPL) version 2.1 or later. See [COPYING.md](COPYING.md) for details.

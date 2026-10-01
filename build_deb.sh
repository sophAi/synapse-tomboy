#!/usr/bin/env bash
# ==============================================================================
# Synapse 0.4.6 Debian Package Build Script
# Compatible with Ubuntu 24.04 (Noble) / Linux Mint 22.3 and newer
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_err()  { echo -e "${RED}[ERROR]${NC} $*"; }

echo -e "${BOLD}============================================================${NC}"
echo -e "${BOLD} Synapse 0.4.6 - Debian Package Builder${NC}"
echo -e " (GCC 14 / Modern Vala Fixes + Tomboy Search & History Boost)"
echo -e "${BOLD}============================================================${NC}"

# Check for local scratch build-root prefix (if built in rootless development environment)
SCRATCH_ROOT="$SCRIPT_DIR/../scratch"
if [ -d "$SCRATCH_ROOT/build_root" ] && [ -x "$SCRATCH_ROOT/bin/valac" ]; then
    log_info "Detected local build-root environment at: $SCRATCH_ROOT"
    export PATH="$SCRATCH_ROOT/bin:$PATH"
    export PKG_CONFIG_PATH="$SCRATCH_ROOT/build_root/usr/lib/x86_64-linux-gnu/pkgconfig:$SCRATCH_ROOT/build_root/usr/share/pkgconfig:${PKG_CONFIG_PATH:-}"
    export ACLOCAL_PATH="$SCRATCH_ROOT/build_root/usr/share/aclocal:${ACLOCAL_PATH:-}"
    export XDG_DATA_DIRS="$SCRATCH_ROOT/build_root/usr/share:${XDG_DATA_DIRS:-}"
    export VALAC="$SCRATCH_ROOT/bin/valac"
    export VAPIGEN="$SCRATCH_ROOT/bin/vapigen"
fi

# 1. Dependency List
REQUIRED_PACKAGES=(
    "build-essential"
    "debhelper"
    "dh-autoreconf"
    "gnome-common"
    "intltool"
    "valac"
    "libzeitgeist-2.0-dev"
    "libdbus-glib-1-dev"
    "libgtk-3-dev"
    "libglib2.0-dev"
    "libgee-0.8-dev"
    "libjson-glib-dev"
    "libkeybinder-3.0-dev"
    "libnotify-dev"
    "librest-dev"
)

# Appindicator package name varies between Debian/Ubuntu versions
if apt-cache show libayatana-appindicator3-dev >/dev/null 2>&1; then
    INDICATOR_DEV="libayatana-appindicator3-dev"
else
    INDICATOR_DEV="libappindicator3-dev"
fi
REQUIRED_PACKAGES+=("$INDICATOR_DEV")

MISSING_PACKAGES=()
for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        # If valac or library headers are provided by scratch environment, skip
        if [ -n "${VALAC:-}" ] && [ "$pkg" = "valac" ]; then
            continue
        fi
        MISSING_PACKAGES+=("$pkg")
    fi
done

INSTALL_DEPS=false
CLEAN_ONLY=false

for arg in "$@"; do
    case "$arg" in
        -i|--install-deps)
            INSTALL_DEPS=true
            ;;
        -c|--clean)
            CLEAN_ONLY=true
            ;;
        -h|--help)
            echo "Usage: ./build_deb.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -i, --install-deps   Install missing build dependencies via sudo apt"
            echo "  -c, --clean          Clean build files and exit without compiling"
            echo "  -h, --help           Show this help message"
            exit 0
            ;;
    esac
done

# Handle cleaning
clean_build() {
    log_info "Cleaning build files..."
    rm -rf debian/tmp debian/synapse debian/synapse-dbg debian/.debhelper debian/files \
           debian/*.substvars debian/*.log debian/debhelper-build-stamp \
           debian/autoreconf.after debian/autoreconf.before \
           autom4te.cache dist
    if [ -f Makefile ]; then
        make distclean >/dev/null 2>&1 || make clean >/dev/null 2>&1 || true
    fi
    log_ok "Clean complete."
}

if [ "$CLEAN_ONLY" = true ]; then
    clean_build
    exit 0
fi

if [ ${#MISSING_PACKAGES[@]} -gt 0 ]; then
    if [ "$INSTALL_DEPS" = true ]; then
        log_info "Installing missing dependencies with sudo apt..."
        sudo apt-get update
        sudo apt-get install -y "${MISSING_PACKAGES[@]}"
    else
        log_warn "Missing required packages: ${MISSING_PACKAGES[*]}"
        if [ -d "$SCRATCH_ROOT/build_root" ]; then
            log_info "Scratch build prefix is available; will continue with dpkg-buildpackage -d."
        else
            echo ""
            echo "To install missing dependencies automatically, run:"
            echo "  ./build_deb.sh --install-deps"
            echo ""
            echo "Or install them manually:"
            echo "  sudo apt-get update && sudo apt-get install -y ${MISSING_PACKAGES[*]}"
            echo ""
            exit 1
        fi
    fi
fi

# 2. Prepare build directory
log_info "Cleaning temporary debian build state..."
rm -rf debian/tmp debian/synapse debian/synapse-dbg debian/.debhelper debian/files \
       debian/*.substvars debian/*.log debian/debhelper-build-stamp \
       debian/autoreconf.after debian/autoreconf.before

# 3. Compile and build deb package
log_info "Starting package build (dpkg-buildpackage)..."
BUILD_FLAGS="-us -uc -b"
if [ ${#MISSING_PACKAGES[@]} -gt 0 ]; then
    BUILD_FLAGS="$BUILD_FLAGS -d"
fi

dpkg-buildpackage $BUILD_FLAGS

# 4. Copy debs to local dist/ folder for convenience
DIST_DIR="$SCRIPT_DIR/dist"
mkdir -p "$DIST_DIR"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
cp "$PARENT_DIR"/synapse_*.deb "$DIST_DIR"/ 2>/dev/null || true
cp "$PARENT_DIR"/synapse-dbg_*.deb "$DIST_DIR"/ 2>/dev/null || true

log_ok "Build finished successfully!"
echo ""
echo -e "${BOLD}Debian Packages created:${NC}"
ls -lh "$DIST_DIR"/*.deb 2>/dev/null || ls -lh "$PARENT_DIR"/synapse_*.deb 2>/dev/null || true
echo ""
echo -e "${BOLD}To install the package on this system:${NC}"
echo "  sudo dpkg -i $DIST_DIR/synapse_0.4.6_amd64.deb"
echo "  sudo apt-get install -f"
echo ""
echo -e "${BOLD}============================================================${NC}"

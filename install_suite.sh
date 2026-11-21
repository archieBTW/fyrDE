#!/bin/bash
set -euo pipefail

# Cross-Distro Fyr Suite Installer & Packager (Ubuntu/Debian, Arch, Fedora)
# Supports standalone installation or .deb packaging of FyrDE application suites:
#   - creative : fyrdaw (Sound Booth), fyrgraphics, fyrdirector
#   - office   : fyrdocs, fyrsheets, fyrslides
#   - dev      : fyrcode, fyrapi, fyrdb, fyrpods
#   - all      : all three suites combined

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

FLUTTER_VERSION="3.41.9"
PKG_VERSION="1.0.0"

CREATIVE_APPS=("fyrdaw" "fyrgraphics" "fyrdirector")
OFFICE_APPS=("fyrdocs" "fyrsheets" "fyrslides")
DEV_APPS=("fyrcode" "fyrapi" "fyrdb" "fyrpods")

SUITE=""
SINGLE_APP=""
CLEAN_BUILD=false
DEPS_ONLY=false
BUILD_DEB=false
SKIP_INSTALL=false

usage() {
    cat <<EOF
Usage: $0 [options]
Install or package standalone FyrDE app suites on Ubuntu/Debian, Arch, or Fedora.

Suites:
  creative    fyrdaw (Sound Booth), fyrgraphics, fyrdirector
  office      fyrdocs, fyrsheets, fyrslides
  dev         fyrcode, fyrapi, fyrdb, fyrpods
  all         All suites combined

Options:
  -s, --suite <name>   Suite to install/package (creative, office, dev, all)
  -a, --app <name>     Install/package a single app from any suite
  -c, --clean          Run 'flutter clean' before building
  -d, --deps-only      Install system dependencies only
      --deb            Build .deb packages into ./dist/deb/ (requires dpkg-deb)
      --no-install     When combined with --deb, only build .deb packages without installing
  -h, --help           Show this help message

Examples:
  $0 --suite creative
  $0 --suite office --deb
  $0 --app fyrdb -c
EOF
}

detect_distro() {
    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        OS="${ID:-unknown}"
        OS_LIKE="${ID_LIKE:-}"
    else
        echo "Error: Cannot determine OS (/etc/os-release not found)."
        exit 1
    fi

    if [ "$OS" = "arch" ] || [ "$OS" = "manjaro" ] || [ "$OS" = "endeavouros" ] || [[ "$OS_LIKE" == *arch* ]]; then
        DISTRO="arch"
    elif [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ] || [[ "$OS_LIKE" == *ubuntu* ]] || [[ "$OS_LIKE" == *debian* ]]; then
        DISTRO="debian"
    elif [ "$OS" = "fedora" ] || [[ "$OS_LIKE" == *fedora* ]]; then
        DISTRO="fedora"
    else
        echo "Error: Unsupported distribution '$OS'. Supported: Ubuntu/Debian, Arch, Fedora."
        exit 1
    fi
    echo "Detected distro family: $DISTRO ($OS)"
}

install_deps() {
    local suites_csv="$1"
    detect_distro

    case "$DISTRO" in
        debian)
            echo "Updating APT package index..."
            sudo apt-get update
            local deps=(
                "build-essential" "clang" "cmake" "ninja-build" "pkg-config"
                "libgtk-3-dev" "liblzma-dev" "libglu1-mesa" "curl" "git"
                "unzip" "xz-utils" "zip" "xvfb"
                "desktop-file-utils" "xdg-utils" "zenity"
            )
            if [[ "$suites_csv" == *creative* ]] || [[ "$suites_csv" == *all* ]]; then
                deps+=(
                    "libasound2-dev" "alsa-utils" "libpulse-dev" "pulseaudio-utils"
                    "liblilv-dev" "libflac-dev" "libopus-dev" "libogg-dev" "libvorbis-dev"
                    "libgstreamer1.0-dev" "libgstreamer-plugins-base1.0-dev"
                    "gstreamer1.0-plugins-base" "gstreamer1.0-plugins-good"
                    "gstreamer1.0-plugins-bad" "gstreamer1.0-libav"
                    "ffmpeg" "mpv" "libmpv-dev" "libepoxy-dev"
                )
            fi
            if [[ "$suites_csv" == *dev* ]] || [[ "$suites_csv" == *all* ]]; then
                deps+=("nodejs" "npm" "clangd" "libsqlite3-dev")
            fi
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${deps[@]}"
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y libmimalloc-dev libgtk-3-bin || true
            ;;
        arch)
            echo "Installing Arch packages via pacman..."
            local deps=(
                "base-devel" "clang" "cmake" "ninja" "pkgconf" "gtk3" "xz"
                "glu" "curl" "git" "unzip" "zip" "xorg-server-xvfb"
                "desktop-file-utils" "xdg-utils" "zenity"
            )
            if [[ "$suites_csv" == *creative* ]] || [[ "$suites_csv" == *all* ]]; then
                deps+=(
                    "alsa-lib" "alsa-utils" "libpulse" "lilv" "flac" "opus"
                    "libogg" "libvorbis" "gstreamer" "gst-plugins-base"
                    "gst-plugins-good" "gst-plugins-bad" "gst-libav"
                    "ffmpeg" "mpv" "libepoxy"
                )
            fi
            if [[ "$suites_csv" == *dev* ]] || [[ "$suites_csv" == *all* ]]; then
                deps+=("nodejs" "npm" "sqlite")
            fi
            sudo pacman -S --needed --noconfirm "${deps[@]}"
            ;;
        fedora)
            echo "Installing Fedora packages via dnf..."
            local deps=(
                "gcc-c++" "clang" "cmake" "ninja-build" "pkgconf" "gtk3-devel"
                "xz-devel" "mesa-libGLU" "curl" "git" "unzip" "zip"
                "xorg-x11-server-Xvfb" "desktop-file-utils" "xdg-utils" "zenity"
            )
            if [[ "$suites_csv" == *creative* ]] || [[ "$suites_csv" == *all* ]]; then
                deps+=(
                    "alsa-lib-devel" "alsa-utils" "pulseaudio-libs-devel"
                    "lilv-devel" "flac-devel" "opus-devel" "libogg-devel" "libvorbis-devel"
                    "gstreamer1-devel" "gstreamer1-plugins-base-devel"
                    "gstreamer1-plugins-good" "gstreamer1-plugins-bad-free"
                    "ffmpeg" "mpv-libs-devel" "libepoxy-devel"
                )
            fi
            if [[ "$suites_csv" == *dev* ]] || [[ "$suites_csv" == *all* ]]; then
                deps+=("nodejs" "npm" "sqlite-devel")
            fi
            sudo dnf install -y "${deps[@]}"
            ;;
    esac
}

install_flutter() {
    echo "Ensuring Flutter ${FLUTTER_VERSION} is installed in /opt/flutter..."
    if [ -d "/opt/flutter/bin" ] && [ -f "/opt/flutter/version" ] && [ "$(cat /opt/flutter/version)" = "$FLUTTER_VERSION" ]; then
        echo "Flutter ${FLUTTER_VERSION} already installed."
    else
        sudo rm -rf /opt/flutter
        sudo git clone --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git /opt/flutter
    fi

    if [ ! -w "/opt/flutter" ] || [ ! -w "/opt/flutter/bin" ]; then
        sudo chown -R "$(id -u):$(id -g)" /opt/flutter
    fi

    export PATH="/opt/flutter/bin:$PATH"
    git config --global --add safe.directory /opt/flutter || true
    flutter config --enable-linux-desktop
    sudo ln -sf /opt/flutter/bin/flutter /usr/local/bin/flutter
    sudo ln -sf /opt/flutter/bin/dart /usr/local/bin/dart
}

icon_source_for_app() {
    case "$1" in
        fyrdaw)      echo "$SCRIPT_DIR/fyrdaw/assets/icons/music2.png" ;;
        fyrgraphics) echo "$SCRIPT_DIR/fyrgraphics/assets/icons/fyrgraphics.png" ;;
        fyrdirector) echo "$SCRIPT_DIR/fyrdirector/assets/icons/fyrdirector.png" ;;
        fyrdocs)     echo "$SCRIPT_DIR/fyrdocs/assets/icons/fyrdocs.png" ;;
        fyrsheets)   echo "$SCRIPT_DIR/fyrsheets/assets/icons/fyrsheets.png" ;;
        fyrslides)   echo "$SCRIPT_DIR/fyrslides/assets/icons/fyrslides.png" ;;
        fyrcode)     echo "$SCRIPT_DIR/fyrcode/assets/icons/code.png" ;;
        fyrdb)       echo "$SCRIPT_DIR/fyrdb/assets/icons/fyrdb.png" ;;
        fyrpods)     echo "$SCRIPT_DIR/fyrpods/assets/icons/fyrpods.png" ;;
        *)           echo "" ;;
    esac
}

write_desktop_file() {
    local app=$1
    local dest=$2

    if [ -f "$SCRIPT_DIR/$app/$app.desktop" ]; then
        cp "$SCRIPT_DIR/$app/$app.desktop" "$dest"
        return
    fi

    case "$app" in
        fyrcode)
            cat <<'EOF' > "$dest"
[Desktop Entry]
Name=FyrCode
Comment=Advanced Code Editor for FyrDE
Exec=/usr/local/bin/fyrcode %U
Icon=fyrcode
Terminal=false
Type=Application
Categories=Development;TextEditor;IDE;
EOF
            ;;
        fyrapi)
            cat <<'EOF' > "$dest"
[Desktop Entry]
Name=FyrApi
Comment=A professional API testing client for FyrDE
Exec=/usr/local/bin/fyrapi
Icon=applications-development
Terminal=false
Type=Application
Categories=Development;Network;
EOF
            ;;
        *)
            cat <<EOF > "$dest"
[Desktop Entry]
Name=$app
Exec=/usr/local/bin/$app
Icon=$app
Terminal=false
Type=Application
Categories=Utility;
EOF
            ;;
    esac
}

deb_depends_for_app() {
    case "$1" in
        fyrdaw)
            echo "libgtk-3-0 | libgtk-3-0t64, libasound2 | libasound2t64, libpulse0, pulseaudio-utils, ffmpeg, zenity"
            ;;
        fyrdirector)
            echo "libgtk-3-0 | libgtk-3-0t64, libmpv2 | libmpv1, libepoxy0, ffmpeg, zenity"
            ;;
        fyrgraphics|fyrdocs|fyrsheets|fyrslides|fyrcode|fyrapi|fyrdb|fyrpods)
            echo "libgtk-3-0 | libgtk-3-0t64, zenity"
            ;;
        *)
            echo "libgtk-3-0 | libgtk-3-0t64"
            ;;
    esac
}

deb_description_for_app() {
    case "$1" in
        fyrdaw)      echo "Sound Booth - Digital Audio Workstation from FyrDE" ;;
        fyrgraphics) echo "fyrGraphics - Layered raster image editor from FyrDE" ;;
        fyrdirector) echo "fyrDirector - Non-linear video editor from FyrDE" ;;
        fyrdocs)     echo "fyrDocs - ODT/DOCX word processor from FyrDE" ;;
        fyrsheets)   echo "fyrSheets - ODS/XLSX/CSV spreadsheet studio from FyrDE" ;;
        fyrslides)   echo "fyrSlides - ODP/PPTX presentation studio from FyrDE" ;;
        fyrcode)     echo "FyrCode - Agentic code editor and IDE from FyrDE" ;;
        fyrapi)      echo "FyrApi - REST and HTTP API client from FyrDE" ;;
        fyrdb)       echo "fyrDB - Universal database manager and SQL IDE from FyrDE" ;;
        fyrpods)     echo "fyrPods - Container and pod manager from FyrDE" ;;
        *)           echo "$1 from FyrDE" ;;
    esac
}

build_app_bundle() {
    local app=$1
    local arch_dir="x64"
    case "$(uname -m)" in
        aarch64|arm64) arch_dir="arm64" ;;
        x86_64|amd64)  arch_dir="x64" ;;
    esac

    if [ ! -d "$SCRIPT_DIR/$app" ]; then
        echo "Error: Directory $SCRIPT_DIR/$app not found!"
        exit 1
    fi

    echo "Building $app..."
    (
        cd "$SCRIPT_DIR/$app"
        if [ "$CLEAN_BUILD" = "true" ]; then
            flutter clean || true
        fi
        if [ ! -f "linux/CMakeLists.txt" ]; then
            flutter create --platforms=linux .
        fi
        flutter pub get
        xvfb-run -a flutter build linux --release
    )

    LAST_BUNDLE_DIR="$SCRIPT_DIR/$app/build/linux/$arch_dir/release/bundle"
    if [ ! -d "$LAST_BUNDLE_DIR" ]; then
        echo "Error: Build bundle not found at $LAST_BUNDLE_DIR"
        exit 1
    fi
}

install_app_system() {
    local app=$1
    local bundle_dir=$2

    echo "Installing $app to /opt/$app..."
    sudo rm -rf "/opt/$app"
    sudo mkdir -p "/opt/$app" /usr/local/bin /usr/share/applications /usr/share/icons/hicolor/512x512/apps
    sudo cp -r "$bundle_dir"/* "/opt/$app/"
    sudo ln -sf "/opt/$app/$app" "/usr/local/bin/$app"

    local icon_src
    icon_src="$(icon_source_for_app "$app")"
    if [ -n "$icon_src" ] && [ -f "$icon_src" ]; then
        sudo cp "$icon_src" "/usr/share/icons/hicolor/512x512/apps/$app.png"
    fi

    local tmp_desktop
    tmp_desktop="$(mktemp)"
    write_desktop_file "$app" "$tmp_desktop"
    sudo install -m 644 "$tmp_desktop" "/usr/share/applications/$app.desktop"
    rm -f "$tmp_desktop"

    if command -v update-desktop-database &> /dev/null; then
        sudo update-desktop-database /usr/share/applications || true
    fi
    if command -v gtk-update-icon-cache &> /dev/null; then
        sudo gtk-update-icon-cache -f -t /usr/share/icons/hicolor || true
    fi
}

package_app_deb() {
    local app=$1
    local bundle_dir=$2

    if ! command -v dpkg-deb &> /dev/null; then
        echo "Error: dpkg-deb not found. Install 'dpkg' to build .deb packages."
        exit 1
    fi

    local deb_arch="amd64"
    case "$(uname -m)" in
        aarch64|arm64) deb_arch="arm64" ;;
        x86_64|amd64)  deb_arch="amd64" ;;
    esac

    local stage_dir
    stage_dir="$(mktemp -d)"
    mkdir -p \
        "$stage_dir/DEBIAN" \
        "$stage_dir/opt/$app" \
        "$stage_dir/usr/local/bin" \
        "$stage_dir/usr/share/applications" \
        "$stage_dir/usr/share/icons/hicolor/512x512/apps"

    cp -r "$bundle_dir"/* "$stage_dir/opt/$app/"
    ln -sf "/opt/$app/$app" "$stage_dir/usr/local/bin/$app"

    local icon_src
    icon_src="$(icon_source_for_app "$app")"
    if [ -n "$icon_src" ] && [ -f "$icon_src" ]; then
        cp "$icon_src" "$stage_dir/usr/share/icons/hicolor/512x512/apps/$app.png"
    fi

    write_desktop_file "$app" "$stage_dir/usr/share/applications/$app.desktop"

    cat <<EOF > "$stage_dir/DEBIAN/control"
Package: $app
Version: $PKG_VERSION
Section: utils
Priority: optional
Architecture: $deb_arch
Maintainer: FyrDE <dev@fyrde.dev>
Depends: $(deb_depends_for_app "$app")
Description: $(deb_description_for_app "$app")
EOF

    cat <<'EOF' > "$stage_dir/DEBIAN/postinst"
#!/bin/sh
set -e
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database /usr/share/applications || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f -t /usr/share/icons/hicolor || true
fi
EOF
    chmod 755 "$stage_dir/DEBIAN/postinst"

    mkdir -p "$SCRIPT_DIR/dist/deb"
    local out_deb="$SCRIPT_DIR/dist/deb/${app}_${PKG_VERSION}_${deb_arch}.deb"
    dpkg-deb --build --root-owner-group "$stage_dir" "$out_deb"
    rm -rf "$stage_dir"
    echo "Built package: $out_deb"
}

suite_for_app() {
    case "$1" in
        fyrdaw|fyrgraphics|fyrdirector) echo "creative" ;;
        fyrdocs|fyrsheets|fyrslides)    echo "office" ;;
        fyrcode|fyrapi|fyrdb|fyrpods)   echo "dev" ;;
        *) echo "" ;;
    esac
}

# --- Parse Arguments ---
while [ $# -gt 0 ]; do
    case "$1" in
        -s|--suite)
            SUITE="${2:-}"
            shift 2
            ;;
        -a|--app)
            SINGLE_APP="$(echo "${2:-}" | tr '[:upper:]' '[:lower:]')"
            shift 2
            ;;
        -c|--clean)
            CLEAN_BUILD=true
            shift
            ;;
        -d|--deps-only)
            DEPS_ONLY=true
            shift
            ;;
        --deb)
            BUILD_DEB=true
            shift
            ;;
        --no-install)
            SKIP_INSTALL=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

TARGET_APPS=()
DEP_SCOPE=""

if [ -n "$SINGLE_APP" ]; then
    DEP_SCOPE="$(suite_for_app "$SINGLE_APP")"
    if [ -z "$DEP_SCOPE" ]; then
        echo "Error: Unknown suite app '$SINGLE_APP'."
        echo "Supported apps: ${CREATIVE_APPS[*]} ${OFFICE_APPS[*]} ${DEV_APPS[*]}"
        exit 1
    fi
    TARGET_APPS=("$SINGLE_APP")
else
    case "${SUITE:-all}" in
        creative)
            TARGET_APPS=("${CREATIVE_APPS[@]}")
            DEP_SCOPE="creative"
            ;;
        office)
            TARGET_APPS=("${OFFICE_APPS[@]}")
            DEP_SCOPE="office"
            ;;
        dev)
            TARGET_APPS=("${DEV_APPS[@]}")
            DEP_SCOPE="dev"
            ;;
        all)
            TARGET_APPS=("${CREATIVE_APPS[@]}" "${OFFICE_APPS[@]}" "${DEV_APPS[@]}")
            DEP_SCOPE="all"
            ;;
        *)
            echo "Error: Unknown suite '$SUITE'. Expected: creative, office, dev, or all."
            exit 1
            ;;
    esac
fi

install_deps "$DEP_SCOPE"

if [ "$DEPS_ONLY" = "true" ]; then
    echo "Dependencies installed for scope: $DEP_SCOPE"
    exit 0
fi

install_flutter

for app in "${TARGET_APPS[@]}"; do
    LAST_BUNDLE_DIR=""
    build_app_bundle "$app"
    if [ "$BUILD_DEB" = "true" ]; then
        package_app_deb "$app" "$LAST_BUNDLE_DIR"
    fi
    if [ "$SKIP_INSTALL" != "true" ]; then
        install_app_system "$app" "$LAST_BUNDLE_DIR"
    fi
done

echo "Done! Processed apps: ${TARGET_APPS[*]}"

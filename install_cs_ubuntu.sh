#!/bin/bash
set -euo pipefail

# Fyr Creative Suite Installer for Ubuntu / Debian
# Installs system dependencies, Flutter 3.41.9, and builds/installs:
#   - fyrdaw      (Sound Booth - Digital Audio Workstation)
#   - fyrgraphics (fyrGraphics - Layered Image Editor)
#   - fyrdirector (fyrDirector - Non-Linear Video Editor)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

FLUTTER_VERSION="3.41.9"
CREATIVE_SUITE_APPS=("fyrdaw" "fyrgraphics" "fyrdirector")

# --- Progress Tracking & Terminal Management ---
CURRENT_STEP=0
TOTAL_STEPS=1
USE_STATUS_BAR=false

setup_status_bar() {
    if [ -t 1 ] && [ -n "${TERM:-}" ] && [ "$TERM" != "dumb" ] && command -v tput &> /dev/null; then
        LINES=$(tput lines 2>/dev/null || echo 0)
        if [ "$LINES" -gt 2 ]; then
            USE_STATUS_BAR=true
            tput csr 0 $((LINES - 2)) || true
            tput cup $((LINES - 1)) 0 || true
            tput el || true
            tput cup $((LINES - 2)) 0 || true
            printf "\n"

            cleanup() {
                tput csr 0 $((LINES - 1)) || true
                tput cup "$LINES" 0 || true
                printf "\n"
            }
            trap cleanup EXIT
        fi
    fi
}

show_progress() {
    local label=$1
    if [ "$USE_STATUS_BAR" != "true" ]; then return; fi

    local width=40
    local percent=$((CURRENT_STEP * 100 / TOTAL_STEPS))
    local filled=$((CURRENT_STEP * width / TOTAL_STEPS))

    local GREEN='\033[0;32m'
    local NC='\033[0m'
    local BOLD='\033[1m'

    tput sc
    tput cup $((LINES - 1)) 0
    tput el
    printf "${BOLD}[${NC}"
    for ((i=0; i<filled; i++)); do printf "${GREEN}=${NC}"; done
    for ((i=filled; i<width; i++)); do printf " "; done
    printf "${BOLD}]${NC} %d%% - %s" "$percent" "$label"
    tput rc
}

next_step() {
    local label=$1
    CURRENT_STEP=$((CURRENT_STEP + 1))
    show_progress "$label"
}

usage() {
    echo "Usage: $0 [options]"
    echo "Install the Fyr Creative Suite (fyrdaw, fyrgraphics, fyrdirector) on Ubuntu."
    echo ""
    echo "Options:"
    echo "  -a <app>    Build and install a single Creative Suite app (fyrdaw, fyrgraphics, fyrdirector)"
    echo "  -c          Force clean Flutter build (run flutter clean before building)"
    echo "  -d          Install Ubuntu system dependencies only"
    echo "  -F          Full Creative Suite installation (default if no flags provided)"
    echo "  -h          Show this help message"
}

check_ubuntu_env() {
    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        OS="${ID:-unknown}"
        OS_LIKE="${ID_LIKE:-}"
    else
        echo "Cannot determine OS (/etc/os-release not found). Exiting."
        exit 1
    fi

    if ! command -v apt-get &> /dev/null; then
        echo "Error: apt-get not found. This script is intended for Ubuntu / Debian-based systems (detected: $OS)."
        exit 1
    fi

    if [ "$OS" != "ubuntu" ] && [ "$OS" != "debian" ] && [[ "$OS_LIKE" != *ubuntu* ]] && [[ "$OS_LIKE" != *debian* ]]; then
        echo "Warning: Detected OS '$OS' (ID_LIKE='$OS_LIKE'). Proceeding with apt-get..."
    else
        echo "Detected OS: $OS"
    fi
}

install_deps() {
    check_ubuntu_env
    next_step "Installing Ubuntu dependencies..."
    echo "Updating APT package index..."
    sudo apt-get update

    # Core Flutter Linux build toolchain + Creative Suite build/runtime deps
    local deps=(
        # Build & Flutter Linux prerequisites
        "build-essential"
        "clang"
        "cmake"
        "ninja-build"
        "pkg-config"
        "libgtk-3-dev"
        "liblzma-dev"
        "libglu1-mesa"
        "curl"
        "git"
        "unzip"
        "xz-utils"
        "zip"
        "xvfb"
        # Desktop integration & file picker dialogs
        "desktop-file-utils"
        "xdg-utils"
        "zenity"
        # Audio & DAW (fyrdaw: ALSA, PulseAudio/PipeWire, SoLoud codecs, GStreamer, LV2)
        "libasound2-dev"
        "alsa-utils"
        "libpulse-dev"
        "pulseaudio-utils"
        "liblilv-dev"
        "libflac-dev"
        "libopus-dev"
        "libogg-dev"
        "libvorbis-dev"
        "libgstreamer1.0-dev"
        "libgstreamer-plugins-base1.0-dev"
        "gstreamer1.0-plugins-base"
        "gstreamer1.0-plugins-good"
        "gstreamer1.0-plugins-bad"
        "gstreamer1.0-libav"
        # Video & Media (fyrdirector & fyrdaw rendering: media_kit / libmpv / epoxy / ffmpeg)
        "ffmpeg"
        "mpv"
        "libmpv-dev"
        "libepoxy-dev"
    )

    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${deps[@]}"

    # Optional packages (best-effort across Ubuntu releases)
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y libmimalloc-dev libgtk-3-bin || true
}

install_flutter() {
    next_step "Setting up Flutter ${FLUTTER_VERSION}..."
    echo "Ensuring Flutter ${FLUTTER_VERSION} is installed in /opt/flutter..."

    if [ -d "/opt/flutter/bin" ] && [ -f "/opt/flutter/version" ] && [ "$(cat /opt/flutter/version)" = "$FLUTTER_VERSION" ]; then
        echo "Flutter ${FLUTTER_VERSION} is already installed. Skipping download."
    else
        echo "Installing/Updating Flutter to ${FLUTTER_VERSION}..."
        sudo rm -rf /opt/flutter
        sudo git clone --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git /opt/flutter
    fi

    if [ ! -w "/opt/flutter" ] || [ ! -w "/opt/flutter/bin" ]; then
        sudo chown -R "$(id -u):$(id -g)" /opt/flutter
    fi

    export PATH="/opt/flutter/bin:$PATH"
    git config --global --add safe.directory /opt/flutter || true

    if ! flutter --version &>/dev/null; then
        echo "Finalizing Flutter setup..."
        flutter doctor
    fi
    flutter config --enable-linux-desktop

    sudo ln -sf /opt/flutter/bin/flutter /usr/local/bin/flutter
    sudo ln -sf /opt/flutter/bin/dart /usr/local/bin/dart
}

cleanup_legacy_user_override() {
    local app=$1
    if [ -d "$HOME/.local/share/fyrDE/$app" ]; then
        rm -rf "$HOME/.local/share/fyrDE/$app"
    fi
    if [ -f "$HOME/.local/share/applications/$app.desktop" ]; then
        rm -f "$HOME/.local/share/applications/$app.desktop"
        if command -v update-desktop-database &> /dev/null; then
            update-desktop-database "$HOME/.local/share/applications" || true
        fi
    fi
    if [ -e "$HOME/.local/bin/$app" ] || [ -L "$HOME/.local/bin/$app" ]; then
        if [ -e "/usr/local/bin/$app" ]; then
            ln -sf "/usr/local/bin/$app" "$HOME/.local/bin/$app"
        elif [ -e "/opt/$app/$app" ]; then
            ln -sf "/opt/$app/$app" "$HOME/.local/bin/$app"
        else
            rm -f "$HOME/.local/bin/$app"
        fi
    fi
}

setup_app_configs() {
    local app=$1
    echo "Setting up desktop entry, icon, and binary symlink for $app..."

    sudo mkdir -p /usr/local/bin /usr/share/applications /usr/share/icons/hicolor/512x512/apps

    case "$app" in
        "fyrdaw")
            sudo ln -sf /opt/fyrdaw/fyrdaw /usr/local/bin/fyrdaw
            if [ -f "$SCRIPT_DIR/fyrdaw/assets/icons/music2.png" ]; then
                sudo cp "$SCRIPT_DIR/fyrdaw/assets/icons/music2.png" /usr/share/icons/hicolor/512x512/apps/fyrdaw.png
            fi
            if [ -f "$SCRIPT_DIR/fyrdaw/fyrdaw.desktop" ]; then
                sudo cp "$SCRIPT_DIR/fyrdaw/fyrdaw.desktop" /usr/share/applications/fyrdaw.desktop
            else
                sudo tee /usr/share/applications/fyrdaw.desktop > /dev/null <<'EOF'
[Desktop Entry]
Name=Sound Booth
Comment=Sound Booth Digital Audio Workstation
Exec=/usr/local/bin/fyrdaw
Icon=fyrdaw
Terminal=false
Type=Application
Categories=AudioVideo;Audio;
EOF
            fi
            ;;
        "fyrgraphics")
            sudo ln -sf /opt/fyrgraphics/fyrgraphics /usr/local/bin/fyrgraphics
            if [ -f "$SCRIPT_DIR/fyrgraphics/assets/icons/fyrgraphics.png" ]; then
                sudo cp "$SCRIPT_DIR/fyrgraphics/assets/icons/fyrgraphics.png" /usr/share/icons/hicolor/512x512/apps/fyrgraphics.png
            fi
            sudo tee /usr/share/applications/fyrgraphics.desktop > /dev/null <<'EOF'
[Desktop Entry]
Name=fyrGraphics
GenericName=Image Editor
Comment=Raster & layered image editor for FyrDE
Exec=/usr/local/bin/fyrgraphics %f
Icon=fyrgraphics
Terminal=false
Type=Application
Categories=Graphics;2DGraphics;RasterGraphics;Photography;
MimeType=image/png;image/jpeg;image/webp;image/bmp;image/gif;image/tiff;application/x-fyrgraphics;
Keywords=gimp;photoshop;photopea;image;editor;layers;graphics;
EOF
            ;;
        "fyrdirector")
            sudo ln -sf /opt/fyrdirector/fyrdirector /usr/local/bin/fyrdirector
            if [ -f "$SCRIPT_DIR/fyrdirector/assets/icons/fyrdirector.png" ]; then
                sudo cp "$SCRIPT_DIR/fyrdirector/assets/icons/fyrdirector.png" /usr/share/icons/hicolor/512x512/apps/fyrdirector.png
            fi
            sudo tee /usr/share/applications/fyrdirector.desktop > /dev/null <<'EOF'
[Desktop Entry]
Name=fyrDirector
GenericName=Video Editor
Comment=Non-linear video editor (Kdenlive / CapCut style) for FyrDE
Exec=/usr/local/bin/fyrdirector %f
Icon=fyrdirector
Terminal=false
Type=Application
Categories=AudioVideo;Video;AudioVideoEditing;
MimeType=video/mp4;video/x-matroska;video/webm;video/quicktime;application/x-fyrdirector;
Keywords=video;editor;kdenlive;capcut;timeline;render;ffmpeg;
EOF
            ;;
        *)
            echo "Error: Unsupported Creative Suite app '$app'. Supported: ${CREATIVE_SUITE_APPS[*]}"
            exit 1
            ;;
    esac

    if command -v update-desktop-database &> /dev/null; then
        sudo update-desktop-database /usr/share/applications || true
    fi
    if command -v gtk-update-icon-cache &> /dev/null; then
        sudo gtk-update-icon-cache -f -t /usr/share/icons/hicolor || true
    fi
}

install_app() {
    local app=$1
    local arch_dir="x64"
    case "$(uname -m)" in
        aarch64|arm64) arch_dir="arm64" ;;
        x86_64|amd64)  arch_dir="x64" ;;
    esac

    next_step "Building and installing $app..."
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

    local bundle_dir="$SCRIPT_DIR/$app/build/linux/$arch_dir/release/bundle"
    if [ ! -d "$bundle_dir" ]; then
        echo "Error: Build bundle not found at $bundle_dir"
        exit 1
    fi

    echo "Installing $app to /opt/$app..."
    sudo rm -rf "/opt/$app"
    sudo mkdir -p "/opt/$app"
    sudo cp -r "$bundle_dir"/* "/opt/$app/"

    setup_app_configs "$app"
    cleanup_legacy_user_override "$app"
}

# --- Argument Parsing ---
MODULAR=false
CLEAN_BUILD=false
INSTALL_DEPS=false
APP_TO_INSTALL=""

while getopts "a:cdFh" opt; do
    case "$opt" in
        a)
            APP_TO_INSTALL="$(echo "$OPTARG" | tr '[:upper:]' '[:lower:]')"
            case "$APP_TO_INSTALL" in
                fyrdaw|fyrgraphics|fyrdirector) ;;
                *)
                    echo "Error: '$OPTARG' is not in the Creative Suite (${CREATIVE_SUITE_APPS[*]})."
                    exit 1
                    ;;
            esac
            MODULAR=true
            ;;
        c) CLEAN_BUILD=true ;;
        d) INSTALL_DEPS=true; MODULAR=true ;;
        F) MODULAR=false ;;
        h) usage; exit 0 ;;
        *) usage; exit 1 ;;
    esac
done

# --- Execution ---
setup_status_bar

if [ "$MODULAR" = "false" ]; then
    echo "Starting Fyr Creative Suite installation for Ubuntu..."
    TOTAL_STEPS=$(( 2 + ${#CREATIVE_SUITE_APPS[@]} ))
    install_deps
    install_flutter
    for app in "${CREATIVE_SUITE_APPS[@]}"; do
        install_app "$app"
    done
    printf "\n"
    echo "Fyr Creative Suite installation complete! Installed: ${CREATIVE_SUITE_APPS[*]}"
else
    echo "Starting modular Fyr Creative Suite installation..."
    TOTAL_STEPS=0
    [ "$INSTALL_DEPS" = "true" ] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
    [ -n "$APP_TO_INSTALL" ] && TOTAL_STEPS=$((TOTAL_STEPS + 2))
    if [ "$TOTAL_STEPS" -eq 0 ]; then TOTAL_STEPS=1; fi

    if [ "$INSTALL_DEPS" = "true" ]; then install_deps; fi
    if [ -n "$APP_TO_INSTALL" ]; then
        install_flutter
        install_app "$APP_TO_INSTALL"
    fi
    printf "\n"
    echo "Operation complete!"
fi

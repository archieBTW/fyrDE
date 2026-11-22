#!/bin/bash
set -e

# --- Configuration & OS Detection ---

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo "Cannot determine OS. Exiting."
    exit 1
fi

echo "Detected OS: $OS"

# Get screen resolution early for patching source files
RES=$(cat /sys/class/drm/*/modes | head -n 1)
if [ -z "$RES" ]; then
    RES="1920x1080"
fi
WIDTH=$(echo $RES | cut -d'x' -f1)
HEIGHT=$(echo $RES | cut -d'x' -f2)
echo "Detected resolution: ${WIDTH}x${HEIGHT}"

flutter_apps=("fyrdock" "fyroverview" "fyrwindowoverview" "fyrsearch" "fyrsettings" "fyrtaskbar" "fyrterm" "fyrfiles" "fyrhelp" "fyremoji" "fyrclipboard" "fyrstore" "fyrvirt" "fyrav" "fyrtext" "fyrdaw" "fyrphone" "fyrcalculator" "fyrcode" "fyrvideo" "fyrmusic" "fyrphotos" "fyrcamera" "fyrbrowser" "fyrjournal" "fyrcalender" "fyrclock" "fyrtorrent" "fyrapi" "fyrgraphics" "devign" "fyremu" "fyrdirector" "fyrdisks" "fyrmonitor" "fyrdocs" "fyrsheets" "fyrslides" "fyrpdf" "fyrdb" "fyrpods")

# --- Progress Tracking & Terminal Management ---
CURRENT_STEP=0
TOTAL_STEPS=1

# Setup fixed status bar at the bottom
if [ -t 1 ]; then
    LINES=$(tput lines)
    COLUMNS=$(tput cols)
    
    # Enable scrolling region for all but the last line
    tput csr 0 $((LINES - 2))
    
    # Clear the last line and initialize it
    tput cup $((LINES - 1)) 0
    tput el
    
    # Move cursor to the last line of the scrollable region
    tput cup $((LINES - 2)) 0
    printf "\n"

    cleanup() {
        tput csr 0 $((LINES - 1)) # Reset scrolling region
        tput cup $LINES 0
        printf "\n"
    }
    trap cleanup EXIT
fi

show_progress() {
    local label=$1
    if [ ! -t 1 ]; then return; fi
    
    local width=40
    local percent=$((CURRENT_STEP * 100 / TOTAL_STEPS))
    local filled=$((CURRENT_STEP * width / TOTAL_STEPS))
    
    # ANSI Colors
    local GREEN='\033[0;32m'
    local NC='\033[0m'
    local BOLD='\033[1m'

    # Save cursor, move to last line, clear, draw, restore
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

# --- Functions ---

usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -a <app>    Rebuild and reinstall a specific Flutter app (e.g., fyrtaskbar, fyrgraphics)"
    echo "  -g          Build and install fyrGraphics standalone"
    echo "  -c          Force clean Flutter build (run flutter clean before building)"
    echo "  -w          Build and install SwayFX compositor"
    echo "  -s          Reinstall Sway configuration and scripts (preserves conf.d/*.conf)"
    echo "  -l          Reinstall SDDM theme and configuration"
    echo "  -t          Reinstall GTK and icon themes"
    echo "  -d          Install system dependencies only"
    echo "  -p          Build and install fyrpak (Go package manager & AUR helper)"
    echo "  -f          Install Fyr Fetch tool and add to zshrc"
    echo "  -z          Setup ZSH and Oh-My-Zsh"
    echo "  -H          Hide redundant dependency apps (mpv, foot, etc.)"
    echo "  -F          Force full installation (default if no flags provided)"
    echo "  -h          Show this help message"
}

install_fyrpak() {
    next_step "Building and installing fyrpak..."
    if [ ! -d "./fyrpak" ]; then
        echo "fyrpak directory not found."
        return 1
    fi
    if ! command -v go &> /dev/null; then
        if [ "$OS" = "arch" ] || [ "$OS" = "manjaro" ] || [ "$OS" = "endeavouros" ]; then
            sudo pacman -S --needed --noconfirm go
        fi
    fi
    if ! command -v go &> /dev/null; then
        echo "Go compiler not found; cannot build fyrpak."
        return 1
    fi
    echo "Building fyrpak (Go package manager & AUR helper)..."
    mkdir -p "$HOME/.local/bin" "$HOME/.config/fyr"
    pwd > "$HOME/.config/fyr/repo_path"
    (cd ./fyrpak && go build -trimpath -ldflags="-s -w" -o "$HOME/.local/bin/fyrpak" .)
    sudo install -Dm755 "$HOME/.local/bin/fyrpak" /usr/local/bin/fyrpak
    echo "fyrpak installed to /usr/local/bin/fyrpak and ~/.local/bin/fyrpak"
}

install_deps() {
    next_step "Installing system dependencies..."
    if [ "$OS" = "arch" ] || [ "$OS" = "manjaro" ] || [ "$OS" = "endeavouros" ]; then
        echo "Configuring pacman..."
        sudo sed -i '/^#\[multilib\]/{ s/^#//; n; s/^#//; }' /etc/pacman.conf
        sudo sed -i 's/^#Color/Color/' /etc/pacman.conf
        if ! grep -q "^ILoveCandy" /etc/pacman.conf; then
            sudo sed -i '/^Color/a ILoveCandy' /etc/pacman.conf
        fi
        
        echo "Updating system..."
        sudo pacman -Syu --noconfirm

        echo "Installing base-devel, git, and go for building packages..."
        sudo pacman -S --needed --noconfirm base-devel git go

        if ! command -v fyrpak &> /dev/null; then
            echo "fyrpak could not be found. Building and installing fyrpak..."
            install_fyrpak
        fi

        deps=( 
            "jq" "mesa-utils" "swaybg" "swaylock" "swayidle" "xorg-xwayland" "foot" "wmenu"
            "gtk-layer-shell" "xdg-desktop-portal" "xdg-desktop-portal-gtk"
            "xdg-desktop-portal-wlr" "xclip" "wl-clipboard" "brightnessctl"
            "wireplumber" "pipewire" "pipewire-pulse" "wlsunset" "cmake" "cpio" "pkg-config" "gcc" "wf-recorder" "grim" "ninja" "clang" "alsa-utils"
            "meson" "scdoc" "wayland-protocols" "pcre2" "json-c" "pango" "cairo" "gdk-pixbuf2" "unzip" "virt-viewer" "libvirt" "virt-install" "qemu-desktop"
            "bluez" "bluez-utils" "xdg-utils" "slurp" "libnotify" "polkit-gnome" "network-manager-applet" "pavucontrol" "playerctl" "jq" "libcanberra" "psmisc" "pamixer" "sddm" "accountsservice" "qt5-declarative" "qt5-quickcontrols" "qt5-quickcontrols2" "qt5-graphicaleffects" "kdeconnect"
            "ufw" "clamav" "rkhunter" "inotify-tools" "acl" "mpv" "ffmpeg" "noto-fonts-emoji" "zsh" "xorg-server-xvfb" "p7zip" "zip" "tar" "gzip" "bzip2" "nodejs" "npm" "clang" "virglrenderer" "libpulse" "rclone" "fuse3" "udisks2" "cryptsetup" "parted" "gptfdisk" "dosfstools" "exfatprogs" "ntfs-3g" "gnupg"
            "gstreamer" "gst-plugins-base" "gst-plugins-good" "gst-plugins-bad" "gst-plugins-ugly" "gst-libav" "gst-plugin-pipewire" "libcamera" "gst-plugin-libcamera"
            "wlroots0.20" "scenefx"
        )
        sudo pacman -S --needed --noconfirm "${deps[@]}"
        fyrpak -S --needed --noconfirm xdg-desktop-portal-termfilechooser-hunkyburrito-git

    elif [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
        echo "Updating system..."
        sudo apt-get update && sudo apt-get upgrade -y
        deps=(
            "swaybg" "swaylock" "swayidle" "xwayland" "foot" "libgtk-layer-shell-dev"
            "xdg-desktop-portal" "xdg-desktop-portal-gtk" "xdg-desktop-portal-wlr"
            "xclip" "wl-clipboard" "brightnessctl" "wireplumber" "pipewire" "pipewire-pulse" "cmake" "cpio" "libasound2-dev" "alsa-utils"
            "pkg-config" "gcc" "wf-recorder" "grim" "ninja-build" "clang" "curl" "git" "unzip" "xz-utils" "zip" "libglu1-mesa" "sway" "virt-viewer" "libvirt-clients" "libvirt-daemon-system" "virtinst" "qemu-kvm" "qemu-system"
            "bluez" "bluez-tools" "xdg-utils" "slurp" "libnotify-bin" "polkit-gnome" "network-manager-gnome" "pavucontrol" "playerctl" "jq" "libcanberra-gtk3-module" "libcanberra-gtk-module" "psmisc" "pamixer" "sddm" "accountsservice" "policykit-1-gnome" "qml-module-qtquick-controls" "qml-module-qtquick-controls2" "qml-module-qtgraphicaleffects" "kdeconnect"
            "ufw" "clamav" "rkhunter" "inotify-tools" "acl" "libmpv-dev" "ffmpeg" "fonts-noto-color-emoji" "zsh" "xvfb" "p7zip-full" "tar" "gzip" "bzip2" "nodejs" "npm" "clangd" "libvirglrenderer-dev" "libpulse-dev" "rclone" "fuse3" "udisks2" "cryptsetup" "parted" "gdisk" "dosfstools" "exfatprogs" "ntfs-3g" "gnupg"
            "libgstreamer1.0-dev" "libgstreamer-plugins-base1.0-dev" "gstreamer1.0-plugins-base" "gstreamer1.0-plugins-good" "gstreamer1.0-plugins-bad" "gstreamer1.0-libav"
        )
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${deps[@]}"
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y wlsunset wmenu swayfx || echo "Optional packages missed."

    elif [ "$OS" = "fedora" ]; then
        echo "Updating system..."
        sudo dnf upgrade -y
        deps=(
            "swaybg" "swaylock" "swayidle" "xorg-x11-server-Xwayland" "foot" "gtk-layer-shell-devel"
            "xdg-desktop-portal" "xdg-desktop-portal-gtk" "xdg-desktop-portal-wlr"
            "xclip" "wl-clipboard" "brightnessctl" "wireplumber" "pipewire" "pipewire-pulseaudio" "cmake" "cpio"
            "pkgconf" "gcc" "wf-recorder" "grim" "ninja-build" "clang" "curl" "git" "unzip" "zip" "mesa-libGLU" "sway" "virt-viewer" "libvirt" "virt-install" "qemu-kvm"
            "bluez" "bluez-utils" "xdg-utils" "slurp" "libnotify" "polkit-gnome" "nm-connection-editor" "pavucontrol" "playerctl" "jq" "libcanberra-gtk3" "psmisc" "pamixer" "sddm" "accountsservice" "lxqt-policykit" "qt5-qtquickcontrols" "qt5-qtquickcontrols2" "qt5-qtgraphicaleffects" "kdeconnect"
            "ufw" "clamav" "rkhunter" "inotify-tools" "acl" "mpv-libs-devel" "ffmpeg" "google-noto-emoji-color-fonts" "zsh" "xorg-x11-server-Xvfb" "p7zip" "tar" "gzip" "bzip2" "nodejs" "npm" "clang" "virglrenderer-devel" "rclone" "fuse3" "udisks2" "cryptsetup" "parted" "gdisk" "dosfstools" "exfatprogs" "ntfs-3g" "gnupg2"
            "gstreamer1-devel" "gstreamer1-plugins-base-devel" "gstreamer1-plugins-good" "gstreamer1-plugins-bad-free" "gstreamer1-libav"
        )
        sudo dnf install -y "${deps[@]}"
        sudo dnf install -y wlsunset wmenu swayfx || echo "Optional packages missed."
    fi
}

install_flutter() {
    next_step "Setting up Flutter..."
    echo "Ensuring Flutter 3.41.9 is installed in /opt/flutter..."
    
    # Check if flutter is already installed and version matches
    if [ -d "/opt/flutter/bin" ] && [ -f "/opt/flutter/version" ] && [ "$(cat /opt/flutter/version)" = "3.41.9" ]; then
        echo "Flutter 3.41.9 is already installed. Skipping download."
    else
        echo "Installing/Updating Flutter to 3.41.9..."
        sudo rm -rf /opt/flutter
        sudo git clone --depth 1 --branch 3.41.9 https://github.com/flutter/flutter.git /opt/flutter
    fi

    if [ ! -w "/opt/flutter" ] || [ ! -w "/opt/flutter/bin" ]; then
        sudo chown -R "$(id -u):$(id -g)" /opt/flutter
    fi

    export PATH="/opt/flutter/bin:$PATH"
    git config --global --add safe.directory /opt/flutter || true
    
    # Only run flutter doctor and config if needed or if first install
    if ! flutter --version &>/dev/null; then
        echo "Finalizing Flutter setup..."
        flutter doctor
        flutter config --enable-linux-desktop
    fi
    
    sudo ln -sf /opt/flutter/bin/flutter /usr/local/bin/flutter
    sudo ln -sf /opt/flutter/bin/dart /usr/local/bin/dart
}

build_swayfx() {
    next_step "Building SwayFX..."
    echo "Building and installing local swayfx..."
    if [ -d "./swayfx" ]; then
        cd ./swayfx
        if [ ! -f "build/build.ninja" ] || ! grep -q "subprojects/scenefx/libscenefx-0.5.a" build/build.ninja 2>/dev/null; then
            rm -rf build
            meson setup build
        fi
        ninja -C build
        sudo ninja -C build install
        cd ..
    fi
}



reinstall_app() {
    local app=$1
    next_step "Building $app..."
    if [ -d "./$app" ]; then
        echo "Building $app..."
        cd "./$app"
        if [ "$CLEAN_BUILD" = "true" ]; then
            flutter clean || true
        fi
        if [ ! -f "linux/CMakeLists.txt" ]; then
            flutter create --platforms=linux .
        fi
        flutter pub get
        xvfb-run -a flutter build linux
        
        echo "Installing $app to /opt/$app..."
        sudo rm -rf "/opt/$app"
        sudo mkdir -p "/opt/$app"
        sudo cp -r build/linux/x64/release/bundle/* "/opt/$app/"
        cd ..
        
        setup_app_configs "$app"
        cleanup_legacy_user_override "$app"
        restart_overlay_daemon_if_running "$app"
    else
        echo "Error: Directory ./$app not found!"
        exit 1
    fi
}

restart_overlay_daemon_if_running() {
    local app=$1
    case "$app" in
        fyrsearch|fyroverview|fyrwindowoverview|fyremoji|fyrclipboard)
            if command -v swaymsg &> /dev/null && swaymsg -t get_version &> /dev/null; then
                pkill -x "$app" 2>/dev/null || true
                rm -f "$HOME/.config/fyr/overlay-$app.sock"
                nohup "/opt/$app/$app" > /dev/null 2>&1 &
            fi
            ;;
        fyrdock)
            if command -v swaymsg &> /dev/null && swaymsg -t get_version &> /dev/null; then
                pkill -x fyrdock 2>/dev/null || true
                nohup /opt/fyrdock/fyrdock > /dev/null 2>&1 &
            fi
            ;;
        fyrtaskbar)
            if command -v swaymsg &> /dev/null && swaymsg -t get_version &> /dev/null; then
                pkill -x fyrtaskbar 2>/dev/null || true
                nohup /opt/fyrtaskbar/fyrtaskbar > /dev/null 2>&1 &
                nohup /opt/fyrtaskbar/fyrtaskbar --desktop > /dev/null 2>&1 &
            fi
            ;;
    esac
}

cleanup_legacy_user_override() {
    local app=$1
    # Older installs placed bundles in ~/.local/share/fyrDE/$app and desktop files
    # in ~/.local/share/applications/$app.desktop, which shadow /opt/$app and
    # /usr/share/applications/$app.desktop. Clean those overrides up so updated
    # /opt builds are always what launchers execute.
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
    echo "Setting up configuration for $app..."
    
    case $app in
        "fyrterm")
            sudo ln -sf /opt/fyrterm/fyrterm /usr/local/bin/fyrterm
            if [ -f "./fyrterm/assets/icons/terminal.png" ]; then
                sudo mkdir -p /usr/share/icons/hicolor/512x512/apps
                sudo cp ./fyrterm/assets/icons/terminal.png /usr/share/icons/hicolor/512x512/apps/fyrterm.png
            fi
            sudo tee /usr/share/applications/fyrterm.desktop > /dev/null <<'EOF'
[Desktop Entry]
Version=1.0
Name=Terminal
GenericName=Terminal Emulator
Comment=A flutter terminal emulator
Exec=/usr/local/bin/fyrterm
Icon=fyrterm
Terminal=false
Type=Application
Categories=System;TerminalEmulator;
EOF
            sudo update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator /usr/local/bin/fyrterm 50 || true
            ;;
        "fyrfiles")
            if [ -f "/opt/fyrfiles/fyrfiles" ]; then
                sudo ln -sf /opt/fyrfiles/fyrfiles /usr/local/bin/fyrfiles
            elif [ -f "/opt/fyrfiles/fyr_files" ]; then
                sudo ln -sf /opt/fyrfiles/fyr_files /usr/local/bin/fyrfiles
            fi
            sudo ln -sf /usr/local/bin/fyrfiles /usr/local/bin/fyr_files 2>/dev/null || true
            if [ -f "./fyrfiles/assets/icons/folderfile.png" ]; then
                sudo mkdir -p /usr/share/icons/hicolor/512x512/apps
                sudo cp ./fyrfiles/assets/icons/folderfile.png /usr/share/icons/hicolor/512x512/apps/fyrfiles.png
            fi
            sudo tee /usr/share/applications/fyrfiles.desktop > /dev/null <<'EOF'
[Desktop Entry]
Name=fyrFiles
Comment=A modern, custom file manager
Exec=/usr/local/bin/fyrfiles %U
Icon=fyrfiles
Terminal=false
Type=Application
MimeType=inode/directory;
Categories=Utility;System;FileTools;
EOF
            sudo tee /usr/local/bin/fyr_files_picker > /dev/null <<'EOF'
#!/bin/bash
multiple="$1"
directory="$2"
save="$3"
path="$4"
out="$5"

fyrfiles_bin=""
for candidate in "$HOME/.local/bin/fyrfiles" "$HOME/.local/share/fyrDE/fyrfiles/fyrfiles" "/usr/local/bin/fyrfiles" "/usr/bin/fyrfiles" "/opt/fyrfiles/fyrfiles"; do
    if [ -x "$candidate" ]; then
        fyrfiles_bin="$candidate"
        break
    fi
done
if [ -z "$fyrfiles_bin" ]; then
    fyrfiles_bin="$(command -v fyrfiles 2>/dev/null)"
fi

cmd_args=("--picker")
if [ "$multiple" = "1" ]; then
    cmd_args+=("--multiple")
fi
if [ "$directory" = "1" ]; then
    cmd_args+=("--directory")
fi
if [ "$save" = "1" ]; then
    cmd_args+=("--save")
fi
cmd_args+=("$path")

"$fyrfiles_bin" "${cmd_args[@]}" > "$out"

if [ "$save" = "1" ] && [ -f "$path" ] && grep -q "xdg-desktop-portal-termfilechooser" "$path" 2>/dev/null; then
    rm -f "$path"
fi

if [ ! -s "$out" ]; then exit 1; fi

if [ "$save" = "1" ]; then
    chosen="$(head -n 1 "$out")"
    if [ -d "$chosen" ] && [ -n "$path" ]; then
        printf "%s/%s\n" "${chosen%/}" "$(basename "$path")" > "$out"
    fi
fi

exit 0
EOF
            sudo chmod +x /usr/local/bin/fyr_files_picker

            sudo tee /usr/local/bin/zenity > /dev/null <<'EOF'
#!/bin/bash
# zenity / qarma / kdialog compatibility wrapper routing file selection to fyrfiles

target_path=""
multiple=false
directory_only=false
save_file=false
title=""
separator="|"

while [ $# -gt 0 ]; do
    case "$1" in
        --file-selection)
            shift
            ;;
        --title)
            title="$2"
            shift 2
            ;;
        --title=*)
            title="${1#*=}"
            shift
            ;;
        --filename)
            target_path="$2"
            shift 2
            ;;
        --filename=*)
            target_path="${1#*=}"
            shift
            ;;
        --getopenfilename|--getsavefilename|--getexistingdirectory)
            if [ "$1" = "--getexistingdirectory" ]; then
                directory_only=true
            elif [ "$1" = "--getsavefilename" ]; then
                save_file=true
            fi
            shift
            if [ $# -gt 0 ] && [[ "$1" != -* ]]; then
                target_path="$1"
                shift
            fi
            ;;
        --multiple)
            multiple=true
            shift
            ;;
        --separate-output)
            multiple=true
            separator=$'\n'
            shift
            ;;
        --directory)
            directory_only=true
            shift
            ;;
        --save)
            save_file=true
            shift
            ;;
        --separator=*)
            separator="${1#*=}"
            shift
            ;;
        --separator)
            separator="$2"
            shift 2
            ;;
        --confirm-overwrite)
            shift
            ;;
        --file-filter=*)
            shift
            ;;
        --file-filter)
            shift 2
            ;;
        *)
            if [[ "$1" != -* ]] && [ -z "$target_path" ]; then
                target_path="$1"
            fi
            shift
            ;;
    esac
done

if [ -z "$target_path" ]; then
    target_path="$HOME"
fi

fyrfiles_bin=""
for candidate in "$HOME/.local/bin/fyrfiles" "$HOME/.local/share/fyrDE/fyrfiles/fyrfiles" "/usr/local/bin/fyrfiles" "/usr/bin/fyrfiles" "/opt/fyrfiles/fyrfiles"; do
    if [ -x "$candidate" ]; then
        fyrfiles_bin="$candidate"
        break
    fi
done

if [ -z "$fyrfiles_bin" ]; then
    fyrfiles_bin="$(command -v fyrfiles 2>/dev/null)"
fi

if [ -z "$fyrfiles_bin" ] || [ ! -x "$fyrfiles_bin" ]; then
    echo "zenity: fyrfiles executable not found" >&2
    exit 1
fi

cmd_args=("--picker")
if [ "$multiple" = true ]; then
    cmd_args+=("--multiple")
fi
if [ "$directory_only" = true ]; then
    cmd_args+=("--directory")
fi
if [ "$save_file" = true ]; then
    cmd_args+=("--save")
fi
if [ -n "$title" ]; then
    cmd_args+=("--title=$title")
fi
cmd_args+=("$target_path")

selected="$("$fyrfiles_bin" "${cmd_args[@]}")"
exit_code=$?

if [ $exit_code -ne 0 ] || [ -z "$selected" ]; then
    exit 1
fi

if [ "$save_file" = true ] && [ -d "$selected" ] && [ -n "$target_path" ] && [ ! -d "$target_path" ]; then
    selected="${selected%/}/$(basename "$target_path")"
fi

if [ "$multiple" = true ]; then
    echo "$selected" | tr '\n' "$separator" | sed "s/$separator\$//"
else
    echo "$selected" | head -n 1
fi

exit 0
EOF
            sudo chmod +x /usr/local/bin/zenity
            sudo ln -sf /usr/local/bin/zenity /usr/local/bin/qarma
            sudo ln -sf /usr/local/bin/zenity /usr/local/bin/kdialog

            mkdir -p ~/.local/bin
            cp /usr/local/bin/fyr_files_picker ~/.local/bin/fyr_files_picker 2>/dev/null || true
            chmod +x ~/.local/bin/fyr_files_picker 2>/dev/null || true
            cp /usr/local/bin/zenity ~/.local/bin/zenity 2>/dev/null || true
            ln -sf zenity ~/.local/bin/qarma 2>/dev/null || true
            ln -sf zenity ~/.local/bin/kdialog 2>/dev/null || true

            mkdir -p ~/.config/xdg-desktop-portal-termfilechooser
            echo -e "[filechooser]\ncmd=$HOME/.local/bin/fyr_files_picker\ncreate_help_file=0" > ~/.config/xdg-desktop-portal-termfilechooser/config
            mkdir -p ~/.config/xdg-desktop-portal
            echo -e "[preferred]\ndefault=wlr;gtk;\norg.freedesktop.impl.portal.FileChooser=termfilechooser" > ~/.config/xdg-desktop-portal/sway-portals.conf
            ;;
        "fyrstore")
            sudo ln -sf /opt/fyrstore/fyrstore /usr/local/bin/fyrstore
            if [ -f "./fyrstore/assets/icons/shop.png" ]; then
                sudo mkdir -p /usr/share/icons/hicolor/512x512/apps
                sudo cp ./fyrstore/assets/icons/shop.png /usr/share/icons/hicolor/512x512/apps/fyrstore.png
            fi
            sudo tee /usr/share/applications/fyrstore.desktop > /dev/null <<'EOF'
[Desktop Entry]
Name=fyrStore
Type=Application
Exec=/usr/local/bin/fyrstore
Icon=fyrstore
Terminal=false
Categories=System;Settings;
EOF
            ;;
        "fyrsettings")
            sudo ln -sf /opt/fyrsettings/fyrsettings /usr/local/bin/fyrsettings
            if [ -f "./fyrsettings/assets/icons/settings.png" ]; then
                sudo mkdir -p /usr/share/icons/hicolor/512x512/apps
                sudo cp ./fyrsettings/assets/icons/settings.png /usr/share/icons/hicolor/512x512/apps/fyrsettings.png
            fi
            sudo tee /usr/share/applications/fyrsettings.desktop > /dev/null <<'EOF'
[Desktop Entry]
Name=Settings
GenericName=Fyr Settings
Comment=System settings for FyrDE
Exec=/usr/local/bin/fyrsettings
Icon=fyrsettings
Terminal=false
Type=Application
Categories=System;Settings;
Keywords=fyr;fyrsettings;settings;preferences;display;audio;sound;system;appearance;
EOF
            ;;
        "fyrvirt")
            sudo ln -sf /opt/fyrvirt/fyrvirt /usr/local/bin/fyrvirt
            if [ -f "./fyrvirt/assets/icons/vm.png" ]; then
                sudo mkdir -p /usr/share/icons/hicolor/512x512/apps
                sudo cp ./fyrvirt/assets/icons/vm.png /usr/share/icons/hicolor/512x512/apps/fyrvirt.png
            fi
            sudo tee /usr/share/applications/fyrvirt.desktop > /dev/null <<'EOF'
[Desktop Entry]
Name=fyrVM
Comment=Virtual Machine Manager for FyrDE
Exec=/usr/local/bin/fyrvirt
Icon=fyrvirt
Terminal=false
Type=Application
Categories=System;Virtualization;
EOF
            ;;
        "fyrav")
            sudo ln -sf /opt/fyrav/fyrav /usr/local/bin/fyrav
            if [ -f "./fyrav/assets/icons/antibac.png" ]; then
                sudo mkdir -p /usr/share/icons/hicolor/512x512/apps
                sudo cp ./fyrav/assets/icons/antibac.png /usr/share/icons/hicolor/512x512/apps/fyrav.png
            fi
            sudo tee /usr/share/applications/fyrav.desktop > /dev/null <<'EOF'
[Desktop Entry]
Name=FyrAV
Comment=Anti-Virus & System Security
Exec=/usr/local/bin/fyrav
Icon=fyrav
Terminal=false
Type=Application
Categories=System;Security;
EOF
            if [ -f "./fyrav/fyrav.service" ]; then
                mkdir -p ~/.config/systemd/user
                cp ./fyrav/fyrav.service ~/.config/systemd/user/fyrav.service
                systemctl --user daemon-reload
                systemctl --user enable fyrav.service || true
            fi
            ;;
        "fyrvideo")
            sudo ln -sf /opt/fyrvideo/fyrvideo /usr/local/bin/fyrvideo
            if [ -f "./fyrvideo/assets/icons/videoPlayer.png" ]; then
                sudo mkdir -p /usr/share/icons/hicolor/512x512/apps
                sudo cp ./fyrvideo/assets/icons/videoPlayer.png /usr/share/icons/hicolor/512x512/apps/fyrvideo.png
            fi
            sudo tee /usr/share/applications/fyrvideo.desktop > /dev/null <<'EOF'
[Desktop Entry]
Name=Watchbox
Comment=Media player for FyrDE
Exec=/usr/local/bin/fyrvideo %f
Icon=fyrvideo
Terminal=false
Type=Application
Categories=AudioVideo;Video;Player;
MimeType=video/mp4;video/x-matroska;video/webm;video/quicktime;video/x-msvideo;video/x-flv;video/x-ms-wmv;video/mpeg;
EOF
            xdg-mime default fyrvideo.desktop video/mp4 video/x-matroska video/webm video/quicktime video/x-msvideo video/x-flv video/x-ms-wmv video/mpeg || true
            ;;
        "fyrphone")
            sudo ln -sf /opt/fyrphone/fyrphone /usr/local/bin/fyrphone
            sudo ln -sf /opt/fyrphone/fyrphone /usr/local/bin/fyrconnect
            if [ -f "./fyrphone/assets/icons/connect.png" ]; then
                sudo mkdir -p /usr/share/icons/hicolor/512x512/apps
                sudo cp ./fyrphone/assets/icons/connect.png /usr/share/icons/hicolor/512x512/apps/fyrphone.png
            fi
            sudo tee /usr/share/applications/fyrphone.desktop > /dev/null <<'EOF'
[Desktop Entry]
Name=fyrConnect
Comment=Mobile device manager for FyrDE
Exec=/usr/local/bin/fyrphone
Icon=fyrphone
Terminal=false
Type=Application
Categories=System;Network;
EOF
            # Allow KDE Connect LAN discovery & pairing through UFW if installed
            if command -v ufw &> /dev/null; then
                sudo ufw allow 1714:1764/tcp comment 'KDE Connect / fyrConnect' || true
                sudo ufw allow 1714:1764/udp comment 'KDE Connect / fyrConnect' || true
            fi
            ;;
        "fyrtext")
            sudo ln -sf /opt/fyrtext/fyrtext /usr/local/bin/fyrtext
            if [ -f "./fyrtext/assets/icons/textEditor.png" ]; then
                sudo mkdir -p /usr/share/icons/hicolor/512x512/apps
                sudo cp ./fyrtext/assets/icons/textEditor.png /usr/share/icons/hicolor/512x512/apps/fyrtext.png
            fi
            sudo cp ./fyrtext/fyrtext.desktop /usr/share/applications/fyrtext.desktop
            xdg-mime default fyrtext.desktop text/plain || true
            ;;
        "fyrdaw")
            sudo ln -sf /opt/fyrdaw/fyrdaw /usr/local/bin/fyrdaw
            if [ -f "./fyrdaw/assets/icons/music2.png" ]; then
                sudo mkdir -p /usr/share/icons/hicolor/512x512/apps
                sudo cp ./fyrdaw/assets/icons/music2.png /usr/share/icons/hicolor/512x512/apps/fyrdaw.png
            fi
            sudo cp ./fyrdaw/fyrdaw.desktop /usr/share/applications/fyrdaw.desktop
            ;;
        "fyrcalculator")
            sudo ln -sf /opt/fyrcalculator/fyrcalculator /usr/local/bin/fyrcalculator
            if [ -f "./fyrcalculator/assets/icons/calculator.png" ]; then
                sudo mkdir -p /usr/share/icons/hicolor/512x512/apps
                sudo cp ./fyrcalculator/assets/icons/calculator.png /usr/share/icons/hicolor/512x512/apps/fyrcalculator.png
            fi
            sudo tee /usr/share/applications/fyrcalculator.desktop > /dev/null <<'EOF'
[Desktop Entry]
Name=Calculator
Comment=Calculator
Exec=/usr/local/bin/fyrcalculator
Icon=fyrcalculator
Terminal=false
Type=Application
Categories=Utility;Calculator;
EOF
            ;;
        "fyrcode")
            sudo ln -sf /opt/fyrcode/fyrcode /usr/local/bin/fyrcode
            if [ -f "./fyrcode/assets/icons/code.png" ]; then
                sudo mkdir -p /usr/share/icons/hicolor/512x512/apps
                sudo cp ./fyrcode/assets/icons/code.png /usr/share/icons/hicolor/512x512/apps/fyrcode.png
            fi
            sudo tee /usr/share/applications/fyrcode.desktop > /dev/null <<'EOF'
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
        "fyrmusic")
            sudo ln -sf /opt/fyrmusic/fyrmusic /usr/local/bin/fyrmusic
            if [ -f "./fyrmusic/assets/icons/music.png" ]; then
                sudo mkdir -p /usr/share/icons/hicolor/512x512/apps
                sudo cp ./fyrmusic/assets/icons/music.png /usr/share/icons/hicolor/512x512/apps/fyrmusic.png
            fi
            sudo tee /usr/share/applications/fyrmusic.desktop > /dev/null <<'EOF'
[Desktop Entry]
Name=Music
Comment=Music library and player for FyrDE
Exec=/usr/local/bin/fyrmusic %f
Icon=fyrmusic
Terminal=false
Type=Application
Categories=AudioVideo;Audio;Player;
MimeType=audio/mpeg;audio/x-wav;audio/flac;audio/ogg;audio/mp4;
EOF
            xdg-mime default fyrmusic.desktop audio/mpeg audio/x-wav audio/flac audio/ogg audio/mp4 || true
            ;;
        "fyrphotos")
            sudo ln -sf /opt/fyrphotos/fyrphotos /usr/local/bin/fyrphotos
            if [ -f "./fyrphotos/assets/icons/photos.png" ]; then
                sudo mkdir -p /usr/share/icons/hicolor/512x512/apps
                sudo cp ./fyrphotos/assets/icons/photos.png /usr/share/icons/hicolor/512x512/apps/fyrphotos.png
            fi
            sudo tee /usr/share/applications/fyrphotos.desktop > /dev/null <<'EOF'
[Desktop Entry]
Name=Photos
Comment=Photo library and viewer for FyrDE
Exec=/usr/local/bin/fyrphotos %f
Icon=fyrphotos
Terminal=false
Type=Application
Categories=Graphics;Viewer;
MimeType=image/jpeg;image/png;image/gif;image/webp;image/x-ms-bmp;
EOF
            xdg-mime default fyrphotos.desktop image/jpeg image/png image/gif image/webp image/x-ms-bmp || true
            ;;
        "fyrcamera")
            sudo ln -sf /opt/fyrcamera/fyrcamera /usr/local/bin/fyrcamera
            if [ -f "./fyrcamera/assets/icons/camera.png" ]; then
                sudo mkdir -p /usr/share/icons/hicolor/512x512/apps
                sudo cp ./fyrcamera/assets/icons/camera.png /usr/share/icons/hicolor/512x512/apps/fyrcamera.png
            fi
            sudo tee /usr/share/applications/fyrcamera.desktop > /dev/null <<'EOF'
[Desktop Entry]
Name=Camera
Comment=Camera application for FyrDE
Exec=/usr/local/bin/fyrcamera
Icon=fyrcamera
Terminal=false
Type=Application
Categories=AudioVideo;Video;
EOF
            ;;
        "fyrbrowser")
            sudo ln -sf /opt/fyrbrowser/fyrbrowser /usr/local/bin/fyrbrowser
            if [ -f "./fyrbrowser/assets/icons/browser.png" ]; then
                sudo mkdir -p /usr/share/icons/hicolor/512x512/apps
                sudo cp ./fyrbrowser/assets/icons/browser.png /usr/share/icons/hicolor/512x512/apps/fyrbrowser.png
            fi
            sudo tee /usr/share/applications/fyrbrowser.desktop > /dev/null <<'EOF'
[Desktop Entry]
Version=1.0
Name=Goose
GenericName=Web Browser
Comment=CEF-based web browser for FyrDE
Exec=/usr/local/bin/fyrbrowser %u
Icon=fyrbrowser
Terminal=false
Type=Application
Categories=Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;application/xml;image/svg+xml;application/rss+xml;application/rdf+xml;x-scheme-handler/http;x-scheme-handler/https;x-scheme-handler/ftp;
StartupNotify=true
EOF
            xdg-settings set default-web-browser fyrbrowser.desktop || true
            xdg-mime default fyrbrowser.desktop text/html text/xml application/xhtml+xml x-scheme-handler/http x-scheme-handler/https || true
            ;;
        "fyrjournal")
            sudo ln -sf /opt/fyrjournal/fyrjournal /usr/local/bin/fyrjournal
            if [ -f "./fyrjournal/assets/icons/journal.png" ]; then
                sudo mkdir -p /usr/share/icons/hicolor/512x512/apps
                sudo cp ./fyrjournal/assets/icons/journal.png /usr/share/icons/hicolor/512x512/apps/fyrjournal.png
            fi
            sudo cp ./fyrjournal/fyrjournal.desktop /usr/share/applications/fyrjournal.desktop
            ;;
        "fyrcalender")
            sudo ln -sf /opt/fyrcalender/fyrcalender /usr/local/bin/fyrcalender
            if [ -f "./fyrcalender/assets/icons/calendar.png" ]; then
                sudo mkdir -p /usr/share/icons/hicolor/512x512/apps
                sudo cp ./fyrcalender/assets/icons/calendar.png /usr/share/icons/hicolor/512x512/apps/fyrcalender.png
            fi
            sudo tee /usr/share/applications/fyrcalender.desktop > /dev/null <<'EOF'
[Desktop Entry]
Name=Calendar
Comment=Modern calendar for FyrDE
Exec=/usr/local/bin/fyrcalender
Icon=fyrcalender
Terminal=false
Type=Application
Categories=Office;Calendar;Utility;
EOF
            ;;
        "fyrclock")
            sudo ln -sf /opt/fyrclock/fyrclock /usr/local/bin/fyrclock
            if [ -f "./fyrclock/assets/icons/clock.png" ]; then
                sudo mkdir -p /usr/share/icons/hicolor/512x512/apps
                sudo cp ./fyrclock/assets/icons/clock.png /usr/share/icons/hicolor/512x512/apps/fyrclock.png
            fi
            sudo tee /usr/share/applications/fyrclock.desktop > /dev/null <<'EOF'
[Desktop Entry]
Name=Clock
Comment=Sleek clock with World Clock, Alarm, Stopwatch, and Timer
Exec=/usr/local/bin/fyrclock
Icon=fyrclock
Terminal=false
Type=Application
Categories=Utility;Clock;
EOF
            ;;
        "fyrtorrent")
            sudo ln -sf /opt/fyrtorrent/fyrtorrent /usr/local/bin/fyrtorrent
            sudo tee /usr/share/applications/fyrtorrent.desktop > /dev/null <<'EOF'
[Desktop Entry]
Name=fyrTorrent
Comment=A premium torrent client for FyrDE
Exec=/usr/local/bin/fyrtorrent %U
Icon=transmission
Terminal=false
Type=Application
Categories=Network;FileTransfer;P2P;
MimeType=application/x-bittorrent;x-scheme-handler/magnet;
EOF
            xdg-mime default fyrtorrent.desktop application/x-bittorrent x-scheme-handler/magnet || true
            ;;
        "fyrapi")
            sudo ln -sf /opt/fyrapi/fyrapi /usr/local/bin/fyrapi
            sudo tee /usr/share/applications/fyrapi.desktop > /dev/null <<'EOF'
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
        "fyrgraphics")
            sudo ln -sf /opt/fyrgraphics/fyrgraphics /usr/local/bin/fyrgraphics
            if [ -f "./fyrgraphics/assets/icons/fyrgraphics.png" ]; then
                sudo mkdir -p /usr/share/icons/hicolor/512x512/apps
                sudo cp ./fyrgraphics/assets/icons/fyrgraphics.png /usr/share/icons/hicolor/512x512/apps/fyrgraphics.png
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
        "devign")
            sudo ln -sf /opt/devign/devign /usr/local/bin/devign
            sudo tee /usr/share/applications/devign.desktop > /dev/null <<'EOF'
[Desktop Entry]
Name=devign
GenericName=UI/UX Design & Prototyping Studio
Comment=Vector UI design, auto-layout, interactive prototyping, and code export studio for FyrDE
Exec=/usr/local/bin/devign %f
Icon=applications-graphics
Terminal=false
Type=Application
Categories=Graphics;2DGraphics;VectorGraphics;Development;
MimeType=application/x-devign;image/svg+xml;
Keywords=figma;design;vector;ui;ux;prototype;wireframe;devign;
EOF
            ;;
        "fyremu")
            sudo ln -sf /opt/fyremu/fyremu /usr/local/bin/fyremu
            if [ -f "./fyremu/assets/icons/fyremu.png" ]; then
                sudo mkdir -p /usr/share/icons/hicolor/512x512/apps
                sudo cp ./fyremu/assets/icons/fyremu.png /usr/share/icons/hicolor/512x512/apps/fyremu.png
            fi
            sudo tee /usr/share/applications/fyremu.desktop > /dev/null <<'EOF'
[Desktop Entry]
Name=fyrEmu
GenericName=Game Emulator
Comment=Multi-platform retro game emulator (GBC, GBA, NES, SNES) for FyrDE
Exec=/usr/local/bin/fyremu %f
Icon=fyremu
Terminal=false
Type=Application
Categories=Game;Emulator;
MimeType=application/x-gameboy-rom;application/x-gameboy-color-rom;application/x-gba-rom;application/x-nes-rom;application/x-snes-rom;application/x-genesis-rom;
Keywords=emulator;gameboy;gbc;gba;nes;snes;retro;roms;
EOF
            ;;
        "fyrdirector")
            sudo ln -sf /opt/fyrdirector/fyrdirector /usr/local/bin/fyrdirector
            if [ -f "./fyrdirector/assets/icons/fyrdirector.png" ]; then
                sudo mkdir -p /usr/share/icons/hicolor/512x512/apps
                sudo cp ./fyrdirector/assets/icons/fyrdirector.png /usr/share/icons/hicolor/512x512/apps/fyrdirector.png
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
        "fyrdisks")
            sudo ln -sf /opt/fyrdisks/fyrdisks /usr/local/bin/fyrdisks
            if [ -f "./fyrdisks/assets/icons/fyrdisks.png" ]; then
                sudo mkdir -p /usr/share/icons/hicolor/512x512/apps
                sudo cp ./fyrdisks/assets/icons/fyrdisks.png /usr/share/icons/hicolor/512x512/apps/fyrdisks.png
            fi
            sudo tee /usr/share/applications/fyrdisks.desktop > /dev/null <<'EOF'
[Desktop Entry]
Name=fyrDisks
GenericName=Disks & ISO Flasher
Comment=Manage disks, partitions, LUKS encrypted volumes, and flash ISOs to USB drives
Exec=/usr/local/bin/fyrdisks %f
Icon=fyrdisks
Terminal=false
Type=Application
Categories=System;Utility;HardwareSettings;
MimeType=application/x-iso9660-image;application/x-raw-disk-image;inode/blockdevice;
Keywords=disk;partition;usb;iso;flash;format;luks;encrypt;drive;
EOF
            ;;
        "fyrmonitor")
            sudo ln -sf /opt/fyrmonitor/fyrmonitor /usr/local/bin/fyrmonitor
            if [ -f "./fyrmonitor/assets/icons/fyrmonitor.png" ]; then
                sudo mkdir -p /usr/share/icons/hicolor/512x512/apps
                sudo cp ./fyrmonitor/assets/icons/fyrmonitor.png /usr/share/icons/hicolor/512x512/apps/fyrmonitor.png
            fi
            sudo tee /usr/share/applications/fyrmonitor.desktop > /dev/null <<'EOF'
[Desktop Entry]
Name=fyrMonitor
GenericName=Task Manager
Comment=Monitor open windows, running processes, and system performance
Exec=/usr/local/bin/fyrmonitor
Icon=fyrmonitor
Terminal=false
Type=Application
Categories=System;Monitor;Utility;
Keywords=task manager;processes;monitor;system;cpu;memory;performance;activity;
EOF
            ;;
        "fyrdocs")
            sudo ln -sf /opt/fyrdocs/fyrdocs /usr/local/bin/fyrdocs
            if [ -f "./fyrdocs/assets/icons/fyrdocs.png" ]; then
                sudo mkdir -p /usr/share/icons/hicolor/512x512/apps
                sudo cp ./fyrdocs/assets/icons/fyrdocs.png /usr/share/icons/hicolor/512x512/apps/fyrdocs.png
            fi
            sudo cp ./fyrdocs/fyrdocs.desktop /usr/share/applications/fyrdocs.desktop
            xdg-mime default fyrdocs.desktop application/vnd.oasis.opendocument.text application/vnd.openxmlformats-officedocument.wordprocessingml.document || true
            ;;
        "fyrsheets")
            sudo ln -sf /opt/fyrsheets/fyrsheets /usr/local/bin/fyrsheets
            if [ -f "./fyrsheets/assets/icons/fyrsheets.png" ]; then
                sudo mkdir -p /usr/share/icons/hicolor/512x512/apps
                sudo cp ./fyrsheets/assets/icons/fyrsheets.png /usr/share/icons/hicolor/512x512/apps/fyrsheets.png
            fi
            sudo cp ./fyrsheets/fyrsheets.desktop /usr/share/applications/fyrsheets.desktop
            xdg-mime default fyrsheets.desktop application/vnd.oasis.opendocument.spreadsheet application/vnd.openxmlformats-officedocument.spreadsheetml.sheet text/csv || true
            ;;
        "fyrslides")
            sudo ln -sf /opt/fyrslides/fyrslides /usr/local/bin/fyrslides
            if [ -f "./fyrslides/assets/icons/fyrslides.png" ]; then
                sudo mkdir -p /usr/share/icons/hicolor/512x512/apps
                sudo cp ./fyrslides/assets/icons/fyrslides.png /usr/share/icons/hicolor/512x512/apps/fyrslides.png
            fi
            sudo cp ./fyrslides/fyrslides.desktop /usr/share/applications/fyrslides.desktop
            xdg-mime default fyrslides.desktop application/vnd.oasis.opendocument.presentation application/vnd.openxmlformats-officedocument.presentationml.presentation || true
            ;;
        "fyrpdf")
            sudo ln -sf /opt/fyrpdf/fyrpdf /usr/local/bin/fyrpdf
            if [ -f "./fyrpdf/assets/icons/fyrpdf.png" ]; then
                sudo mkdir -p /usr/share/icons/hicolor/512x512/apps
                sudo cp ./fyrpdf/assets/icons/fyrpdf.png /usr/share/icons/hicolor/512x512/apps/fyrpdf.png
            fi
            sudo cp ./fyrpdf/fyrpdf.desktop /usr/share/applications/fyrpdf.desktop
            xdg-mime default fyrpdf.desktop application/pdf || true
            ;;
        "fyrdb")
            sudo ln -sf /opt/fyrdb/fyrdb /usr/local/bin/fyrdb
            if [ -f "./fyrdb/assets/icons/fyrdb.png" ]; then
                sudo mkdir -p /usr/share/icons/hicolor/512x512/apps
                sudo cp ./fyrdb/assets/icons/fyrdb.png /usr/share/icons/hicolor/512x512/apps/fyrdb.png
            fi
            sudo cp ./fyrdb/fyrdb.desktop /usr/share/applications/fyrdb.desktop
            ;;
        "fyrpods")
            sudo ln -sf /opt/fyrpods/fyrpods /usr/local/bin/fyrpods
            if [ -f "./fyrpods/assets/icons/fyrpods.png" ]; then
                sudo mkdir -p /usr/share/icons/hicolor/512x512/apps
                sudo cp ./fyrpods/assets/icons/fyrpods.png /usr/share/icons/hicolor/512x512/apps/fyrpods.png
            fi
            sudo cp ./fyrpods/fyrpods.desktop /usr/share/applications/fyrpods.desktop
            ;;
        "fyrdock"|"fyrtaskbar"|"fyroverview"|"fyrwindowoverview"|"fyrsearch"|"fyrhelp"|"fyremoji"|"fyrclipboard")
            sudo ln -sf "/opt/$app/$app" "/usr/local/bin/$app"
            ;;
    esac
    
    if command -v update-desktop-database &> /dev/null; then
        sudo update-desktop-database /usr/share/applications || true
    fi
}

hide_redundant_apps() {
    next_step "Hiding redundant applications..."
    echo "Hiding mpv and kdeconnect from menus..."
    
    mkdir -p "$HOME/.local/share/applications"
    
    # Redundant Apps
    REDUNDANT_DESKTOPS=(
        "mpv.desktop"
        "org.kde.kdeconnect.app.desktop"
        "org.kde.kdeconnect.sms.desktop"
        "org.kde.kdeconnect.nonplasma.desktop"
        "org.kde.kdeconnect.settings.desktop"
        "org.kde.kdeconnect.handler.desktop"
        "foot.desktop"
        "footclient.desktop"
        "foot-server.desktop"
        "pavucontrol.desktop"
        "nm-connection-editor.desktop"
        "avahi-discover.desktop"
        "bssh.desktop"
        "bvnc.desktop"
        "cmake-gui.desktop"
        "qv4l2.desktop"
        "qvidcap.desktop"
        "zenity.desktop"
        "ktelnetservice6.desktop"
        "google-maps-geo-handler.desktop"
        "openstreetmap-geo-handler.desktop"
        "wheel-geo-handler.desktop"
        "qemu.desktop"
        "org.pulseaudio.pavucontrol.desktop"
        "remote-viewer.desktop"
        "virt-viewer.desktop"
    )

    for desktop in "${REDUNDANT_DESKTOPS[@]}"; do
        if [ -f "/usr/share/applications/$desktop" ]; then
            echo "Overriding $desktop in local share..."
            cp "/usr/share/applications/$desktop" "$HOME/.local/share/applications/"
            # Remove any existing NoDisplay= line to avoid duplicates
            sed -i '/^NoDisplay=/d' "$HOME/.local/share/applications/$desktop"
            # Add NoDisplay=true
            echo "NoDisplay=true" >> "$HOME/.local/share/applications/$desktop"
        fi
    done
    
    if command -v update-desktop-database &> /dev/null; then
        update-desktop-database "$HOME/.local/share/applications" || true
    fi
}

setup_fetch() {
    next_step "Installing Fyr Fetch..."
    mkdir -p ~/.config/fyr
    cat << 'EOF' > ~/.config/fyr/fyr_fetch
#!/bin/bash

# ANSI color codes
PURPLE='\033[38;5;147m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ASCII Art
logo=(
"        %          "
"         %%%        "
"         % %%%      "
"        %% %%%      "
"       %%% %%%  %%  "
"     %%%  %%% %%%   "
"   %%%   %%%%% %    "
"  %%%   %% %%  %%   "
" %%%%          %%%  "
" %%%%#   % %. %%%%% "
"%%%%% %% % %%%%%%%%%"
"%%%%% %% % %%%%%%%%%"
" %%%% %%%% %%%%%%%%%"
" %%%%%%%%%%%%%%%%%% "
"   %%%        %%%   "
"      %%%%%%%     "
)

# System info
os=$(grep '^PRETTY_NAME=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
host=$(uname -n)
user=$(whoami)
kernel=$(uname -r)
uptime=$(uptime -p | sed 's/uptime //')

# Package count (detecting package manager)
if command -v pacman &> /dev/null; then
    pkgs=$(pacman -Qq | wc -l)
elif command -v dpkg &> /dev/null; then
    pkgs=$(dpkg -l | grep -c '^ii')
elif command -v rpm &> /dev/null; then
    pkgs=$(rpm -qa | wc -l)
else
    pkgs="Unknown"
fi

# Memory info
mem_total=$(free -m | awk '/Mem:/ {print $2}')
mem_used=$(free -m | awk '/Mem:/ {print $3}')
memory="${mem_used}MiB / ${mem_total}MiB"

# Print layout
info=(
    "${BOLD}${PURPLE}${user}${NC}@${BOLD}${PURPLE}${host}${NC}"
    ""
    "-------------------"
    ""
    "${BOLD}${PURPLE}OS:${NC} ${os}"
    ""
    "${BOLD}${PURPLE}Host:${NC} ${host}"
    ""
    "${BOLD}${PURPLE}Kernel:${NC} ${kernel}"
    ""
    "${BOLD}${PURPLE}Uptime:${NC} ${uptime}"
    ""
    "${BOLD}${PURPLE}Packages:${NC} ${pkgs}"
    ""
    "${BOLD}${PURPLE}Memory:${NC} ${memory}"
)

max_lines=${#logo[@]}
if [ ${#info[@]} -gt $max_lines ]; then
    max_lines=${#info[@]}
fi

echo ""
for ((i=0; i<max_lines; i++)); do
    line_logo="${logo[i]}"
    line_info="${info[i]:-}"
    
    # Print logo in bold purple and info next to it
    printf "  ${BOLD}${PURPLE}%-20s${NC}  %b\n" "$line_logo" "$line_info"
done
echo ""
EOF
    chmod +x ~/.config/fyr/fyr_fetch
    mkdir -p "$HOME/.local/bin"
    ln -sf "$HOME/.config/fyr/fyr_fetch" "$HOME/.local/bin/fyrfetch"
    ln -sf "$HOME/.config/fyr/fyr_fetch" "$HOME/.local/bin/fyr_fetch"
    sudo ln -sf "$HOME/.config/fyr/fyr_fetch" /usr/local/bin/fyrfetch
    sudo ln -sf "$HOME/.config/fyr/fyr_fetch" /usr/local/bin/fyr_fetch
    
    if [ -f "$HOME/.zshrc" ]; then
        if ! grep -q "fyr_fetch" "$HOME/.zshrc"; then
            echo "" >> "$HOME/.zshrc"
            echo "# Fyr Fetch" >> "$HOME/.zshrc"
            echo "~/.config/fyr/fyr_fetch" >> "$HOME/.zshrc"
        fi
    fi
}

setup_sway_config() {
    next_step "Configuring Sway..."
    echo "Setting up Sway configuration..."
    mkdir -p ~/.config/fyr
    cp ./backgrounds/space.jpg ~/.config/fyr/space.jpg
    
    # Toggle Floating Script
    cat << 'EOF' > ~/.config/fyr/toggle_floating.sh
#!/bin/bash
CONF="$HOME/.config/sway/floating.conf"
EXCLUDED="fyrtaskbar|fyrdock|fyrdesktop|fyrsearch|launcher|fyroverview|fyrwindowoverview|fyrhelp|fyremoji|fyrclipboard"
if [ -f "$CONF" ] && grep -q "floating enable" "$CONF"; then
    echo "" > "$CONF"
    if swaymsg 'unfor_window [class=".*"] floating enable' >/dev/null 2>&1; then
        swaymsg 'unfor_window [app_id=".*"] floating enable' >/dev/null 2>&1 || true
        swaymsg 'unfor_window [class=".*"] border auto 4' >/dev/null 2>&1 || true
        swaymsg "unfor_window [app_id=\"^(?!($EXCLUDED)$).*$\"] border auto 4" >/dev/null 2>&1 || true
        swaymsg 'default_floating_border auto 4' >/dev/null 2>&1 || true
        swaymsg 'gaps inner 20' >/dev/null 2>&1 || true
        swaymsg 'gaps outer 20' >/dev/null 2>&1 || true
        swaymsg "[workspace=\"^[0-9]+$\" app_id=\"^(?!($EXCLUDED)$).*$\"] floating disable; [tiling] border auto 2; gaps inner all set 20; gaps outer all set 20" >/dev/null 2>&1 || true
    else
        swaymsg "[workspace=\"^[0-9]+$\" app_id=\"^(?!($EXCLUDED)$).*$\"] floating disable; [tiling] border auto 2; gaps inner all set 20; gaps outer all set 20" >/dev/null 2>&1 || true
        swaymsg reload >/dev/null 2>&1 || true
    fi
else
    echo 'for_window [class=".*"] floating enable' > "$CONF"
    echo 'for_window [app_id=".*"] floating enable' >> "$CONF"
    echo 'for_window [class=".*"] border auto 4' >> "$CONF"
    echo "for_window [app_id=\"^(?!($EXCLUDED)$).*$\"] border auto 4" >> "$CONF"
    echo 'default_floating_border auto 4' >> "$CONF"
    echo 'gaps inner 0' >> "$CONF"
    echo 'gaps outer 0' >> "$CONF"
    swaymsg 'for_window [class=".*"] floating enable' >/dev/null 2>&1 || true
    swaymsg 'for_window [app_id=".*"] floating enable' >/dev/null 2>&1 || true
    swaymsg 'for_window [class=".*"] border auto 4' >/dev/null 2>&1 || true
    swaymsg "for_window [app_id=\"^(?!($EXCLUDED)$).*$\"] border auto 4" >/dev/null 2>&1 || true
    swaymsg 'default_floating_border auto 4' >/dev/null 2>&1 || true
    swaymsg 'gaps inner 0' >/dev/null 2>&1 || true
    swaymsg 'gaps outer 0' >/dev/null 2>&1 || true
    swaymsg "[tiling] floating enable; [floating workspace=\"^[0-9]+$\" class=\".*\"] border auto 4; [floating workspace=\"^[0-9]+$\" app_id=\"^(?!($EXCLUDED)$).*$\"] border auto 4; gaps inner all set 0; gaps outer all set 0" >/dev/null 2>&1 || true
fi
exit 0
EOF
    chmod +x ~/.config/fyr/toggle_floating.sh

    # Close Window Script (Super + Q)
    cat << 'EOF' > ~/.config/fyr/close_window.sh
#!/bin/bash
# Super + Q - close the focused window.
#
# Sends the regular Wayland/X11 close request ("kill") so applications can
# save state or ask for confirmation before exiting. Two guard rails keep the
# shortcut from breaking the session:
#   * shell panels (taskbar, dock, overviews) are never closed;
#   * scratchpad overlays (fyrHelp, fyrEmoji) are hidden instead of killed,
#     because they are launched once per session and toggled from there.

set -u

HIDE_APPS='^(fyrhelp|fyremoji|fyrclipboard)$'
PANEL_APPS='^(fyrtaskbar|fyrdock|fyrdesktop|fyrsearch|launcher|fyroverview|fyrwindowoverview)$'

command -v swaymsg >/dev/null 2>&1 || exit 0

# Without jq we cannot tell panels and overlays apart; fall back to sway's own
# focused-window handling.
if ! command -v jq >/dev/null 2>&1; then
    swaymsg kill >/dev/null 2>&1 || true
    exit 0
fi

# Pick the focused window: a leaf view with a client process, which skips
# sway's internal containers, empty workspaces and layer surfaces.
node=$(swaymsg -t get_tree 2>/dev/null | jq -c '
    [ .. | objects
      | select(.focused == true)
      | select(.type == "con" or .type == "floating_con")
      | select((.pid // -1) > 0)
      | select(((.app_id // "") | length) > 0 or ((.window_properties? // {}) | length) > 0)
    ] | first // empty')

[ -n "$node" ] || exit 0

app_id=$(jq -r '.app_id // ""' <<<"$node")
con_id=$(jq -r '.id // ""' <<<"$node")
[ -n "$con_id" ] || exit 0

# Note: these patterns are EREs ([[ =~ ]]), not case globs.
if [[ "$app_id" =~ $PANEL_APPS ]]; then
    # Shell surface: there is no application window to close.
    exit 0
fi

if [[ "$app_id" =~ $HIDE_APPS ]]; then
    swaymsg "[con_id=$con_id]" move scratchpad >/dev/null 2>&1 || true
    exit 0
fi

swaymsg "[con_id=$con_id]" kill >/dev/null 2>&1 || swaymsg kill >/dev/null 2>&1
exit 0
EOF
    chmod +x ~/.config/fyr/close_window.sh

    setup_fetch


    # Retile Script
    cat << 'EOF' > ~/.config/fyr/retile.py
#!/usr/bin/env python3
import subprocess, json
def run(cmd): return subprocess.check_output(cmd, shell=True).decode('utf-8')
def main():
    tree_out = run('swaymsg -t get_tree')
    if not tree_out: return
    tree = json.loads(tree_out)
    ws_out = run('swaymsg -t get_workspaces')
    if not ws_out: return
    workspaces = json.loads(ws_out)
    focused_ws = next((w for w in workspaces if w.get('focused')), None)
    if not focused_ws: return
    def get_windows(node):
        wins = []
        app_id = node.get('app_id'); class_name = node.get('window_properties', {}).get('class'); name = node.get('name')
        excluded = ['fyrtaskbar', 'fyrdock', 'fyroverview', 'fyrsearch', 'fyrhelp', 'fyremoji', 'fyrclipboard']
        if not (app_id in excluded or class_name in excluded or name in excluded) and node.get('type') in ['con', 'floating_con'] and (app_id or class_name or name):
            if not node.get('nodes'): wins.append(node)
        for child in node.get('nodes', []) + node.get('floating_nodes', []): wins.extend(get_windows(child))
        return wins
    def find_ws(node):
        if node.get('type') == 'workspace' and node.get('name') == focused_ws['name']: return node
        for c in node.get('nodes', []):
            res = find_ws(c)
            if res: return res
        return None
    ws_node = find_ws(tree)
    if not ws_node: return
    windows = get_windows(ws_node)
    if not windows: return
    windows.sort(key=lambda w: (w['rect']['x'], w['rect']['y']))
    for w in windows: run(f'swaymsg "[con_id={w["id"]}] move workspace {focused_ws["name"]}"')
    for w in windows: run(f'swaymsg "[con_id={w["id"]}] floating disable"')
    run(f'swaymsg "workspace {focused_ws["name"]}; layout splith"')
    if len(windows) % 2 == 0 and len(windows) > 0:
        half = len(windows) // 2
        for i in range(half):
            w_top, w_bot = windows[i], windows[i+half]
            run(f'swaymsg "[con_id={w_top["id"]}] focus; splitv; move down"')
            run(f'swaymsg "[con_id={w_top["id"]}] mark target; [con_id={w_bot["id"]}] move window to mark target; unmark target"')
if __name__ == "__main__": main()
EOF
    chmod +x ~/.config/fyr/retile.py

    # Alt-Tab Script (supports --prev for Alt+Shift+Tab)
    cat << 'EOF' > ~/.config/fyr/alttab.py
#!/usr/bin/env python3
import subprocess, json, sys
def run(cmd): return subprocess.check_output(cmd, shell=True).decode('utf-8')
def get_windows(node, windows):
    if node.get('type') in ['con', 'floating_con'] and (node.get('app_id') or node.get('window_properties')) and not node.get('nodes'):
        windows.append(node); return
    for child in node.get('nodes', []) + node.get('floating_nodes', []): get_windows(child, windows)
def main():
    reverse = any(arg in ('--prev', '-p', 'prev') for arg in sys.argv[1:])
    tree, workspaces = json.loads(run('swaymsg -t get_tree')), json.loads(run('swaymsg -t get_workspaces'))
    focused_ws = next((ws['name'] for ws in workspaces if ws['focused']), None)
    if not focused_ws: return
    def find_ws(node, name):
        if node.get('type') == 'workspace' and node.get('name') == name: return node
        for c in node.get('nodes', []) + node.get('floating_nodes', []):
            res = find_ws(c, name)
            if res: return res
        return None
    ws_node = find_ws(tree, focused_ws)
    if not ws_node: return
    windows = []; get_windows(ws_node, windows)
    if len(windows) < 2: return
    def find_focused(node):
        if node.get('focused'): return node.get('id')
        for c in node.get('nodes', []) + node.get('floating_nodes', []):
            res = find_focused(c);
            if res: return res
        return None
    fid = find_focused(tree)
    fidx = next((i for i, w in enumerate(windows) if w.get('id') == fid), -1)
    if fidx == -1:
        target_idx = len(windows) - 1 if reverse else 0
    else:
        target_idx = (fidx - 1 if reverse else fidx + 1) % len(windows)
    nid = windows[target_idx]['id']
    subprocess.run(['swaymsg', f'[con_id={nid}] focus'])
if __name__ == "__main__": main()
EOF
    chmod +x ~/.config/fyr/alttab.py

    # Interactive Screenshot Script (full / region / window)
    cat << 'EOF' > ~/.config/fyr/screenshot.sh
#!/bin/bash
set -euo pipefail

MODE="${1:-full}"
OUT_DIR="$HOME/Pictures/screenshots"
mkdir -p "$OUT_DIR"
OUT_FILE="$OUT_DIR/$(date +'%Y-%m-%d_%H-%M-%S').png"

case "$MODE" in
    region)
        GEOM=$(slurp 2>/dev/null || true)
        [ -n "$GEOM" ] || exit 0
        grim -g "$GEOM" "$OUT_FILE"
        LABEL="Region screenshot"
        ;;
    window)
        GEOM=$(swaymsg -t get_tree 2>/dev/null | jq -r '
            [ .. | objects
              | select(.focused == true)
              | select(.type == "con" or .type == "floating_con")
              | .rect
            ] | first // empty
            | "\(.x),\(.y) \(.width)x\(.height)"' || true)
        if [ -n "$GEOM" ] && [ "$GEOM" != "null,null nullxnull" ]; then
            grim -g "$GEOM" "$OUT_FILE"
            LABEL="Window screenshot"
        else
            grim "$OUT_FILE"
            LABEL="Full screenshot"
        fi
        ;;
    full|*)
        grim "$OUT_FILE"
        LABEL="Full screenshot"
        ;;
esac

if command -v wl-copy &> /dev/null; then
    wl-copy -t image/png < "$OUT_FILE"
fi
if command -v canberra-gtk-play &> /dev/null; then
    canberra-gtk-play -i screen-capture >/dev/null 2>&1 &
fi
OSD_SOCK="$HOME/.config/fyr/osd.sock"
SENT_TOAST=0
if [ -S "$OSD_SOCK" ] && command -v python3 &> /dev/null; then
    if python3 -c "import socket,sys; s=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM); s.settimeout(0.3); s.connect(sys.argv[1]); s.sendall((sys.argv[2]+'\n').encode()); s.close()" "$OSD_SOCK" "screenshot ${LABEL}|${OUT_FILE}" 2>/dev/null; then
        SENT_TOAST=1
    fi
fi
if [ "$SENT_TOAST" -eq 0 ] && command -v notify-send &> /dev/null; then
    notify-send -i "$OUT_FILE" "$LABEL saved" "Copied to clipboard & saved to ~/Pictures/screenshots/$(basename "$OUT_FILE")" || true
fi
EOF
    chmod +x ~/.config/fyr/screenshot.sh

    # Screen Lock Script (swaylock with Fyr theme, falling back to SDDM greeter)
    cat << 'EOF' > ~/.config/fyr/lock.sh
#!/bin/bash
set -euo pipefail

if command -v swaylock &> /dev/null; then
    if pgrep -x swaylock >/dev/null 2>&1; then
        exit 0
    fi
    BG_ARGS=(--color 0b0a10)
    if [ -s "$HOME/.config/fyr/lockscreen.jpg" ]; then
        BG_ARGS=(--image "$HOME/.config/fyr/lockscreen.jpg" --scaling fill)
    elif [ -s "$HOME/.config/fyr/space.jpg" ]; then
        BG_ARGS=(--image "$HOME/.config/fyr/space.jpg" --scaling fill)
    fi
    exec swaylock -f "${BG_ARGS[@]}" \
        --inside-color 14121acc \
        --ring-color 9c27b0ff \
        --ring-ver-color ba68c8ff \
        --ring-wrong-color e53935ff \
        --key-hl-color e040fbff \
        --bs-hl-color ff5252ff \
        --text-color ffffffff \
        --line-color 00000000 \
        --separator-color 00000000 \
        --indicator-radius 95 \
        --indicator-thickness 7
elif command -v dbus-send &> /dev/null; then
    dbus-send --system --type=method_call \
        --dest=org.freedesktop.DisplayManager \
        /org/freedesktop/DisplayManager/Seat0 \
        org.freedesktop.DisplayManager.Seat.SwitchToGreeter
fi
EOF
    chmod +x ~/.config/fyr/lock.sh

    # Recording Script
    cat << 'EOF' > ~/.config/fyr/toggle_recording.sh
#!/bin/bash
pid=$(pgrep wf-recorder)
if [ -n "$pid" ]; then kill -SIGINT $pid; notify-send "Screen Recording" "Saved to ~/Videos/screencasts/"; else
mkdir -p ~/Videos/screencasts; wf-recorder -f ~/Videos/screencasts/$(date +'%Y-%m-%d_%H-%M-%S').mp4 & notify-send "Screen Recording" "Started"; fi
EOF
    chmod +x ~/.config/fyr/toggle_recording.sh

    # Overview Toggle Script
    cat << 'EOF' > ~/.config/fyr/overview_toggle.sh
#!/bin/bash
CONF="$HOME/.config/sway/floating.conf"
IS_FLOATING=0
if [ -f "$CONF" ] && grep -q "floating enable" "$CONF"; then
    IS_FLOATING=1
fi

send_cmd() {
    local sock="$HOME/.config/fyr/overlay-$1.sock"
    local msg="$2"
    [ -S "$sock" ] || return 1
    python3 -c "import socket,sys; s=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM); s.settimeout(0.3); s.connect(sys.argv[1]); s.sendall((sys.argv[2]+'\n').encode()); s.close()" "$sock" "$msg" 2>/dev/null
}

ARG="${1:-}"
if [ "$ARG" = "hide" ]; then
    send_cmd "fyrwindowoverview" "hide" || true
    send_cmd "fyroverview" "hide" || true
    exit 0
fi

COORDS=$(swaymsg -t get_outputs 2>/dev/null | jq -r '.[] | select(.focused) | "\(.rect.x),\(.rect.y)"' | head -n 1)

if [ "$IS_FLOATING" -eq 1 ]; then
    if [ "$ARG" = "workspace" ]; then
        TARGET="fyroverview"
        OTHER="fyrwindowoverview"
    else
        TARGET="fyrwindowoverview"
        OTHER="fyroverview"
    fi
else
    TARGET="fyroverview"
    OTHER="fyrwindowoverview"
fi

send_cmd "$OTHER" "hide" || true
if ! send_cmd "$TARGET" "toggle ${COORDS}"; then
    "/opt/$TARGET/$TARGET" --show >/dev/null 2>&1 &
fi
EOF
    chmod +x ~/.config/fyr/overview_toggle.sh

    # Launcher Toggle Script
    cat << 'EOF' > ~/.config/fyr/launcher_toggle.sh
#!/bin/bash
SOCK="$HOME/.config/fyr/overlay-fyrsearch.sock"
COORDS=$(swaymsg -t get_outputs 2>/dev/null | jq -r '.[] | select(.focused) | "\(.rect.x),\(.rect.y)"' | head -n 1)

if [ -S "$SOCK" ]; then
    python3 -c "import socket,sys; s=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM); s.settimeout(0.3); s.connect(sys.argv[1]); s.sendall((sys.argv[2]+'\n').encode()); s.close()" "$SOCK" "toggle ${COORDS}" && exit 0
fi

/opt/fyrsearch/fyrsearch --show >/dev/null 2>&1 &
EOF
    chmod +x ~/.config/fyr/launcher_toggle.sh

    # Emoji Picker Toggle Script
    cat << 'EOF' > ~/.config/fyr/emoji_toggle.sh
#!/bin/bash
SOCK="$HOME/.config/fyr/overlay-fyremoji.sock"
COORDS=$(swaymsg -t get_outputs 2>/dev/null | jq -r '.[] | select(.focused) | "\(.rect.x),\(.rect.y)"' | head -n 1)

if [ -S "$SOCK" ]; then
    python3 -c "import socket,sys; s=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM); s.settimeout(0.3); s.connect(sys.argv[1]); s.sendall((sys.argv[2]+'\n').encode()); s.close()" "$SOCK" "toggle ${COORDS}" && exit 0
fi

/opt/fyremoji/fyremoji --show >/dev/null 2>&1 &
EOF
    chmod +x ~/.config/fyr/emoji_toggle.sh

    # Clipboard History Toggle Script
    cat << 'EOF' > ~/.config/fyr/clipboard_toggle.sh
#!/bin/bash
SOCK="$HOME/.config/fyr/overlay-fyrclipboard.sock"
COORDS=$(swaymsg -t get_outputs 2>/dev/null | jq -r '.[] | select(.focused) | "\(.rect.x),\(.rect.y)"' | head -n 1)

if [ -S "$SOCK" ]; then
    python3 -c "import socket,sys; s=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM); s.settimeout(0.3); s.connect(sys.argv[1]); s.sendall((sys.argv[2]+'\n').encode()); s.close()" "$SOCK" "toggle ${COORDS}" && exit 0
fi

/opt/fyrclipboard/fyrclipboard --show >/dev/null 2>&1 &
EOF
    chmod +x ~/.config/fyr/clipboard_toggle.sh

    # Task Manager (fyrMonitor) Toggle Script
    cat << 'EOF' > ~/.config/fyr/monitor_toggle.sh
#!/bin/bash
# Ctrl+Shift+Esc: focus the existing fyrMonitor window, otherwise launch it.
#
# flock keeps a double keypress (or a double binding) from spawning two windows.
mkdir -p "$HOME/.config/fyr"
exec 9>"$HOME/.config/fyr/.monitor_toggle.lock"
flock -n 9 2>/dev/null || exit 0

MONITOR_BIN=""
for candidate in "/usr/local/bin/fyrmonitor" "/opt/fyrmonitor/fyrmonitor" "$(command -v fyrmonitor 2>/dev/null)"; do
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then
        MONITOR_BIN="$candidate"
        break
    fi
done

CON_ID=""
if command -v swaymsg &> /dev/null && command -v jq &> /dev/null; then
    CON_ID=$(swaymsg -t get_tree 2>/dev/null | jq -r '
        .. | objects
        | select((.app_id? // "") | test("fyrmonitor"))
        | .id' | head -n 1)
fi

if [ -n "$CON_ID" ]; then
    swaymsg "[con_id=$CON_ID] focus" >/dev/null 2>&1
    exit 0
fi

if [ -z "$MONITOR_BIN" ]; then
    notify-send "fyrMonitor" "Not installed. Run ./install.sh -a fyrmonitor" 2>/dev/null || true
    exit 1
fi

"$MONITOR_BIN" >/dev/null 2>&1 &
EOF
    chmod +x ~/.config/fyr/monitor_toggle.sh

    # Help Toggle Script
    cat << 'EOF' > ~/.config/fyr/help_toggle.sh
#!/bin/bash
FOCUSED_OUTPUT=$(swaymsg -t get_outputs | jq -r '.[] | select(.focused) | .name')
X=$(swaymsg -t get_outputs | jq -r ".[] | select(.name == \"$FOCUSED_OUTPUT\") | .rect.x")
Y=$(swaymsg -t get_outputs | jq -r ".[] | select(.name == \"$FOCUSED_OUTPUT\") | .rect.y")
W=$(swaymsg -t get_outputs | jq -r ".[] | select(.name == \"$FOCUSED_OUTPUT\") | .rect.width")
H=$(swaymsg -t get_outputs | jq -r ".[] | select(.name == \"$FOCUSED_OUTPUT\") | .rect.height")

VISIBLE=$(swaymsg -t get_tree | jq -r '.. | select(.app_id? == "fyrhelp") | .visible')

if [ "$VISIBLE" = "true" ]; then
    swaymsg '[app_id="fyrhelp"] move scratchpad'
else
    swaymsg "[app_id=\"fyrhelp\"] scratchpad show, border none, resize set $W $H, move absolute position $X $Y"
fi
EOF
    chmod +x ~/.config/fyr/help_toggle.sh

    # OSD Popup Helper Script (Volume, Mic, Brightness)
    cat << 'EOF' > ~/.config/fyr/osd.sh
#!/bin/bash
set -e

SOCK="${HOME}/.config/fyr/osd.sock"

send_osd() {
    local msg="$1"
    [ -S "$SOCK" ] || return 0
    python3 -c "import socket,sys; s=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM); s.settimeout(0.2); s.connect(sys.argv[1]); s.sendall((sys.argv[2]+'\n').encode()); s.close()" "$SOCK" "$msg" 2>/dev/null || true
}

report_volume() {
    local out pct
    out=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null || true)
    pct=$(awk '{printf "%d", $2 * 100 + 0.5}' <<<"$out")
    if grep -q '\[MUTED\]' <<<"$out"; then
        send_osd "volume ${pct:-0} muted"
    else
        send_osd "volume ${pct:-0}"
    fi
}

report_mic() {
    local out
    out=$(wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null || true)
    if grep -q '\[MUTED\]' <<<"$out"; then
        send_osd "mic muted"
    else
        send_osd "mic unmuted"
    fi
}

report_brightness() {
    local pct
    pct=$(brightnessctl -m 2>/dev/null | awk -F, '{gsub(/%/, "", $4); print $4}')
    [ -n "$pct" ] && send_osd "brightness $pct"
}

case "${1:-}" in
    vol-up)
        wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+
        report_volume
        ;;
    vol-down)
        wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
        report_volume
        ;;
    vol-mute)
        wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
        report_volume
        ;;
    mic-mute)
        wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle
        report_mic
        ;;
    bright-up)
        brightnessctl set +5% >/dev/null
        report_brightness
        ;;
    bright-down)
        brightnessctl set 5%- >/dev/null
        report_brightness
        ;;
esac
EOF
    chmod +x ~/.config/fyr/osd.sh

    mkdir -p ~/.config/sway/conf.d
    if [ -d "./sway" ] && [ -f "./sway/config" ]; then
        cp ./sway/config ~/.config/sway/config
        echo "Sway main config updated (user overrides in ~/.config/sway/conf.d/ preserved)."
    fi
    if [ ! -f ~/.config/sway/conf.d/22-displays.conf ]; then
        cat << EOF > ~/.config/sway/conf.d/22-displays.conf
# DISPLAY OUTPUT SETTINGS
output eDP-1 resolution ${WIDTH}x${HEIGHT} position 0 0
# END DISPLAY OUTPUT SETTINGS
EOF
    fi
    if [ ! -f ~/.config/sway/conf.d/30-touchpad.conf ]; then
        cat << 'EOF' > ~/.config/sway/conf.d/30-touchpad.conf
# TOUCHPAD SETTINGS
input "type:touchpad" {
    tap enabled
    tap_button_map lrm
    drag enabled
    dwt enabled
    natural_scroll disabled
}
# END TOUCHPAD SETTINGS
EOF
    fi
    if [ ! -f ~/.config/sway/conf.d/40-power.conf ]; then
        cat << 'EOF' > ~/.config/sway/conf.d/40-power.conf
# POWER & SCREEN LOCK SETTINGS
bindswitch --reload --locked lid:on exec ~/.config/fyr/lock.sh
exec swayidle -w before-sleep '~/.config/fyr/lock.sh'
# END POWER & SCREEN LOCK SETTINGS
EOF
    fi

    # Configure WirePlumber auto-profile for automatic HDMI and audio detection
    mkdir -p ~/.config/wireplumber/wireplumber.conf.d
    cat << 'EOF' > ~/.config/wireplumber/wireplumber.conf.d/50-alsa-auto-profile.conf
monitor.alsa.rules = [
  {
    matches = [
      {
        device.name = "~alsa_card.*"
      }
    ]
    actions = {
      update-props = {
        api.acp.auto-profile = true
        api.acp.auto-port = true
      }
    }
  }
]
EOF

    if command -v swaymsg &> /dev/null && swaymsg -t get_version &> /dev/null; then
        swaymsg reload || true
    fi
}

setup_themes() {
    next_step "Installing themes..."
    echo "Installing Themes..."
    if [ ! -d "$HOME/.local/share/icons/Tela-purple-dark" ]; then
        git clone https://github.com/vinceliuice/Tela-icon-theme.git /tmp/Tela-icon-theme
        /tmp/Tela-icon-theme/install.sh -a && rm -rf /tmp/Tela-icon-theme
    fi

    if [ -d "./themes" ]; then
        mkdir -p ~/.themes/Fyr-Dark/gtk-3.0
        cp -r ./themes/gtk-3.0/* ~/.themes/Fyr-Dark/gtk-3.0/
        mkdir -p ~/.config/gtk-4.0
        cp ./themes/gtk-4.0/gtk-dark.css ~/.config/gtk-4.0/gtk.css
        mkdir -p ~/.config/gtk-3.0
        
        cat <<EOF > ~/.config/gtk-3.0/settings.ini
[Settings]
gtk-theme-name=Fyr-Dark
gtk-icon-theme-name=Tela-purple-dark
gtk-application-prefer-dark-theme=1
EOF
        gsettings set org.gnome.desktop.interface gtk-theme "Fyr-Dark" || true
        gsettings set org.gnome.desktop.interface icon-theme "Tela-purple-dark" || true
        gsettings set org.gnome.desktop.interface color-scheme "prefer-dark" || true
    fi
}

setup_sddm() {
    next_step "Configuring SDDM..."
    echo "Setting up SDDM theme..."
    if [ -d "./sddm" ]; then
        sudo mkdir -p /usr/share/sddm/themes/fyr
        sudo cp -r ./sddm/theme/* /usr/share/sddm/themes/fyr/
        sudo mkdir -p /etc/sddm.conf.d
        sudo cp ./sddm/sddm.conf /etc/sddm.conf.d/fyr.conf
        sudo mkdir -p /etc/X11/xorg.conf.d
        sudo tee /etc/X11/xorg.conf.d/30-touchpad.conf > /dev/null <<'XORG_TOUCHPAD_EOF'
Section "InputClass"
    Identifier "touchpad"
    Driver "libinput"
    MatchIsTouchpad "on"
    Option "Tapping" "on"
    Option "TappingDrag" "on"
    Option "TappingButtonMap" "lrm"
    Option "DisableWhileTyping" "on"
EndSection
XORG_TOUCHPAD_EOF
        sudo systemctl enable sddm || true
        
        echo "Setting up ACLs for SDDM user..."
        sudo setfacl -m u:sddm:x "$HOME"
        mkdir -p "$HOME/.config/fyr"
        touch "$HOME/.face.icon"
        touch "$HOME/.config/fyr/lockscreen.jpg"
        sudo setfacl -m u:sddm:r "$HOME/.face.icon"
        sudo setfacl -m u:sddm:r "$HOME/.config/fyr/lockscreen.jpg"
    fi
}

# --- Main Logic ---

MODULAR=false
CLEAN_BUILD=false
INSTALL_DEPS=false
INSTALL_SWAY_CONFIG=false
INSTALL_SDDM=false
INSTALL_THEMES=false
INSTALL_ZSH=false
INSTALL_FETCH=false
INSTALL_FYRPAK=false
HIDE_REDUNDANT=false
INSTALL_GRAPHICS=false

setup_zsh() {
    next_step "Configuring ZSH..."
    echo "Setting up ZSH and Oh-My-Zsh..."
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        RUNZSH=no CHSH=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    else
        echo "Oh-My-Zsh already installed."
    fi
    
    if [ "$SHELL" != "$(which zsh)" ]; then
        echo "Changing default shell to zsh..."
        sudo chsh -s $(which zsh) $USER
    fi
    
    # Ensure flutter is in the zsh path
    if ! grep -q "/opt/flutter/bin" "$HOME/.zshrc" 2>/dev/null; then
        echo "export PATH=\"\$PATH:/opt/flutter/bin\"" >> "$HOME/.zshrc"
    fi
}

APP_TO_REINSTALL=""

while getopts "a:wcsltdhfFzHgp" opt; do
    case $opt in
        a) APP_TO_REINSTALL="$OPTARG"
           if [ ! -d "./$APP_TO_REINSTALL" ]; then
               LOWER_APP="$(echo "$APP_TO_REINSTALL" | tr '[:upper:]' '[:lower:]')"
               if [ -d "./$LOWER_APP" ]; then
                   APP_TO_REINSTALL="$LOWER_APP"
               fi
           fi
           MODULAR=true ;;
        c) CLEAN_BUILD=true ;;
        w) INSTALL_SWAYFX=true; MODULAR=true ;;
        s) INSTALL_SWAY_CONFIG=true; MODULAR=true ;;
        l) INSTALL_SDDM=true; MODULAR=true ;;
        t) INSTALL_THEMES=true; MODULAR=true ;;
        d) INSTALL_DEPS=true; MODULAR=true ;;
        z) INSTALL_ZSH=true; MODULAR=true ;;
        f) INSTALL_FETCH=true; MODULAR=true ;;
        p) INSTALL_FYRPAK=true; MODULAR=true ;;
        g) INSTALL_GRAPHICS=true; MODULAR=true ;;
        H) HIDE_REDUNDANT=true; MODULAR=true ;;
        F) MODULAR=false ;;
        h) usage; exit 0 ;;
        *) usage; exit 1 ;;
    esac
done

if [ "$MODULAR" = "false" ]; then
    echo "Starting full installation..."
    TOTAL_STEPS=$(( 11 + ${#flutter_apps[@]} ))
    install_deps
    install_fyrpak
    setup_zsh
    install_flutter
    build_swayfx
    for app in "${flutter_apps[@]}"; do
        reinstall_app "$app"
    done
    setup_sway_config
    setup_themes
    setup_sddm
    hide_redundant_apps
else
    echo "Starting modular installation..."
    # Calculate steps
    TOTAL_STEPS=0
    [ "$INSTALL_DEPS" = "true" ] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
    [ "$INSTALL_FYRPAK" = "true" ] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
    [ "$INSTALL_ZSH" = "true" ] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
    [ -n "$APP_TO_REINSTALL" ] && TOTAL_STEPS=$((TOTAL_STEPS + 2)) # flutter + app
    [ "$INSTALL_GRAPHICS" = "true" ] && [ "$APP_TO_REINSTALL" != "fyrgraphics" ] && TOTAL_STEPS=$((TOTAL_STEPS + 2))
    [ "$INSTALL_SWAYFX" = "true" ] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
    [ "$INSTALL_SWAY_CONFIG" = "true" ] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
    [ "$INSTALL_SDDM" = "true" ] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
    [ "$INSTALL_THEMES" = "true" ] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
    [ "$INSTALL_FETCH" = "true" ] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
    [ "$HIDE_REDUNDANT" = "true" ] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
    
    if [ "$TOTAL_STEPS" -eq 0 ]; then TOTAL_STEPS=1; fi

    if [ "$INSTALL_DEPS" = "true" ]; then install_deps; fi
    if [ "$INSTALL_FYRPAK" = "true" ]; then install_fyrpak; fi
    if [ "$INSTALL_ZSH" = "true" ]; then setup_zsh; fi
    if [ -n "$APP_TO_REINSTALL" ]; then
        install_flutter
        reinstall_app "$APP_TO_REINSTALL"
    fi
    if [ "$INSTALL_GRAPHICS" = "true" ] && [ "$APP_TO_REINSTALL" != "fyrgraphics" ]; then
        if [ -z "$APP_TO_REINSTALL" ]; then install_flutter; fi
        reinstall_app "fyrgraphics"
    fi
    if [ "$INSTALL_SWAYFX" = "true" ]; then build_swayfx; fi
    if [ "$INSTALL_SWAY_CONFIG" = "true" ]; then setup_sway_config; fi
    if [ "$INSTALL_SDDM" = "true" ]; then setup_sddm; fi
    if [ "$INSTALL_THEMES" = "true" ]; then setup_themes; fi
    if [ "$INSTALL_FETCH" = "true" ]; then setup_fetch; fi
    if [ "$HIDE_REDUNDANT" = "true" ]; then hide_redundant_apps; fi
fi

printf "\n"
echo "Operation complete!"

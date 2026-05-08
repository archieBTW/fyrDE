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

flutter_apps=("fyrdock" "fyroverview" "fyrwindowoverview" "fyrsearch" "fyrsettings" "fyrtaskbar" "fyrterm" "fyrfiles" "fyrhelp" "fyremoji" "fyrstore" "fyrvirt" "fyrtext" "fyrdaw" "fyrav" "fyrphone" "fyrcode" "fyrvideo" "fyrmusic" "fyrphotos" "fyrcamera" "fyrbrowser" "fyrjournal")

# --- Functions ---

usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -a <app>    Rebuild and reinstall a specific Flutter app (e.g., fyrtaskbar)"
    echo "  -s          Reinstall Sway configuration and scripts"
    echo "  -l          Reinstall SDDM theme and configuration"
    echo "  -t          Reinstall GTK and icon themes"
    echo "  -d          Install system dependencies only"
    echo "  -z          Setup ZSH and Oh-My-Zsh"
    echo "  -f          Force full installation (default if no flags provided)"
    echo "  -h          Show this help message"
}

install_deps() {
    if [ "$OS" = "arch" ] || [ "$OS" = "manjaro" ] || [ "$OS" = "endeavouros" ]; then
        echo "Configuring pacman..."
        sudo sed -i '/^#\[multilib\]/{ s/^#//; n; s/^#//; }' /etc/pacman.conf
        sudo sed -i 's/^#Color/Color/' /etc/pacman.conf
        if ! grep -q "^ILoveCandy" /etc/pacman.conf; then
            sudo sed -i '/^Color/a ILoveCandy' /etc/pacman.conf
        fi
        
        echo "Updating system..."
        sudo pacman -Syu --noconfirm

        echo "Installing base-devel and git for building packages..."
        sudo pacman -S --needed --noconfirm base-devel git

        if ! command -v yay &> /dev/null; then
            echo "yay could not be found. Installing yay..."
            git clone https://aur.archlinux.org/yay.git /tmp/yay
            cd /tmp/yay
            makepkg -si --noconfirm
            cd -
            rm -rf /tmp/yay
        fi

        deps=( 
            "jq" "mesa-utils" "swaybg" "swaylock" "swayidle" "xorg-xwayland" "foot" "wmenu"
            "gtk-layer-shell" "xdg-desktop-portal" "xdg-desktop-portal-gtk"
            "xdg-desktop-portal-wlr" "xclip" "wl-clipboard" "brightnessctl"
            "wireplumber" "pipewire" "pipewire-pulse" "wlsunset" "cmake" "cpio" "pkg-config" "gcc" "wf-recorder" "grim" "ninja" "clang" "alsa-utils"
            "meson" "scdoc" "wayland-protocols" "pcre2" "json-c" "pango" "cairo" "gdk-pixbuf2" "unzip" "virt-viewer" "libvirt" "virt-install" "qemu-desktop"
            "bluez" "bluez-utils" "xdg-utils" "slurp" "libnotify" "polkit-gnome" "network-manager-applet" "pavucontrol" "playerctl" "jq" "libcanberra" "psmisc" "pamixer" "sddm" "accountsservice" "qt5-declarative" "qt5-quickcontrols" "qt5-quickcontrols2" "qt5-graphicaleffects" "kdeconnect"
            "ufw" "clamav" "rkhunter" "inotify-tools" "acl" "firefox" "mpv" "ffmpeg" "noto-fonts-emoji" "zsh" "xorg-server-xvfb" "p7zip" "zip" "tar" "gzip" "bzip2" "nodejs" "npm" "clang" "virglrenderer" "libpulse"
            "gstreamer" "gst-plugins-base" "gst-plugins-good" "gst-plugins-bad" "gst-plugins-ugly" "gst-libav" "gst-plugin-pipewire" "libcamera" "gst-plugin-libcamera"
        )
        sudo pacman -S --needed --noconfirm "${deps[@]}"
        yay -S --needed --noconfirm scenefx0.4 wlroots0.19 xdg-desktop-portal-termfilechooser-hunkyburrito-git

    elif [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
        echo "Updating system..."
        sudo apt-get update && sudo apt-get upgrade -y
        deps=(
            "swaybg" "swaylock" "swayidle" "xwayland" "foot" "libgtk-layer-shell-dev"
            "xdg-desktop-portal" "xdg-desktop-portal-gtk" "xdg-desktop-portal-wlr"
            "xclip" "wl-clipboard" "brightnessctl" "wireplumber" "pipewire" "pipewire-pulse" "cmake" "cpio" "libasound2-dev" "alsa-utils"
            "pkg-config" "gcc" "wf-recorder" "grim" "ninja-build" "clang" "curl" "git" "unzip" "xz-utils" "zip" "libglu1-mesa" "sway" "virt-viewer" "libvirt-clients" "libvirt-daemon-system" "virtinst" "qemu-kvm" "qemu-system"
            "bluez" "bluez-tools" "xdg-utils" "slurp" "libnotify-bin" "polkit-gnome" "network-manager-gnome" "pavucontrol" "playerctl" "jq" "libcanberra-gtk3-module" "libcanberra-gtk-module" "psmisc" "pamixer" "sddm" "accountsservice" "policykit-1-gnome" "qml-module-qtquick-controls" "qml-module-qtquick-controls2" "qml-module-qtgraphicaleffects" "kdeconnect"
            "ufw" "clamav" "rkhunter" "inotify-tools" "acl" "firefox" "libmpv-dev" "ffmpeg" "fonts-noto-color-emoji" "zsh" "xvfb" "p7zip-full" "tar" "gzip" "bzip2" "nodejs" "npm" "clangd" "libvirglrenderer-dev" "libpulse-dev"
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
            "ufw" "clamav" "rkhunter" "inotify-tools" "acl" "firefox" "mpv-libs-devel" "ffmpeg" "google-noto-emoji-color-fonts" "zsh" "xorg-x11-server-Xvfb" "p7zip" "tar" "gzip" "bzip2" "nodejs" "npm" "clang" "virglrenderer-devel"
            "gstreamer1-devel" "gstreamer1-plugins-base-devel" "gstreamer1-plugins-good" "gstreamer1-plugins-bad-free" "gstreamer1-libav"
        )
        sudo dnf install -y "${deps[@]}"
        sudo dnf install -y wlsunset wmenu swayfx || echo "Optional packages missed."
    fi
}

install_flutter() {
    echo "Ensuring Flutter 3.41.9 is installed in /opt/flutter..."
    
    # Check if flutter is already installed and version matches
    if [ -d "/opt/flutter/bin" ] && [ -f "/opt/flutter/version" ] && [ "$(cat /opt/flutter/version)" = "3.41.9" ]; then
        echo "Flutter 3.41.9 is already installed. Skipping download."
    else
        echo "Installing/Updating Flutter to 3.41.9..."
        sudo rm -rf /opt/flutter
        sudo git clone --depth 1 --branch 3.41.9 https://github.com/flutter/flutter.git /opt/flutter
        sudo chown -R $USER:$USER /opt/flutter
    fi
    
    export PATH="$PATH:/opt/flutter/bin"
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
    echo "Building and installing local swayfx..."
    if [ -d "./swayfx" ]; then
        cd ./swayfx
        rm -rf build
        meson setup build
        ninja -C build
        sudo ninja -C build install
        cd ..
    fi
}



reinstall_app() {
    local app=$1
    if [ -d "./$app" ]; then
        echo "Building $app..."
        cd "./$app"
        flutter clean || true
        flutter create --platforms=linux .
        flutter pub get
        xvfb-run -a flutter build linux
        
        echo "Installing $app to /opt/$app..."
        sudo rm -rf "/opt/$app"
        sudo mkdir -p "/opt/$app"
        sudo cp -r build/linux/x64/release/bundle/* "/opt/$app/"
        cd ..
        
        setup_app_configs "$app"
    else
        echo "Error: Directory ./$app not found!"
        exit 1
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
            sudo ln -sf /opt/fyrfiles/fyr_files /usr/local/bin/fyrfiles
            if [ -f "./fyrfiles/assets/icons/folderfile.png" ]; then
                sudo mkdir -p /usr/share/icons/hicolor/512x512/apps
                sudo cp ./fyrfiles/assets/icons/folderfile.png /usr/share/icons/hicolor/512x512/apps/fyrfiles.png
            fi
            sudo tee /usr/share/applications/fyrfiles.desktop > /dev/null <<'EOF'
[Desktop Entry]
Name=fyrFiles
Comment=A modern, custom file manager
Exec=/usr/local/bin/fyrfiles
Icon=fyrfiles
Terminal=false
Type=Application
Categories=Utility;System;FileTools;
EOF
            sudo tee /usr/local/bin/fyr_files_picker > /dev/null <<'EOF'
#!/bin/bash
out="$5"
/usr/local/bin/fyrfiles --picker > "$out"
if [ ! -s "$out" ]; then exit 1; fi
exit 0
EOF
            sudo chmod +x /usr/local/bin/fyr_files_picker
            mkdir -p ~/.config/xdg-desktop-portal-termfilechooser
            echo -e "[filechooser]\ncmd=/usr/local/bin/fyr_files_picker" > ~/.config/xdg-desktop-portal-termfilechooser/config
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
Comment=System settings for FyrDE
Exec=/usr/local/bin/fyrsettings
Icon=fyrsettings
Terminal=false
Type=Application
Categories=System;Settings;
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
            ;;
        "fyrtext")
            sudo ln -sf /opt/fyrtext/fyrtext /usr/local/bin/fyrtext
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
        "fyrcode")
            sudo ln -sf /opt/fyrcode/fyrcode /usr/local/bin/fyrcode
            sudo tee /usr/share/applications/fyrcode.desktop > /dev/null <<'EOF'
[Desktop Entry]
Name=FyrCode
Comment=Advanced Code Editor for FyrDE
Exec=/usr/local/bin/fyrcode
Icon=accessories-text-editor
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
    esac
    
    if command -v update-desktop-database &> /dev/null; then
        sudo update-desktop-database /usr/share/applications || true
    fi
}

setup_sway_config() {
    echo "Setting up Sway configuration..."
    mkdir -p ~/.config/fyr
    cp ./backgrounds/space.jpg ~/.config/fyr/space.jpg
    
    # Toggle Floating Script
    cat << 'EOF' > ~/.config/fyr/toggle_floating.sh
#!/bin/bash
CONF="$HOME/.config/sway/floating.conf"
if [ -f "$CONF" ] && grep -q "floating enable" "$CONF"; then
    echo "" > "$CONF"
    swaymsg '[floating workspace="^[0-9]+$" app_id="(?!(fyrtaskbar|fyrdock|fyrsearch|fyroverview|fyrhelp|fyremoji)).*"] floating disable'
    swaymsg '[tiling] border pixel 2'
    swaymsg 'gaps inner all set 20'
    swaymsg 'gaps outer all set 20'
else
    echo 'for_window [class=".*"] floating enable' > "$CONF"
    echo 'for_window [app_id=".*"] floating enable' >> "$CONF"
    echo 'for_window [class=".*"] border pixel 4' >> "$CONF"
    echo 'for_window [app_id="(?!(fyrtaskbar|fyrdock|fyrsearch|fyroverview|fyrhelp|fyremoji)).*"] border pixel 4' >> "$CONF"
    echo 'default_floating_border pixel 4' >> "$CONF"
    echo 'gaps inner 0' >> "$CONF"
    echo 'gaps outer 0' >> "$CONF"
    swaymsg '[tiling] floating enable'
    swaymsg '[floating workspace="^[0-9]+$" class=".*"] border pixel 4'
    swaymsg '[floating workspace="^[0-9]+$" app_id="(?!(fyrtaskbar|fyrdock|fyrsearch|fyroverview|fyrhelp|fyremoji)).*"] border pixel 4'
    swaymsg 'gaps inner all set 0'
    swaymsg 'gaps outer all set 0'
fi
swaymsg reload
EOF
    chmod +x ~/.config/fyr/toggle_floating.sh

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
        excluded = ['fyrtaskbar', 'fyrdock', 'fyroverview', 'fyrsearch', 'fyrhelp', 'fyremoji']
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

    # Alt-Tab Script
    cat << 'EOF' > ~/.config/fyr/alttab.py
#!/usr/bin/env python3
import subprocess, json
def run(cmd): return subprocess.check_output(cmd, shell=True).decode('utf-8')
def get_windows(node, windows):
    if node.get('type') in ['con', 'floating_con'] and (node.get('app_id') or node.get('window_properties')) and not node.get('nodes'):
        windows.append(node); return
    for child in node.get('nodes', []) + node.get('floating_nodes', []): get_windows(child, windows)
def main():
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
    nid = windows[(fidx + 1) % len(windows)]['id']
    subprocess.run(['swaymsg', f'[con_id={nid}] focus'])
if __name__ == "__main__": main()
EOF
    chmod +x ~/.config/fyr/alttab.py

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

# Get focused output info
FOCUSED_OUTPUT=$(swaymsg -t get_outputs | jq -r '.[] | select(.focused) | .name')
X=$(swaymsg -t get_outputs | jq -r ".[] | select(.name == \"$FOCUSED_OUTPUT\") | .rect.x")
Y=$(swaymsg -t get_outputs | jq -r ".[] | select(.name == \"$FOCUSED_OUTPUT\") | .rect.y")
W=$(swaymsg -t get_outputs | jq -r ".[] | select(.name == \"$FOCUSED_OUTPUT\") | .rect.width")
H=$(swaymsg -t get_outputs | jq -r ".[] | select(.name == \"$FOCUSED_OUTPUT\") | .rect.height")

CONF="$HOME/.config/sway/floating.conf"
IS_FLOATING=0
if [ -f "$CONF" ] && grep -q "floating enable" "$CONF"; then
    IS_FLOATING=1
fi

ARG=$1

if [ "$ARG" = "hide" ]; then
    swaymsg '[app_id="fyrwindowoverview"] move scratchpad'
    swaymsg '[app_id="fyroverview"] move scratchpad'
    exit 0
fi

TARGET=""

if [ "$IS_FLOATING" -eq 1 ]; then
    if [ "$ARG" = "workspace" ]; then
        TARGET="fyroverview"
    else
        TARGET="fyrwindowoverview"
    fi
else
    TARGET="fyroverview"
fi

OTHER="fyrwindowoverview"
if [ "$TARGET" = "fyrwindowoverview" ]; then
    OTHER="fyroverview"
fi

swaymsg "[app_id=\"$OTHER\"] move scratchpad"
swaymsg "[app_id=\"$TARGET\"] scratchpad show, border none, resize set $W $H, move absolute position $X $Y"
EOF
    chmod +x ~/.config/fyr/overview_toggle.sh

    # Launcher Toggle Script
    cat << 'EOF' > ~/.config/fyr/launcher_toggle.sh
#!/bin/bash
FOCUSED_OUTPUT=$(swaymsg -t get_outputs | jq -r '.[] | select(.focused) | .name')
X=$(swaymsg -t get_outputs | jq -r ".[] | select(.name == \"$FOCUSED_OUTPUT\") | .rect.x")
Y=$(swaymsg -t get_outputs | jq -r ".[] | select(.name == \"$FOCUSED_OUTPUT\") | .rect.y")
W=$(swaymsg -t get_outputs | jq -r ".[] | select(.name == \"$FOCUSED_OUTPUT\") | .rect.width")
H=$(swaymsg -t get_outputs | jq -r ".[] | select(.name == \"$FOCUSED_OUTPUT\") | .rect.height")

# Toggle logic: if it's already visible on the current output, hide it
# Otherwise show it on the current output
VISIBLE=$(swaymsg -t get_tree | jq -r '.. | select(.app_id? == "fyrsearch" or .app_id? == "launcher") | .visible')

if [ "$VISIBLE" = "true" ]; then
    swaymsg '[app_id="(?i).*fyrsearch.*"] move scratchpad'
else
    swaymsg "[app_id=\"(?i).*fyrsearch.*\"] scratchpad show, border none, resize set $W $H, move absolute position $X $Y"
fi
EOF
    chmod +x ~/.config/fyr/launcher_toggle.sh

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

    mkdir -p ~/.config/sway
    if [ -f "./sway/config" ]; then
        cp ./sway/config ~/.config/sway/config
        sed -i "s/1920 1080/$WIDTH $HEIGHT/g" ~/.config/sway/config
        sed -i "s/1920x1080/${WIDTH}x${HEIGHT}/g" ~/.config/sway/config
        echo "Sway config updated with resolution ${WIDTH}x${HEIGHT}"
    fi
}

setup_themes() {
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
    echo "Setting up SDDM theme..."
    if [ -d "./sddm" ]; then
        sudo mkdir -p /usr/share/sddm/themes/fyr
        sudo cp -r ./sddm/theme/* /usr/share/sddm/themes/fyr/
        sudo mkdir -p /etc/sddm.conf.d
        sudo cp ./sddm/sddm.conf /etc/sddm.conf.d/fyr.conf
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
INSTALL_DEPS=false
INSTALL_SWAY_CONFIG=false
INSTALL_SDDM=false
INSTALL_THEMES=false
INSTALL_ZSH=false

setup_zsh() {
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

while getopts "a:sldthfz" opt; do
    MODULAR=true
    case $opt in
        a) APP_TO_REINSTALL="$OPTARG" ;;
        s) INSTALL_SWAY_CONFIG=true ;;
        l) INSTALL_SDDM=true ;;
        t) INSTALL_THEMES=true ;;
        d) INSTALL_DEPS=true ;;
        z) INSTALL_ZSH=true ;;
        f) MODULAR=false ;;
        h) usage; exit 0 ;;
        *) usage; exit 1 ;;
    esac
done

if [ "$MODULAR" = "false" ]; then
    echo "Starting full installation..."
    install_deps
    setup_zsh
    install_flutter
    build_swayfx
    for app in "${flutter_apps[@]}"; do
        reinstall_app "$app"
    done
    setup_sway_config
    setup_themes
    setup_sddm
else
    echo "Starting modular installation..."
    if [ "$INSTALL_DEPS" = "true" ]; then install_deps; fi
    if [ "$INSTALL_ZSH" = "true" ]; then setup_zsh; fi
    if [ -n "$APP_TO_REINSTALL" ]; then
        install_flutter
        reinstall_app "$APP_TO_REINSTALL"
    fi
    if [ "$INSTALL_SWAY_CONFIG" = "true" ]; then setup_sway_config; fi
    if [ "$INSTALL_SDDM" = "true" ]; then setup_sddm; fi
    if [ "$INSTALL_THEMES" = "true" ]; then setup_themes; fi
fi

echo "Operation complete!"

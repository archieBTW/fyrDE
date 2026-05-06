#!/bin/bash
set -e

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


if [ "$OS" = "arch" ] || [ "$OS" = "manjaro" ] || [ "$OS" = "endeavouros" ]; then
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
    else
        echo "yay is already installed."
    fi

    deps=( 
        "jq" "mesa-utils" "swaybg" "swaylock" "swayidle" "xorg-xwayland" "foot" "wmenu"
        "gtk-layer-shell" "xdg-desktop-portal" "xdg-desktop-portal-gtk"
        "xdg-desktop-portal-wlr" "xclip" "wl-clipboard" "brightnessctl"
        "wireplumber" "pipewire" "pipewire-pulse" "wlsunset" "cmake" "cpio" "pkg-config" "gcc" "wf-recorder" "grim" "ninja" "clang"
        "meson" "scdoc" "wayland-protocols" "pcre2" "json-c" "pango" "cairo" "gdk-pixbuf2" "unzip" "virt-viewer" "libvirt" "virt-install"
        "bluez" "bluez-utils" "xdg-utils" "slurp" "libnotify" "mako" "polkit-gnome" "network-manager-applet" "pavucontrol" "playerctl" "jq" "libcanberra" "psmisc" "pamixer" "sddm" "accountsservice" "qt5-declarative" "qt5-quickcontrols" "qt5-quickcontrols2" "qt5-graphicaleffects"
    )

    echo "Installing official dependencies via pacman..."
    sudo pacman -S --needed --noconfirm "${deps[@]}"

    echo "Installing build dependencies, flutter, and termfilechooser via yay..."
    yay -S --needed --noconfirm scenefx0.4 wlroots0.19 xdg-desktop-portal-termfilechooser-hunkyburrito-git

elif [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    echo "Updating system..."
    sudo apt-get update && sudo apt-get upgrade -y

    deps=(
        "swaybg" "swaylock" "swayidle" "xwayland" "foot" "libgtk-layer-shell-dev"
        "xdg-desktop-portal" "xdg-desktop-portal-gtk" "xdg-desktop-portal-wlr"
        "xclip" "wl-clipboard" "brightnessctl" "wireplumber" "pipewire" "pipewire-pulse" "cmake" "cpio"
        "pkg-config" "gcc" "wf-recorder" "grim" "ninja-build" "clang" "curl" "git" "unzip" "xz-utils" "zip" "libglu1-mesa" "sway" "virt-viewer" "libvirt-clients" "libvirt-daemon-system" "virtinst"
        "bluez" "bluez-tools" "xdg-utils" "slurp" "libnotify-bin" "mako-notifier" "polkit-gnome" "network-manager-gnome" "pavucontrol" "playerctl" "jq" "libcanberra-gtk3-module" "libcanberra-gtk-module" "psmisc" "pamixer" "sddm" "accountsservice" "policykit-1-gnome" "qml-module-qtquick-controls" "qml-module-qtquick-controls2" "qml-module-qtgraphicaleffects"
    )

    echo "Installing official dependencies via apt..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${deps[@]}"
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y wlsunset wmenu swayfx || echo "Some optional packages (wlsunset, wmenu, swayfx) might not be available, continuing..."



elif [ "$OS" = "fedora" ]; then
    echo "Updating system..."
    sudo dnf upgrade -y

    deps=(
        "swaybg" "swaylock" "swayidle" "xorg-x11-server-Xwayland" "foot" "gtk-layer-shell-devel"
        "xdg-desktop-portal" "xdg-desktop-portal-gtk" "xdg-desktop-portal-wlr"
        "xclip" "wl-clipboard" "brightnessctl" "wireplumber" "pipewire" "pipewire-pulseaudio" "cmake" "cpio"
        "pkgconf" "gcc" "wf-recorder" "grim" "ninja-build" "clang" "curl" "git" "unzip" "zip" "mesa-libGLU" "sway" "virt-viewer" "libvirt" "virt-install"
        "bluez" "bluez-utils" "xdg-utils" "slurp" "libnotify" "mako" "polkit-gnome" "nm-connection-editor" "pavucontrol" "playerctl" "jq" "libcanberra-gtk3" "psmisc" "pamixer" "sddm" "accountsservice" "lxqt-policykit" "qt5-qtquickcontrols" "qt5-qtquickcontrols2" "qt5-qtgraphicaleffects"
    )

    echo "Installing official dependencies via dnf..."
    sudo dnf install -y "${deps[@]}"
    sudo dnf install -y wlsunset wmenu swayfx || echo "Some optional packages (wlsunset, wmenu, swayfx) might not be available, continuing..."



else
    echo "Unsupported OS: $OS"
    echo "Please install dependencies and flutter manually, then run the build steps."
    exit 1
fi

echo "Ensuring Flutter 3.41.9 is installed in /opt/flutter..."
if [ ! -d "/opt/flutter" ] || [ "$(cat /opt/flutter/version 2>/dev/null)" != "3.41.9" ]; then
    sudo rm -rf /opt/flutter
    sudo git clone https://github.com/flutter/flutter.git -b 3.41.9 /opt/flutter
    sudo chown -R $USER:$USER /opt/flutter
fi
export PATH="$PATH:/opt/flutter/bin"
flutter doctor


echo "Building and installing local swayfx..."
if [ -d "./swayfx" ]; then
    cd ./swayfx
    rm -rf build
    meson setup build
    ninja -C build
    sudo ninja -C build install
    cd ..
else
    echo "Warning: Directory ./swayfx not found! Cannot install local swayfx."
    exit 1
fi

echo "Building and installing Flutter applications..."
git config --global --add safe.directory /opt/flutter || true
flutter config --enable-linux-desktop
echo "Patching Flutter applications with detected resolution..."
find . -maxdepth 2 -name "lib" -type d | while read dir; do
    find "$dir" -name "*.dart" -exec sed -i "s/1920/$WIDTH/g" {} +
    find "$dir" -name "*.dart" -exec sed -i "s/1080/$HEIGHT/g" {} +
done

if [ -f "./fyrdock/tree.json" ]; then
    sed -i "s/1920/$WIDTH/g" ./fyrdock/tree.json
    sed -i "s/1080/$HEIGHT/g" ./fyrdock/tree.json
fi

flutter_apps=("fyrdock" "fyroverview" "fyrsearch" "fyrsettings" "fyrtaskbar" "fyrterm" "fyrfiles" "fyrhelp" "fyremoji" "fyrstore" "fyrvirt" "fyrtext" "fyrdaw")


for app in "${flutter_apps[@]}"; do
    if [ -d "./$app" ]; then
        echo "Building $app..."
        cd "./$app"
        flutter clean || true
        flutter create --platforms=linux .
        flutter pub get
        flutter build linux
        
        echo "Installing $app to /opt/$app..."
        sudo rm -rf "/opt/$app"
        sudo mkdir -p "/opt/$app"
        sudo cp -r build/linux/x64/release/bundle/* "/opt/$app/"
        cd ..
    else
        echo "Warning: Directory ./$app not found!"
    fi
done

echo "Setting up fyrterm configurations..."
if [ -d "./fyrterm" ]; then
    sudo ln -sf /opt/fyrterm/fyrterm /usr/local/bin/fyrterm
    
    if [ -f "./fyrterm/assets/icons/fyrterm.png" ]; then
        sudo mkdir -p /usr/share/icons/hicolor/512x512/apps
        sudo cp ./fyrterm/assets/icons/fyrterm.png /usr/share/icons/hicolor/512x512/apps/fyrterm.png
    fi

    sudo tee /usr/share/applications/fyrterm.desktop > /dev/null <<'EOF'
[Desktop Entry]
Version=1.0
Name=fyrterm
GenericName=Terminal Emulator
Comment=A flutter terminal emulator
Exec=/usr/local/bin/fyrterm
Icon=fyrterm
Terminal=false
Type=Application
Categories=System;TerminalEmulator;
EOF

    if command -v update-desktop-database &> /dev/null; then
        sudo update-desktop-database /usr/share/applications || true
    fi

    if command -v gtk-update-icon-cache &> /dev/null; then
        sudo gtk-update-icon-cache -f -t /usr/share/icons/hicolor || true
    fi

    sudo update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator /usr/local/bin/fyrterm 50 || true
fi

echo "Setting up fyrfiles configurations..."
if [ -d "./fyrfiles" ]; then
    sudo ln -sf /opt/fyrfiles/fyr_files /usr/local/bin/fyrfiles

    sudo tee /usr/share/applications/fyrfiles.desktop > /dev/null <<'EOF'
[Desktop Entry]
Name=fyrfiles
Comment=A modern, custom file manager
Exec=/usr/local/bin/fyrfiles
Icon=system-file-manager
Terminal=false
Type=Application
Categories=Utility;System;FileTools;
EOF

    if command -v update-desktop-database &> /dev/null; then
        sudo update-desktop-database /usr/share/applications || true
    fi

    echo "Setting up fyrfiles as default file picker for Sway..."
    sudo tee /usr/local/bin/fyr_files_picker > /dev/null <<'EOF'
#!/bin/bash
out="$5"
/usr/local/bin/fyrfiles --picker > "$out"
if [ ! -s "$out" ]; then
    exit 1
fi
exit 0
EOF
    sudo chmod +x /usr/local/bin/fyr_files_picker

    mkdir -p ~/.config/xdg-desktop-portal-termfilechooser
    cat > ~/.config/xdg-desktop-portal-termfilechooser/config <<EOF
[filechooser]
cmd=/usr/local/bin/fyr_files_picker
EOF

    mkdir -p ~/.config/xdg-desktop-portal
    cat > ~/.config/xdg-desktop-portal/sway-portals.conf <<EOF
[preferred]
default=wlr;gtk;
org.freedesktop.impl.portal.FileChooser=termfilechooser
EOF
fi

echo "Setting up FyrStore configurations..."
if [ -d "./fyrstore" ]; then
    sudo ln -sf /opt/fyrstore/fyrstore /usr/local/bin/fyrstore
    
    sudo tee /usr/share/applications/fyrstore.desktop > /dev/null <<'EOF'
[Desktop Entry]
Name=FyrStore
Type=Application
Exec=/usr/local/bin/fyrstore
Icon=system-software-install
Terminal=false
Categories=System;Settings;
EOF
    
    if command -v update-desktop-database &> /dev/null; then
        sudo update-desktop-database /usr/share/applications || true
    fi
fi

echo "Setting up FyrSettings configurations..."
if [ -d "./fyrsettings" ]; then
    sudo ln -sf /opt/fyrsettings/fyrsettings /usr/local/bin/fyrsettings
    
    sudo tee /usr/share/applications/fyrsettings.desktop > /dev/null <<'EOF'
[Desktop Entry]
Name=FyrSettings
Comment=System settings for FyrDE
Exec=/usr/local/bin/fyrsettings
Icon=preferences-system
Terminal=false
Type=Application
Categories=System;Settings;
EOF
    
    if command -v update-desktop-database &> /dev/null; then
        sudo update-desktop-database /usr/share/applications || true
    fi
fi

echo "Setting up FyrVirt configurations..."
if [ -d "./fyrvirt" ]; then
    sudo ln -sf /opt/fyrvirt/fyrvirt /usr/local/bin/fyrvirt
    
    sudo tee /usr/share/applications/fyrvirt.desktop > /dev/null <<'EOF'
[Desktop Entry]
Name=FyrVirt
Comment=Virtual Machine Manager for FyrDE
Exec=/usr/local/bin/fyrvirt
Icon=virt-manager
Terminal=false
Type=Application
Categories=System;Virtualization;
EOF
    
    if command -v update-desktop-database &> /dev/null; then
        sudo update-desktop-database /usr/share/applications || true
    fi
fi

echo "Setting up FyrText configurations..."
if [ -d "./fyrtext" ]; then
    sudo ln -sf /opt/fyrtext/fyrtext /usr/local/bin/fyrtext
    
    sudo cp ./fyrtext/fyrtext.desktop /usr/share/applications/fyrtext.desktop
    
    if command -v update-desktop-database &> /dev/null; then
        sudo update-desktop-database /usr/share/applications || true
    fi
    
    # Set as default for text files
    xdg-mime default fyrtext.desktop text/plain || true
fi

echo "Setting up FyrDAW configurations..."
if [ -d "./fyrdaw" ]; then
    sudo ln -sf /opt/fyrdaw/fyrdaw /usr/local/bin/fyrdaw
    
    sudo cp ./fyrdaw/fyrdaw.desktop /usr/share/applications/fyrdaw.desktop
    
    if command -v update-desktop-database &> /dev/null; then
        sudo update-desktop-database /usr/share/applications || true
    fi
fi

echo "Setting up Floating Mode script..."
mkdir -p ~/.config/fyr
cp ./backgrounds/space.jpg ~/.config/fyr/space.jpg

mkdir -p ~/.config/sway

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

echo "Setting up Retile script..."
cat << 'EOF' > ~/.config/fyr/retile.py
#!/usr/bin/env python3
import subprocess
import json
import sys

def run(cmd):
    try:
        return subprocess.check_output(cmd, shell=True).decode('utf-8')
    except subprocess.CalledProcessError:
        return ""

def main():
    tree_out = run('swaymsg -t get_tree')
    if not tree_out:
        return
    tree = json.loads(tree_out)
    
    ws_out = run('swaymsg -t get_workspaces')
    if not ws_out:
        return
    workspaces = json.loads(ws_out)
    focused_ws = next((w for w in workspaces if w.get('focused')), None)
    if not focused_ws:
        return

    def get_windows(node):
        wins = []
        app_id = node.get('app_id')
        class_name = node.get('window_properties', {}).get('class')
        name = node.get('name')
        
        excluded = ['fyrtaskbar', 'fyrdock', 'fyroverview', 'fyrsearch', 'fyrhelp', 'fyremoji']
        
        is_internal = False
        if app_id in excluded: is_internal = True
        if class_name in excluded: is_internal = True
        if name in excluded: is_internal = True
        
        if not is_internal and node.get('type') in ['con', 'floating_con'] and (app_id or class_name or name):
            if not node.get('nodes'):
                wins.append(node)
        for child in node.get('nodes', []) + node.get('floating_nodes', []):
            wins.extend(get_windows(child))
        return wins

    def find_ws(node):
        if node.get('type') == 'workspace' and node.get('name') == focused_ws['name']: return node
        for c in node.get('nodes', []):
            res = find_ws(c)
            if res: return res
        return None

    ws_node = find_ws(tree)
    if not ws_node:
        return

    windows = get_windows(ws_node)
    if not windows:
        return
    
    windows.sort(key=lambda w: (w['rect']['x'], w['rect']['y']))
    
    for w in windows:
        run(f'swaymsg "[con_id={w["id"]}] move workspace {focused_ws["name"]}"')
    
    for w in windows:
        run(f'swaymsg "[con_id={w["id"]}] floating disable"')
    
    run(f'swaymsg "workspace {focused_ws["name"]}; layout splith"')
    
    if len(windows) % 2 == 0 and len(windows) > 0:
        half = len(windows) // 2
        for i in range(half):
            w_top = windows[i]
            w_bot = windows[i + half]
            run(f'swaymsg "[con_id={w_top["id"]}] focus; splitv"')
            run(f'swaymsg "[con_id={w_bot["id"]}] move down"')
            run(f'swaymsg "[con_id={w_top["id"]}] mark target"')
            run(f'swaymsg "[con_id={w_bot["id"]}] move window to mark target"')
            run(f'swaymsg "[con_id={w_top["id"]}] unmark target"')
            
if __name__ == "__main__":
    main()
EOF
chmod +x ~/.config/fyr/retile.py

echo "Setting up Alt-Tab script..."
cat << 'EOF' > ~/.config/fyr/alttab.py
#!/usr/bin/env python3
import subprocess
import json

def run(cmd):
    return subprocess.check_output(cmd, shell=True).decode('utf-8')

def get_windows(node, windows):
    if node.get('type') in ['con', 'floating_con']:
        if (node.get('app_id') or node.get('window_properties')) and not node.get('nodes'):
            windows.append(node)
            return
    for child in node.get('nodes', []) + node.get('floating_nodes', []):
        get_windows(child, windows)

def main():
    try:
        tree = json.loads(run('swaymsg -t get_tree'))
        workspaces = json.loads(run('swaymsg -t get_workspaces'))
    except Exception:
        return

    focused_ws_name = next((ws['name'] for ws in workspaces if ws['focused']), None)
    if not focused_ws_name:
        return

    def find_workspace_node(node, name):
        if node.get('type') == 'workspace' and node.get('name') == name:
            return node
        for child in node.get('nodes', []) + node.get('floating_nodes', []):
            res = find_workspace_node(child, name)
            if res: return res
        return None

    workspace_node = find_workspace_node(tree, focused_ws_name)
    if not workspace_node:
        return

    windows = []
    get_windows(workspace_node, windows)
    if len(windows) < 2:
        return

    def find_focused_node_id(node):
        if node.get('focused'):
            return node.get('id')
        for child in node.get('nodes', []) + node.get('floating_nodes', []):
            res = find_focused_node_id(child)
            if res: return res
        return None

    focused_id = find_focused_node_id(tree)
    focused_idx = -1
    for i, w in enumerate(windows):
        if w.get('id') == focused_id:
            focused_idx = i
            break
    
    next_idx = (focused_idx + 1) % len(windows)
    next_id = windows[next_idx]['id']
    subprocess.run(['swaymsg', f'[con_id={next_id}] focus'])

if __name__ == "__main__":
    main()
EOF
chmod +x ~/.config/fyr/alttab.py

touch ~/.config/sway/floating.conf

echo "Setting up Screen Recording script..."
cat << 'EOF' > ~/.config/fyr/toggle_recording.sh
#!/bin/bash
pid=$(pgrep wf-recorder)
if [ -n "$pid" ]; then
    kill -SIGINT $pid
    notify-send "Screen Recording" "Saved to ~/Videos/screencasts/"
else
    mkdir -p ~/Videos/screencasts
    wf-recorder -f ~/Videos/screencasts/$(date +'%Y-%m-%d_%H-%M-%S').mp4 &
    notify-send "Screen Recording" "Started"
fi
EOF
chmod +x ~/.config/fyr/toggle_recording.sh


echo "Copying sway configuration..."
mkdir -p ~/.config/sway
if [ -f "./sway/config" ]; then
    cp ./sway/config ~/.config/sway/config
    
    # Get screen resolution (already detected at top, but just in case we're using a cached config)
    sed -i "s/1920 1080/$WIDTH $HEIGHT/g" ~/.config/sway/config
    sed -i "s/1920x1080/${WIDTH}x${HEIGHT}/g" ~/.config/sway/config
    
    echo "Sway config successfully copied and updated with resolution ${WIDTH}x${HEIGHT} to ~/.config/sway/config"
else
    echo "Warning: ./sway/config not found. Make sure you are running this script from the 'de' directory."
fi



echo "Installing Tela Icon Theme..."
if [ ! -d "$HOME/.local/share/icons/Tela-purple-dark" ]; then
    git clone https://github.com/vinceliuice/Tela-icon-theme.git /tmp/Tela-icon-theme
    cd /tmp/Tela-icon-theme
    ./install.sh -a
    cd -
    rm -rf /tmp/Tela-icon-theme
else
    echo "Tela icons already installed, skipping..."
fi

echo "Installing Fyr themes..."
if [ -d "./themes" ]; then
    # Install GTK 3.0 Theme
    mkdir -p ~/.themes/Fyr-Dark/gtk-3.0
    cp -r ./themes/gtk-3.0/* ~/.themes/Fyr-Dark/gtk-3.0/
    
    # Install GTK 4.0 / Libadwaita Themes
    mkdir -p ~/.config/gtk-4.0
    cp ./themes/gtk-4.0/gtk-dark.css ~/.config/gtk-4.0/gtk-dark.css
    cp ./themes/gtk-4.0/gtk-light.css ~/.config/gtk-4.0/gtk-light.css
    
    # By default apply the dark theme
    cp ~/.config/gtk-4.0/gtk-dark.css ~/.config/gtk-4.0/gtk.css

    # Apply initial GTK settings globally
    mkdir -p ~/.config/gtk-3.0
    cat <<EOF > ~/.config/gtk-3.0/settings.ini
[Settings]
gtk-theme-name=Fyr-Dark
gtk-icon-theme-name=Tela-purple-dark
gtk-application-prefer-dark-theme=1
gtk-decoration-layout=close:
EOF

    cat <<EOF > ~/.config/gtk-4.0/settings.ini
[Settings]
gtk-theme-name=Fyr-Dark
gtk-icon-theme-name=Tela-purple-dark
gtk-application-prefer-dark-theme=1
gtk-decoration-layout=close:
EOF

    # Enforce GTK settings using gsettings for libadwaita/gnome apps
    gsettings set org.gnome.desktop.interface gtk-theme "Fyr-Dark" || true
    gsettings set org.gnome.desktop.interface icon-theme "Tela-purple-dark" || true
    gsettings set org.gnome.desktop.interface color-scheme "prefer-dark" || true

    echo "Installing Firefox theme..."
    for ff_path in "$HOME/.mozilla/firefox" "$HOME/.var/app/org.mozilla.firefox/.mozilla/firefox"; do
        if [ -d "$ff_path" ]; then
            for profile in "$ff_path"/*.default*; do
                if [ -d "$profile" ]; then
                    mkdir -p "$profile/chrome"
                    cp -r ./themes/firefox/chrome/* "$profile/chrome/"
                    if ! grep -q "toolkit.legacyUserProfileCustomizations.stylesheets" "$profile/user.js" 2>/dev/null; then
                        echo 'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);' >> "$profile/user.js"
                    fi
                fi
            done
        fi
    done
else
    echo "Warning: ./themes directory not found!"
fi

echo "Setting up SDDM theme..."
if [ -d "./sddm" ]; then
    sudo mkdir -p /usr/share/sddm/themes/fyr
    sudo cp -r ./sddm/theme/* /usr/share/sddm/themes/fyr/
    
    sudo mkdir -p /etc/sddm.conf.d
    sudo cp ./sddm/sddm.conf /etc/sddm.conf.d/fyr.conf
    
    echo "SDDM theme 'fyr' installed and configured."
    sudo systemctl enable sddm || echo "Could not enable sddm service, please check manually."
else
    echo "Warning: ./sddm directory not found!"
fi

echo "Installation complete!"


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
        "swaybg" "swaylock" "swayidle" "xorg-xwayland" "foot" "wmenu"
        "gtk-layer-shell" "xdg-desktop-portal" "xdg-desktop-portal-gtk"
        "xdg-desktop-portal-wlr" "xclip" "wl-clipboard" "brightnessctl"
        "wireplumber" "wlsunset" "cmake" "cpio" "pkg-config" "gcc" "wf-recorder" "grim" "ninja" "clang"
        "meson" "scdoc" "wayland-protocols" "pcre2" "json-c" "pango" "cairo" "gdk-pixbuf2"
    )

    echo "Installing official dependencies via pacman..."
    sudo pacman -S --needed --noconfirm "${deps[@]}"

    echo "Installing build dependencies, flutter, and termfilechooser via yay..."
    yay -S --needed --noconfirm scenefx0.4 wlroots0.19 xdg-desktop-portal-termfilechooser-hunkyburrito-git # flutter

elif [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    echo "Updating system..."
    sudo apt-get update && sudo apt-get upgrade -y

    deps=(
        "swaybg" "swaylock" "swayidle" "xwayland" "foot" "libgtk-layer-shell-dev"
        "xdg-desktop-portal" "xdg-desktop-portal-gtk" "xdg-desktop-portal-wlr"
        "xclip" "wl-clipboard" "brightnessctl" "wireplumber" "cmake" "cpio"
        "pkg-config" "gcc" "wf-recorder" "grim" "ninja-build" "clang" "curl" "git" "unzip" "xz-utils" "zip" "libglu1-mesa" "sway"
    )

    echo "Installing official dependencies via apt..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${deps[@]}"
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y wlsunset wmenu swayfx || echo "Some optional packages (wlsunset, wmenu, swayfx) might not be available, continuing..."

    if ! command -v flutter &> /dev/null; then
        echo "Flutter not found. Installing via snap..."
        sudo snap install flutter --classic || echo "Failed to install flutter via snap. Please install flutter manually."
    fi

elif [ "$OS" = "fedora" ]; then
    echo "Updating system..."
    sudo dnf upgrade -y

    deps=(
        "swaybg" "swaylock" "swayidle" "xorg-x11-server-Xwayland" "foot" "gtk-layer-shell-devel"
        "xdg-desktop-portal" "xdg-desktop-portal-gtk" "xdg-desktop-portal-wlr"
        "xclip" "wl-clipboard" "brightnessctl" "wireplumber" "cmake" "cpio"
        "pkgconf" "gcc" "wf-recorder" "grim" "ninja-build" "clang" "curl" "git" "unzip" "zip" "mesa-libGLU" "sway"
    )

    echo "Installing official dependencies via dnf..."
    sudo dnf install -y "${deps[@]}"
    sudo dnf install -y wlsunset wmenu swayfx || echo "Some optional packages (wlsunset, wmenu, swayfx) might not be available, continuing..."

    if ! command -v flutter &> /dev/null; then
        echo "Flutter not found. Please install Flutter manually: https://docs.flutter.dev/get-started/install/linux"
        exit 1
    fi

else
    echo "Unsupported OS: $OS"
    echo "Please install dependencies and flutter manually, then run the build steps."
    exit 1
fi

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

flutter_apps=("fyrdock" "fyroverview" "fyrsearch" "fyrsettings" "fyrtaskbar" "fyrTerm" "fyrFiles" "fyrhelp" "fyremoji" "fyrstore")

for app in "${flutter_apps[@]}"; do
    if [ -d "./$app" ]; then
        echo "Building $app..."
        cd "./$app"
        flutter clean || true
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

echo "Setting up fyrTerm configurations..."
if [ -d "./fyrTerm" ]; then
    sudo ln -sf /opt/fyrTerm/fyrterm /usr/local/bin/fyrterm
    
    if [ -f "./fyrTerm/assets/icons/fyrterm.png" ]; then
        sudo mkdir -p /usr/share/icons/hicolor/512x512/apps
        sudo cp ./fyrTerm/assets/icons/fyrterm.png /usr/share/icons/hicolor/512x512/apps/fyrterm.png
    fi

    sudo tee /usr/share/applications/fyrterm.desktop > /dev/null <<'EOF'
[Desktop Entry]
Version=1.0
Name=fyrTerm
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

echo "Setting up FyrFiles configurations..."
if [ -d "./fyrFiles" ]; then
    sudo ln -sf /opt/fyrFiles/fyr_files /usr/local/bin/fyrfiles

    sudo tee /usr/share/applications/fyrfiles.desktop > /dev/null <<'EOF'
[Desktop Entry]
Name=FyrFiles
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

    echo "Setting up FyrFiles as default file picker for Sway..."
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

echo "Setting up Floating Mode script..."
mkdir -p ~/.config/fyr
mkdir -p ~/.config/sway

cat << 'EOF' > ~/.config/fyr/toggle_floating.sh
#!/bin/bash
CONF="$HOME/.config/sway/floating.conf"

if [ -f "$CONF" ] && grep -q "floating enable" "$CONF"; then
    echo "" > "$CONF"
    swaymsg '[floating app_id="(?!(fyrtaskbar|fyrdock|fyrsearch|fyroverview|fyrhelp|fyremoji)).*"] floating disable'
else
    echo "for_window [class=\".*\"] floating enable" > "$CONF"
    echo "for_window [app_id=\".*\"] floating enable" >> "$CONF"
    echo "default_floating_border normal" >> "$CONF"
    swaymsg '[tiling] floating enable'
fi
swaymsg reload
EOF
chmod +x ~/.config/fyr/toggle_floating.sh

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
    echo "Sway config successfully copied to ~/.config/sway/config"
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
    cp ~/.themes/Fyr-Dark/gtk-4.0/gtk.css ~/.config/gtk-4.0/gtk-dark.css
    cp ~/.themes/Fyr-Light/gtk-4.0/gtk.css ~/.config/gtk-4.0/gtk-light.css
    
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

echo "Installation complete!"


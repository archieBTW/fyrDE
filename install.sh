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
        "wireplumber" "wlsunset" "cmake" "cpio" "pkg-config" "gcc" "grim" "ninja" "clang"
    )

    echo "Installing official dependencies via pacman..."
    sudo pacman -S --needed --noconfirm "${deps[@]}"

    echo "Installing swayfx and flutter via yay..."
    yay -S --needed --noconfirm swayfx flutter

elif [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    echo "Updating system..."
    sudo apt-get update && sudo apt-get upgrade -y

    deps=(
        "swaybg" "swaylock" "swayidle" "xwayland" "foot" "libgtk-layer-shell-dev"
        "xdg-desktop-portal" "xdg-desktop-portal-gtk" "xdg-desktop-portal-wlr"
        "xclip" "wl-clipboard" "brightnessctl" "wireplumber" "cmake" "cpio"
        "pkg-config" "gcc" "grim" "ninja-build" "clang" "curl" "git" "unzip" "xz-utils" "zip" "libglu1-mesa" "sway"
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
        "pkgconf" "gcc" "grim" "ninja-build" "clang" "curl" "git" "unzip" "zip" "mesa-libGLU" "sway"
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

echo "Building and installing Flutter applications..."
git config --global --add safe.directory /opt/flutter || true

flutter_apps=("fyrdock" "fyroverview" "fyrsearch" "fyrsettings" "fyrtaskbar")

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
gtk-decoration-layout=close,minimize,maximize:
EOF

    cat <<EOF > ~/.config/gtk-4.0/settings.ini
[Settings]
gtk-theme-name=Fyr-Dark
gtk-icon-theme-name=Tela-purple-dark
gtk-application-prefer-dark-theme=1
gtk-decoration-layout=close,minimize,maximize:
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


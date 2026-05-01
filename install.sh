#!/bin/bash
set -e

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
    "swaybg"
    "swaylock"
    "swayidle"
    "xorg-xwayland"
    "foot"
    "wmenu"
    "gtk-layer-shell"
    "xdg-desktop-portal"
    "xdg-desktop-portal-gtk"
    "xdg-desktop-portal-wlr"
    "xclip"
    "wl-clipboard"
    "brightnessctl"
    "wireplumber"
    "wlsunset"
    "cmake"
    "cpio"
    "pkg-config"
    "gcc"
    "grim"
)

echo "Installing official dependencies via pacman..."
sudo pacman -S --needed --noconfirm "${deps[@]}"

echo "Installing swayfx via yay..."
yay -S --needed --noconfirm swayfx

echo "Copying sway configuration..."
mkdir -p ~/.config/sway
if [ -f "./sway/config" ]; then
    cp ./sway/config ~/.config/sway/config
    echo "Sway config successfully copied to ~/.config/sway/config"
else
    echo "Warning: ./sway/config not found. Make sure you are running this script from the 'de' directory."
fi

echo "Installation complete!"

#!/bin/bash
set -e

if [ ! -f "pubspec.yaml" ]; then
    echo "Please run this script from the fyrslides project root."
    exit 1
fi

echo "Building fyrSlides..."
flutter pub get
flutter build linux --release

echo "Installing fyrSlides system-wide (requires sudo)..."
INSTALL_DIR="/opt/fyrslides"
BIN_DIR="/usr/local/bin"
APP_DIR="/usr/share/applications"
ICON_DIR="/usr/share/icons/hicolor/512x512/apps"

sudo mkdir -p "$INSTALL_DIR" "$BIN_DIR" "$APP_DIR" "$ICON_DIR"

sudo rm -rf "$INSTALL_DIR"/*
sudo cp -r build/linux/x64/release/bundle/* "$INSTALL_DIR/"
sudo ln -sf "$INSTALL_DIR/fyrslides" "$BIN_DIR/fyrslides"

if [ -f "assets/icons/fyrslides.png" ]; then
    sudo cp assets/icons/fyrslides.png "$ICON_DIR/fyrslides.png"
fi

sudo cp fyrslides.desktop "$APP_DIR/fyrslides.desktop"

if command -v update-desktop-database &> /dev/null; then
    sudo update-desktop-database "$APP_DIR" || true
fi

if command -v gtk-update-icon-cache &> /dev/null; then
    sudo gtk-update-icon-cache -f -t /usr/share/icons/hicolor || true
fi

echo "fyrSlides installed successfully!"

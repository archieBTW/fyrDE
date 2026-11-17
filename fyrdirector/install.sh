#!/bin/bash
set -e

if [ ! -f "pubspec.yaml" ]; then
    echo "Please run this script from the fyrdirector project root."
    exit 1
fi

echo "Building fyrDirector..."
flutter pub get
flutter build linux --release

echo "Installing fyrDirector system-wide (requires sudo)..."
INSTALL_DIR="/opt/fyrdirector"
BIN_DIR="/usr/local/bin"
APP_DIR="/usr/share/applications"
ICON_DIR="/usr/share/icons/hicolor/512x512/apps"

sudo mkdir -p "$INSTALL_DIR" "$BIN_DIR" "$APP_DIR" "$ICON_DIR"

sudo rm -rf "$INSTALL_DIR"/*
sudo cp -r build/linux/x64/release/bundle/* "$INSTALL_DIR/"
sudo ln -sf "$INSTALL_DIR/fyrdirector" "$BIN_DIR/fyrdirector"

if [ -f "assets/icons/fyrdirector.png" ]; then
    sudo cp assets/icons/fyrdirector.png "$ICON_DIR/fyrdirector.png"
fi

sudo cp fyrdirector.desktop "$APP_DIR/fyrdirector.desktop"

if command -v update-desktop-database &> /dev/null; then
    sudo update-desktop-database "$APP_DIR" || true
fi

if command -v gtk-update-icon-cache &> /dev/null; then
    sudo gtk-update-icon-cache -f -t /usr/share/icons/hicolor || true
fi

echo "fyrDirector installed successfully!"
echo "You can now run 'fyrdirector [project.fyrd]' from the terminal."

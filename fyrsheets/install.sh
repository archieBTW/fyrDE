#!/bin/bash
set -e

if [ ! -f "pubspec.yaml" ]; then
    echo "Please run this script from the fyrsheets project root."
    exit 1
fi

echo "Building fyrSheets..."
flutter pub get
flutter build linux --release

echo "Installing fyrSheets system-wide (requires sudo)..."
INSTALL_DIR="/opt/fyrsheets"
BIN_DIR="/usr/local/bin"
APP_DIR="/usr/share/applications"
ICON_DIR="/usr/share/icons/hicolor/512x512/apps"

sudo mkdir -p "$INSTALL_DIR" "$BIN_DIR" "$APP_DIR" "$ICON_DIR"

sudo rm -rf "$INSTALL_DIR"/*
sudo cp -r build/linux/x64/release/bundle/* "$INSTALL_DIR/"
sudo ln -sf "$INSTALL_DIR/fyrsheets" "$BIN_DIR/fyrsheets"

if [ -f "assets/icons/fyrsheets.png" ]; then
    sudo cp assets/icons/fyrsheets.png "$ICON_DIR/fyrsheets.png"
fi

sudo cp fyrsheets.desktop "$APP_DIR/fyrsheets.desktop"

if command -v update-desktop-database &> /dev/null; then
    sudo update-desktop-database "$APP_DIR" || true
fi

if command -v gtk-update-icon-cache &> /dev/null; then
    sudo gtk-update-icon-cache -f -t /usr/share/icons/hicolor || true
fi

echo "fyrSheets installed successfully!"

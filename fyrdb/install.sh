#!/bin/bash
set -e

if [ ! -f "pubspec.yaml" ]; then
    echo "Please run this script from the fyrdb project root."
    exit 1
fi

echo "Building fyrDB..."
flutter pub get
flutter build linux --release

echo "Installing fyrDB system-wide (requires sudo)..."
INSTALL_DIR="/opt/fyrdb"
BIN_DIR="/usr/local/bin"
APP_DIR="/usr/share/applications"
ICON_DIR="/usr/share/icons/hicolor/512x512/apps"

sudo mkdir -p "$INSTALL_DIR" "$BIN_DIR" "$APP_DIR" "$ICON_DIR"

sudo rm -rf "$INSTALL_DIR"/*
sudo cp -r build/linux/x64/release/bundle/* "$INSTALL_DIR/"
sudo ln -sf "$INSTALL_DIR/fyrdb" "$BIN_DIR/fyrdb"

if [ -f "assets/icons/fyrdb.png" ]; then
    sudo cp assets/icons/fyrdb.png "$ICON_DIR/fyrdb.png"
fi

sudo cp fyrdb.desktop "$APP_DIR/fyrdb.desktop"

if command -v update-desktop-database &> /dev/null; then
    sudo update-desktop-database "$APP_DIR" || true
fi

if command -v gtk-update-icon-cache &> /dev/null; then
    sudo gtk-update-icon-cache -f -t /usr/share/icons/hicolor || true
fi

echo "fyrDB installed successfully!"

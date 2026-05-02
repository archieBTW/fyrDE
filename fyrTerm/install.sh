#!/bin/bash
set -e

# Ensure we're in the right directory
if [ ! -f "pubspec.yaml" ]; then
    echo "Please run this script from the fyrTerm project root."
    exit 1
fi

echo "Building fyrTerm..."
flutter build linux --release

echo "Installing fyrTerm system-wide (requires sudo)..."
INSTALL_DIR="/opt/fyrTerm"
BIN_DIR="/usr/local/bin"
APP_DIR="/usr/share/applications"
ICON_DIR="/usr/share/icons/hicolor/512x512/apps"

sudo mkdir -p "$INSTALL_DIR"
sudo mkdir -p "$BIN_DIR"
sudo mkdir -p "$APP_DIR"
sudo mkdir -p "$ICON_DIR"

# Copy binary and data
sudo rm -rf "$INSTALL_DIR"/*
sudo cp -r build/linux/x64/release/bundle/* "$INSTALL_DIR/"

# Create a symlink to CLI
sudo ln -sf "$INSTALL_DIR/fyrterm" "$BIN_DIR/fyrterm"

# Copy icon
if [ -f "assets/icons/fyrterm.png" ]; then
    sudo cp assets/icons/fyrterm.png "$ICON_DIR/fyrterm.png"
fi

# Create a .desktop file
sudo bash -c "cat <<EOF > $APP_DIR/fyrterm.desktop
[Desktop Entry]
Version=1.0
Name=fyrTerm
GenericName=Terminal Emulator
Comment=A flutter terminal emulator
Exec=$BIN_DIR/fyrterm
Icon=fyrterm
Terminal=false
Type=Application
Categories=System;TerminalEmulator;
EOF"

# Update desktop database
if command -v update-desktop-database &> /dev/null; then
    sudo update-desktop-database "$APP_DIR" || true
fi

# Update icon cache
if command -v gtk-update-icon-cache &> /dev/null; then
    sudo gtk-update-icon-cache -f -t /usr/share/icons/hicolor || true
fi

sudo update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator /usr/local/bin/fyrterm 50 || true

echo "fyrTerm installed successfully!"
echo "You can now run 'fyrterm' from the CLI or find it in your application launcher."

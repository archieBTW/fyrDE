#!/bin/bash
set -e

# Ensure we're in the right directory
if [ ! -f "pubspec.yaml" ]; then
    echo "Please run this script from the fyrcode project root."
    exit 1
fi

echo "Building FyrCode..."
flutter build linux --release

echo "Installing FyrCode system-wide (requires sudo)..."
INSTALL_DIR="/opt/fyrcode"
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
sudo ln -sf "$INSTALL_DIR/fyrcode" "$BIN_DIR/fyrcode"

# Copy icon
if [ -f "assets/icons/code.png" ]; then
    sudo cp assets/icons/code.png "$ICON_DIR/fyrcode.png"
fi

# Create a .desktop file
sudo bash -c "cat <<EOF > $APP_DIR/fyrcode.desktop
[Desktop Entry]
Name=FyrCode
Comment=Advanced Code Editor for FyrDE
Exec=$BIN_DIR/fyrcode %U
Icon=fyrcode
Terminal=false
Type=Application
Categories=Development;TextEditor;IDE;
EOF"

# Update desktop database
if command -v update-desktop-database &> /dev/null; then
    sudo update-desktop-database "$APP_DIR" || true
fi

# Update icon cache
if command -v gtk-update-icon-cache &> /dev/null; then
    sudo gtk-update-icon-cache -f -t /usr/share/icons/hicolor || true
fi

echo "FyrCode installed successfully!"
echo "You can now run 'fyrcode [folder]' from the terminal."

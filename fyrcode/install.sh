#!/bin/bash

# Exit on error
set -e

echo "Building FyrCode..."
flutter build linux

# Define installation paths
INSTALL_DIR="$HOME/.local/share/fyrcode"
BIN_PATH="$HOME/.local/bin/fyrcode"

echo "Installing to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
cp -r build/linux/x64/release/bundle/* "$INSTALL_DIR/"

echo "Creating executable wrapper at $BIN_PATH..."
mkdir -p "$HOME/.local/bin"
cat > "$BIN_PATH" << 'EOF'
#!/bin/bash
"$HOME/.local/share/fyrcode/fyrcode" "$@"
EOF

chmod +x "$BIN_PATH"

echo "Creating Desktop entry..."
DESKTOP_DIR="$HOME/.local/share/applications"
DESKTOP_FILE="$DESKTOP_DIR/fyrcode.desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_FILE" << EOF
[Desktop Entry]
Name=FyrCode
Comment=Flutter Code Editor
Exec=$BIN_PATH %U
Icon=code
Terminal=false
Type=Application
Categories=Development;IDE;
EOF

echo "FyrCode installed successfully!"
echo "Make sure $HOME/.local/bin is in your PATH."
echo "You can now run 'fyrcode [folder]' from the terminal."

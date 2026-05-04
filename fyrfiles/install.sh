#!/bin/bash

# Exit on error
set -e

echo "Building fyrfiles for Linux..."
flutter build linux --release

echo "Installing fyrfiles..."
# Remove any previous installation
sudo rm -rf /opt/fyrfiles

# Copy the new build bundle to /opt
sudo cp -r build/linux/x64/release/bundle /opt/fyrfiles

# Create a symlink to /usr/local/bin
sudo ln -sf /opt/fyrfiles/fyr_files /usr/local/bin/fyrfiles

# Create a desktop entry
echo "[Desktop Entry]
Name=fyrfiles
Comment=A modern, custom file manager
Exec=/usr/local/bin/fyrfiles
Icon=system-file-manager
Terminal=false
Type=Application
Categories=Utility;System;FileTools;" | sudo tee /usr/share/applications/fyrfiles.desktop > /dev/null

echo "Updating desktop database..."
sudo update-desktop-database || true

echo "Setting up fyrfiles as default file picker for Sway..."

sudo bash -c "cat > /usr/local/bin/fyr_files_picker <<EOF
#!/bin/bash
out=\"\\\$5\"
/usr/local/bin/fyrfiles --picker > \"\\\$out\"
if [ ! -s \"\\\$out\" ]; then
    exit 1
fi
exit 0
EOF"
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

echo "Installation complete!"
echo "Please ensure xdg-desktop-portal-termfilechooser is installed!"
echo "You can now run fyrfiles from your application menu or by typing 'fyrfiles' in the terminal."

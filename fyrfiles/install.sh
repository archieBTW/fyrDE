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
if [ -f "/opt/fyrfiles/fyrfiles" ]; then
    sudo ln -sf /opt/fyrfiles/fyrfiles /usr/local/bin/fyrfiles
elif [ -f "/opt/fyrfiles/fyr_files" ]; then
    sudo ln -sf /opt/fyrfiles/fyr_files /usr/local/bin/fyrfiles
fi
sudo ln -sf /usr/local/bin/fyrfiles /usr/local/bin/fyr_files 2>/dev/null || true

# Create a desktop entry
if [ -f "./assets/icons/folderfile.png" ]; then
    sudo mkdir -p /usr/share/icons/hicolor/512x512/apps
    sudo cp ./assets/icons/folderfile.png /usr/share/icons/hicolor/512x512/apps/fyrfiles.png
fi

echo "[Desktop Entry]
Name=fyrFiles
Comment=A modern, custom file manager
Exec=/usr/local/bin/fyrfiles
Icon=fyrfiles
Terminal=false
Type=Application
Categories=Utility;System;FileTools;" | sudo tee /usr/share/applications/fyrfiles.desktop > /dev/null

echo "Updating desktop database..."
sudo update-desktop-database || true

echo "Setting up fyrfiles as default file picker for Sway..."

sudo bash -c "cat > /usr/local/bin/fyr_files_picker <<EOF
#!/bin/bash
multiple=\"\\\$1\"
directory=\"\\\$2\"
save=\"\\\$3\"
path=\"\\\$4\"
out=\"\\\$5\"
/usr/local/bin/fyrfiles --picker \"\\\$path\" > \"\\\$out\"
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

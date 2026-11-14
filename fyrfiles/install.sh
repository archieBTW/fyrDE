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
Exec=/usr/local/bin/fyrfiles %U
Icon=fyrfiles
Terminal=false
Type=Application
MimeType=inode/directory;
Categories=Utility;System;FileTools;" | sudo tee /usr/share/applications/fyrfiles.desktop > /dev/null

echo "Updating desktop database..."
sudo update-desktop-database || true

echo "Setting up fyrfiles as default file picker for Sway..."

sudo tee /usr/local/bin/fyr_files_picker > /dev/null <<'EOF'
#!/bin/bash
multiple="$1"
directory="$2"
save="$3"
path="$4"
out="$5"

fyrfiles_bin=""
for candidate in "$HOME/.local/bin/fyrfiles" "$HOME/.local/share/fyrDE/fyrfiles/fyrfiles" "/usr/local/bin/fyrfiles" "/usr/bin/fyrfiles" "/opt/fyrfiles/fyrfiles"; do
    if [ -x "$candidate" ]; then
        fyrfiles_bin="$candidate"
        break
    fi
done
if [ -z "$fyrfiles_bin" ]; then
    fyrfiles_bin="$(command -v fyrfiles 2>/dev/null)"
fi

cmd_args=("--picker")
if [ "$multiple" = "1" ]; then
    cmd_args+=("--multiple")
fi
if [ "$directory" = "1" ]; then
    cmd_args+=("--directory")
fi
if [ "$save" = "1" ]; then
    cmd_args+=("--save")
fi
cmd_args+=("$path")

"$fyrfiles_bin" "${cmd_args[@]}" > "$out"

if [ "$save" = "1" ] && [ -f "$path" ] && grep -q "xdg-desktop-portal-termfilechooser" "$path" 2>/dev/null; then
    rm -f "$path"
fi

if [ ! -s "$out" ]; then
    exit 1
fi

if [ "$save" = "1" ]; then
    chosen="$(head -n 1 "$out")"
    if [ -d "$chosen" ] && [ -n "$path" ]; then
        printf "%s/%s\n" "${chosen%/}" "$(basename "$path")" > "$out"
    fi
fi

exit 0
EOF
sudo chmod +x /usr/local/bin/fyr_files_picker
mkdir -p ~/.local/bin
cp /usr/local/bin/fyr_files_picker ~/.local/bin/fyr_files_picker 2>/dev/null || true
chmod +x ~/.local/bin/fyr_files_picker 2>/dev/null || true

mkdir -p ~/.config/xdg-desktop-portal-termfilechooser
cat > ~/.config/xdg-desktop-portal-termfilechooser/config <<EOF
[filechooser]
cmd=$HOME/.local/bin/fyr_files_picker
create_help_file=0
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

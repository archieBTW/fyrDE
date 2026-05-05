#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root (use sudo)"
  exit 1
fi

# ==========================================
# CONFIGURATION
# Adjust these variables to match your files
# ==========================================
APP_NAME="FyrDAW"
APP_EXEC="fyrdaw"  # Change this to the exact name of your Linux executable
ICON_NAME="icon.png"     # Change this to the exact name of your icon file
OPT_DIR="/opt/fyrdaw"
DESKTOP_FILE="/usr/share/applications/fyrdaw.desktop"

# Check if the executable and icon exist in the current directory
if [ ! -f "$APP_EXEC" ]; then
    echo "Error: Executable '$APP_EXEC' not found in the current directory."
    exit 1
fi

if [ ! -f "$ICON_NAME" ]; then
    echo "Error: Icon '$ICON_NAME' not found in the current directory."
    exit 1
fi

# ==========================================
# DEPENDENCY INSTALLATION
# ==========================================
echo "Detecting package manager and installing dependencies..."

if command -v apt &> /dev/null; then
    echo "Detected Ubuntu/Debian (APT)..."
    apt update
    apt install -y libasound2 ffmpeg fmedia zenity libgtk-3-0

elif command -v dnf &> /dev/null; then
    echo "Detected Fedora (DNF)..."
    # Note: fmedia might require rpmfusion or manual compilation on Fedora depending on the version
    dnf install -y alsa-lib ffmpeg fmedia zenity gtk3

elif command -v pacman &> /dev/null; then
    echo "Detected Arch Linux (Pacman)..."
    pacman -Syu --noconfirm alsa-lib ffmpeg zenity gtk3
    
    # fmedia is typically housed in the Arch User Repository (AUR) rather than the main repos
    if ! command -v fmedia &> /dev/null; then
        echo "-----------------------------------------------------------------"
        echo "NOTE: 'fmedia' is required for recording but isn't in Arch's core repos."
        echo "Please install it manually using an AUR helper after this script finishes."
        echo "Example: yay -S fmedia"
        echo "-----------------------------------------------------------------"
    fi
else
    echo "Unsupported package manager. Please install ALSA, FFmpeg, fmedia, and Zenity manually."
fi

# ==========================================
# INSTALLATION
# ==========================================
echo "Copying files to $OPT_DIR..."
mkdir -p "$OPT_DIR"

# Copy the executable and icon
cp "$APP_EXEC" "$OPT_DIR/"
cp "$ICON_NAME" "$OPT_DIR/"

# Copy the required Flutter dependency directories
cp -r lib/ "$OPT_DIR/"
cp -r data/ "$OPT_DIR/"

# Ensure the binary is executable
chmod +x "$OPT_DIR/$APP_EXEC"

echo "Creating desktop entry..."
cat <<EOF > "$DESKTOP_FILE"
[Desktop Entry]
Name=$APP_NAME
Exec=$OPT_DIR/$APP_EXEC
Icon=$OPT_DIR/$ICON_NAME
Type=Application
Categories=AudioVideo;AudioEditing;
Terminal=false
Comment=A Flutter-based Digital Audio Workstation
EOF

chmod 644 "$DESKTOP_FILE"

echo "Updating desktop database..."
update-desktop-database /usr/share/applications || true

echo "Installation complete! You should now be able to find $APP_NAME in your application launcher."

#!/bin/bash

# Exit on error
set -e

echo "🔨 Building FyrSettings..."
flutter build linux

echo "📦 Installing to /opt/fyrsettings..."
sudo rm -rf /opt/fyrsettings
sudo mkdir -p /opt/fyrsettings
sudo cp -r build/linux/x64/release/bundle/* /opt/fyrsettings/

echo "🔑 Setting permissions..."
sudo chmod +x /opt/fyrsettings/fyrsettings

echo "📝 Creating desktop entry..."
cat <<EOF | sudo tee /usr/share/applications/fyrsettings.desktop > /dev/null
[Desktop Entry]
Version=1.0
Name=Fyr Settings
Comment=System Settings for Fyr Stack
Exec=/opt/fyrsettings/fyrsettings
Icon=preferences-system
Terminal=false
Type=Application
Categories=Settings;System;HardwareSettings;
EOF

echo "✅ Installation complete! You can now find Fyr Settings in your app launcher."

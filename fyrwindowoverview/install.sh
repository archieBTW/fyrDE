#!/bin/bash

# Build the flutter linux application
echo "Building Fyrwindowoverview..."
flutter build linux --release

# Ensure destination directory exists
echo "Creating /opt/fyrwindowoverview directory..."
sudo mkdir -p /opt/fyrwindowoverview

# Copy files
echo "Installing to /opt/fyrwindowoverview..."
sudo cp -r build/linux/x64/release/bundle/* /opt/fyrwindowoverview/

echo "Installation complete!"
echo "Configuration is handled via the main Sway config and overview_toggle.sh."

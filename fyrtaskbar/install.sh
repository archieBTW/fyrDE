#!/bin/bash

# Build the flutter linux application
echo "Building FyrTaskbar..."
flutter build linux --release

# Ensure destination directory exists
echo "Creating /opt/fyrtaskbar directory..."
sudo mkdir -p /opt/fyrtaskbar

# Copy files
echo "Installing to /opt/fyrtaskbar..."
sudo cp -r build/linux/x64/release/bundle/* /opt/fyrtaskbar/

echo "Installation complete!"
echo "Add 'include /path/to/fyrtaskbar/sway_fyrtaskbar.config' to your Sway config."

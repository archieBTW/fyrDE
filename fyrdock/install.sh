#!/bin/bash

# Build the flutter linux application
echo "Building FyrDock..."
flutter build linux --release

# Ensure destination directory exists
echo "Creating /opt/fyrdock directory..."
sudo mkdir -p /opt/fyrdock

# Copy files
echo "Installing to /opt/fyrdock..."
sudo cp -r build/linux/x64/release/bundle/* /opt/fyrdock/

echo "Installation complete!"
echo "Add 'include /path/to/fyrdock/sway_fyrdock.config' to your Sway config."

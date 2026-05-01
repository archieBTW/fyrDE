#!/bin/bash

# Build the flutter linux application
echo "Building Fyroverview..."
flutter build linux --release

# Ensure destination directory exists
echo "Creating /opt/fyroverview directory..."
sudo mkdir -p /opt/fyroverview

# Copy files
echo "Installing to /opt/fyroverview..."
sudo cp -r build/linux/x64/release/bundle/* /opt/fyroverview/

echo "Installation complete!"
echo "Add 'include /path/to/fyroverview/sway_fyroverview.config' to your Sway config."

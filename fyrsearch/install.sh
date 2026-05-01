#!/bin/bash

# Build the flutter linux application
echo "Building FyrSearch..."
flutter build linux --release

# Ensure destination directory exists
echo "Creating /opt/fyrsearch directory..."
sudo mkdir -p /opt/fyrsearch

# Copy files
echo "Installing to /opt/fyrtaskbar..."
sudo cp -r build/linux/x64/release/bundle/* /opt/fyrsearch/

echo "Installation complete!"
echo "Add 'include /path/to/fyrsearch/sway_fyrsearch.config' to your Sway config."

#!/bin/bash

# Build the flutter linux application
echo "Building FyrEmoji..."
flutter build linux --release

# Ensure destination directory exists
echo "Creating /opt/fyremoji directory..."
sudo mkdir -p /opt/fyremoji

# Copy files
echo "Installing to /opt/fyremoji..."
sudo cp -r build/linux/x64/release/bundle/* /opt/fyremoji/

echo "Installation complete!"

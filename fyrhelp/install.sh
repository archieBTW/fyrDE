#!/bin/bash

# Build the flutter linux application
echo "Building FyrHelp..."
flutter build linux --release

# Ensure destination directory exists
echo "Creating /opt/fyrhelp directory..."
sudo mkdir -p /opt/fyrhelp

# Copy files
echo "Installing to /opt/fyrhelp..."
sudo cp -r build/linux/x64/release/bundle/* /opt/fyrhelp/

echo "Installation complete!"

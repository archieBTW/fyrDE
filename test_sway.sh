#!/bin/bash

# Remove LD_PRELOAD from current environment just in case it's set
unset LD_PRELOAD

cd /home/archie/Code/de/swayfx

# Build and install swayfx
echo "Building swayfx..."
ninja -C build

echo "Installing swayfx (requires sudo)..."
sudo ninja -C build install

echo "Done! You can now restart sway."

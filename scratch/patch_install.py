import sys

with open('/home/archie/Code/fyrDE/install.sh', 'r') as f:
    lines = f.readlines()

new_lines = []
for line in lines:
    new_lines.append(line)
    if 'xdg-mime default fyrphotos.desktop image/jpeg image/png image/gif image/webp image/x-ms-bmp || true' in line:
        # We found the line before the ;; for fyrphotos
        pass
    if '        "fyrphotos":' in line:
        # Start of fyrphotos block
        pass

# Actually let's just find the closing ;; of fyrphotos and add fyrcamera after it
found_fyrphotos = False
inserted = False
final_lines = []
for i in range(len(lines)):
    final_lines.append(lines[i])
    if '        "fyrphotos":' in lines[i]:
        found_fyrphotos = True
    if found_fyrphotos and '            ;;' in lines[i] and not inserted:
        final_lines.append('        "fyrcamera":\n')
        final_lines.append('            sudo ln -sf /opt/fyrcamera/fyrcamera /usr/local/bin/fyrcamera\n')
        final_lines.append('            sudo tee /usr/share/applications/fyrcamera.desktop > /dev/null <<\'EOF\'\n')
        final_lines.append('[Desktop Entry]\n')
        final_lines.append('Name=FyrCamera\n')
        final_lines.append('Comment=Camera app for pictures and video\n')
        final_lines.append('Exec=/usr/local/bin/fyrcamera\n')
        final_lines.append('Icon=camera-photo\n')
        final_lines.append('Terminal=false\n')
        final_lines.append('Type=Application\n')
        final_lines.append('Categories=AudioVideo;Video;\n')
        final_lines.append('EOF\n')
        final_lines.append('            ;;\n')
        inserted = True

with open('/home/archie/Code/fyrDE/install.sh', 'w') as f:
    f.writelines(final_lines)

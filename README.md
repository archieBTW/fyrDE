# fyr (frick your RAM)

![Desktop](screenshots/desktop.png)

This repository contains the core configuration and setup scripts for the fyr (frick your RAM) Desktop Environment (fyrDE).

## How it Works

fyrDE uses a custom fork of Sway (SwayFX) to provide a Wayland compositor. On top of this compositor, it runs a suite of custom-built **Flutter applications** to provide the core desktop experience:



## Installation

### 1. Clone the Repository

```bash
git clone https://github.com/archieBTW/fyrDE.git
cd fyrDE
```

### 2. Run the Install Script

The updated `install.sh` is a powerful tool for managing your fyrDE installation. It handles dependencies, builds all Flutter apps, and configures the system.

```bash
chmod +x install.sh
./install.sh [options]
```

#### Installer Options:
| Flag | Description |
|---|---|
| `-F` | **Force full installation** (Default if no flags provided). |
| `-a <app>` | Rebuild and reinstall a **specific application** (e.g., `./install.sh -a fyrtaskbar`, `./install.sh -a fyrgraphics`, `./install.sh -a devign`). |
| `-s` | Reinstall **Sway configuration** and scripts. |
| `-l` | Reinstall **SDDM theme** and configuration. |
| `-t` | Reinstall **GTK and icon themes**. |
| `-d` | Install **system dependencies** only (uses `fyrpak` by default; `install.yay.sh.bak` kept as a `yay` fallback). |
| `-p` | Build and install **fyrpak** (native Go package manager & AUR helper). |
| `-f` | Install **fyrfetch** tool and add to PATH & shell config. |
| `-z` | Setup **ZSH and Oh-My-Zsh** environment. |
| `-h` | Show the help message. |

> **Note:** The script will prompt you for your `sudo` password to install system packages.

#### Standalone Suite Installers & `.deb` Packaging:
You can also install individual app suites (Creative, Office, or Dev) on Ubuntu/Debian, Arch, or Fedora without installing the full desktop environment:

```bash
chmod +x install_suite.sh
./install_suite.sh --suite creative          # Sound Booth (fyrdaw), fyrGraphics, fyrDirector
./install_suite.sh --suite office            # fyrDocs, fyrSheets, fyrSlides, fyrPDF
./install_suite.sh --suite dev               # FyrCode, FyrApi, fyrDB, fyrPods
./install_suite.sh --app fyrjournal          # fyrJournal (Linux & Arch/Ubuntu on WSL)
./install_suite.sh --suite creative --deb    # Also package .deb installers into ./dist/deb/
```

For an Ubuntu-specific Creative Suite installer, `./install_cs_ubuntu.sh` is also available.

---

## Keyboard Shortcuts

The main modifier key (`$mod`) is the **Super/Windows** key.

| Action | Shortcut |
|---|---|
| **System** | |
| Lock Screen | `Super + L` |
| Close Window | `Super + Q` |
| Open Application Launcher (**fyrSearch**) | `Super + Space` |
| Toggle Overview (**fyrOverview**) | `Super + Tab` |
| Show Workspaces Overview (**fyrWindowOverview**) | `Super + W` |
| Open Clipboard History (**fyrClipboard**) | `Alt + V` |
| Show Cheatsheet (**fyrHelp**) | `Super + Ctrl` |
| Open Emoji Picker (**fyrEmoji**) | `Super + .` |
| Open Task Manager (**fyrMonitor**) | `Ctrl + Shift + Esc` |
| Open Terminal (**fyrTerm**) | `Super + T` |
| Open File Manager (**fyrFiles**) | `Super + F` |
| Toggle Floating / Tiling Mode | `Super + M` |
| Take a Screenshot (Full Screen) | `Print Screen` |
| Take a Screenshot (Select Region) | `Shift + Print Screen` |
| Take a Screenshot (Focused Window) | `Alt + Print Screen` |
| Toggle Screen Recording | `Super + Print Screen` |
| **Window Management** | |
| Change Focus | `Super + Arrow Keys` |
| Resize Window | `Super + Shift + Arrow Keys` |
| Split Horizontally (Tiling Mode) | `Super + H` |
| Split Vertically (Tiling Mode) | `Super + V` |
| Focus Next/Prev Window | `Alt + Tab` / `Alt + Shift + Tab` |
| **Workspaces** | |
| Switch to Workspace 1-10 | `Super + 1-0` |
| Move Window to Workspace 1-10 | `Super + Shift + 1-0` |
| **Touchpad Gestures** | |
| Switch Workspace Prev/Next | `Swipe 3 Fingers Left/Right` |
| Toggle Overview | `Swipe 3 Fingers Down/Up` |
| **Media & Brightness** | |
| Volume Up / Down | `Volume Keys` |
| Mute Audio / Mic | `Mute / Mic Mute Keys` |
| Brightness Up / Down | `Brightness Keys` |

---

## Customization

After installation, you can customize your experience by editing `~/.config/sway/config`. To change your wallpaper, update the background line:
```text
output * bg /path/to/your/wallpaper.jpg fill
```

## Launching

Start the desktop environment from your TTY:
```bash
sway
```
---

### Core Desktop Components
- **fyrTaskbar**: Top panel with desktop layer, notifications, screenshot toasts, system tray, clock, media controls, and frosted Quick Settings.
  ![Taskbar 1](screenshots/taskbar1.png)
  ![Taskbar 2](screenshots/taskbar2.png)
  ![Taskbar 3](screenshots/taskbar3.png)
- **fyrDock**: Translucent dock for launching apps and managing open windows.
- **fyrSearch**: Spotlight-like application launcher, inline calculator, and search tool.
  ![Search](screenshots/search.png)
- **fyrOverview & fyrWindowOverview**: Exposé-like window and workspace overview.
  ![Overview](screenshots/overview.png)
- **fyrClipboard**: Frosted-glass clipboard history manager with text & image history, pinning, filtering, and instant search (`Alt + V`).
- **fyrHelp**: A quick-access keyboard shortcut cheatsheet (`Super + Ctrl`).
  ![Help](screenshots/fyrhelp.png)
- **fyrEmoji**: An integrated emoji picker (`Super + .`).
  ![Emoji](screenshots/fyremoji.png)

### Window Management
![Tiling](screenshots/tiling.png)
![Floating](screenshots/floating.png)

### System Applications
- **Terminal** (`fyrTerm`): A custom Flutter terminal emulator.
  ![Terminal](screenshots/terminal.png)
- **fyrFiles**: A modern, custom file manager.
  ![Files](screenshots/files.png)
- **fyrStore**: A software center for managing applications.
  ![Store](screenshots/store.png)
- **Settings** (`fyrSettings`): Control center for system configurations.
  ![Settings](screenshots/settings.png)
- **fyrVM** (`fyrVirt`): Virtual Machine Manager.
  ![Virtual Machine](screenshots/fyrvirt.png)
- **fyrAV**: Anti-Virus and system security suite.
  ![AV](screenshots/av.png)
- **fyrConnect** (`fyrPhone`): Mobile device manager and integration tool.
  ![Phone](screenshots/phone.png)
- **Task Manager** (`fyrMonitor`): Windows-style open-apps, processes, and
  performance monitor (CPU, memory & swap, disk and network charts).
  ![Monitor](screenshots/fyrmonitor.png)
- **fyrDisks**: Disk, partition, LUKS encryption, and USB ISO flasher utility.
  ![Disks](screenshots/fyrdisks.png)
- **fyrpak**: Native Go package manager, AUR helper (`yay`-compatible `-Syu`, `-S`, `-Ss`, `-Si`, `-R`, `-Q`, `-Yc`, `-Ps`, `-G`), and built-in fyrDE updater (`fyrpak fyr update`, `fyrpak fyr status`, `fyrpak fyr doctor`, `fyrpak fyr clean`).
- **fyrfetch**: A custom system information tool (like neofetch).

### Productivity & Media
- **Goose** (`fyrBrowser`): A CEF-based web browser designed for fyrDE.
  ![Goose](screenshots/goose.png)
- **fyrCode**: Agentic code editor and IDE with integrated AI agent, inline diffs, and LSP support.
  ![Code](screenshots/code.png)
- **fyrAPI**: REST & HTTP API client and request builder.
  ![API](screenshots/fyrapi.png)
- **fyrText**: Advanced text and document editor.
  ![Text](screenshots/text.png)
- **Sound Booth** (`fyrDaw`): Digital Audio Workstation.
  ![DAW](screenshots/daw.png)
- **Music** (`fyrMusic`): Music library and player.
  ![Music](screenshots/music.png)
- **Watchbox** (`fyrVideo`): Media player for videos.
  ![Video](screenshots/seinfeld.png)
- **Photos** (`fyrPhotos`): Photo library and viewer.
  ![Photos](screenshots/fyrphotos.png)
- **Camera** (`fyrCamera`): Camera and video recording application.
  ![Camera](screenshots/camera.png)
- **fyrTorrent**: BitTorrent and magnet link client.
  ![Torrent](screenshots/fyrtorrent.png)
- **fyrGraphics**: Layered raster & vector image editor with **Simple** and **Advanced Pro** workspace modes (Curves, Develop adjustments, Photo Looks, Symmetry drawing, Color Harmonies, Alpha Lock, Clipping Masks, and Stamp Visible).
  ![Graphics](screenshots/fyrgraphics.png)
- **devign**: Vector UI/UX design & interactive prototyping studio with multi-page frames, Auto-Layout flexbox containers, reusable Master Components & Instances, Bezier pen paths, color tokens, live Prototype Player, and Flutter/CSS/SVG/PNG code & asset export.
- **fyrEmu**: Multi-platform retro game emulator.
  ![Emulator](screenshots/fyremu.png)
- **fyrDirector**: Non-linear video editor.
  ![Director](screenshots/fyrdirector.png)
- **fyrDocs** (`fyrOffice`): OpenDocument (`.odt`) and Word (`.docx`) rich word processor.
  ![Docs](screenshots/fyrdocs.png)
- **fyrSheets** (`fyrOffice`): OpenDocument (`.ods`), Excel (`.xlsx`), and CSV spreadsheet studio.
  ![Sheets](screenshots/fyrsheets.png)
- **fyrSlides** (`fyrOffice`): OpenDocument (`.odp`) and PowerPoint (`.pptx`) presentation studio.
  ![Slides](screenshots/fyrslides.png)
- **fyrPDF** (`fyrOffice`): Fast native PDF reader with thumbnails, table of contents outline, bookmarks, in-document text search, rotation, dark reading mode, and drag-and-drop opening.
- **fyrDB**: Universal database manager, SQL IDE, and ER diagram studio with guided connection setup wizard (SQLite, PostgreSQL, MySQL/MariaDB, DuckDB, Redis).
  ![DB](screenshots/fyrdb.png)
- **fyrPods**: Container, pod, image, and compose stack manager (Podman / Docker).
  ![Pods](screenshots/fyrpods.png)
- **Calendar** (`fyrCalendar`): Modern calendar with event management.
  ![Calendar](screenshots/calendar.png)
- **Clock** (`fyrClock`): Sleek clock with World Clock, Alarm, Stopwatch, and Timer.
  ![Clock](screenshots/clock.png)
- **Calculator** (`fyrCalculator`): High-contrast, modern calculator.
  ![Calculator](screenshots/calc.png)
- **Journal** (`fyrJournal`): Personal journal and note-taking application (native Linux & WSLg compatible).
  ![Journal](screenshots/journal.png)

### Companion Mobile Launcher
- **fyrAndroid** (`fyrandroid/`): Lightweight native Kotlin Android launcher bringing the FyrDE aesthetic to mobile — paged `4×5` squircle home grid with frosted dock, swipe-up `fyrSearch` app drawer with immediate autofocus & inline calculator, swipe-down & optional top-edge Fyr Quick Settings sheet, and live Light/Dark mode + Fyr accent color customization.

---



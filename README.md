# fyr (frick your RAM) Desktop Environment (fyrDE)

![Idle](screenshots/idle.png)
![Dark Mode](screenshots/dark%20mode.png)
![Light Mode](screenshots/light%20mode.png)
![Menu](screenshots/menu.png)
![Quick Settings](screenshots/quick%20settings.png)
![Calendar](screenshots/calender.png)
![Search](screenshots/search.png)
![Overview](screenshots/overview.png)
![Floating](screenshots/floating.png)
![Help](screenshots/help.png)
![Emoji](screenshots/emoji.png)

This repository contains the core configuration and setup scripts for the fyr (frick your RAM) Desktop Environment (fyrDE).

## How it Works

fyrDE uses a custom fork of Sway (SwayFX) to provide a Wayland compositor. On top of this compositor, it runs a suite of custom-built **Flutter applications** to provide the core desktop experience:

### Core Desktop Components
- **fyrTaskbar**: Top panel with system tray, clock, and quick settings.
- **fyrDock**: macOS-like dock for launching apps and managing open windows.
- **fyrSearch**: Spotlight-like application launcher and search tool.
- **fyrOverview**: Exposé-like window and workspace overview.
- **fyrWindowOverview**: Detailed window management and workspace visualization.
- **fyrHelp**: A quick-access keyboard shortcut cheatsheet.
- **fyrEmoji**: An integrated emoji picker.

### System Applications
- **Terminal** (`fyrTerm`): A custom Flutter terminal emulator.
- **fyrFiles**: A modern, custom file manager.
- **fyrStore**: A software center for managing applications.
- **Settings** (`fyrSettings`): Control center for system configurations.
- **fyrVM** (`fyrVirt`): Virtual Machine Manager.
- **fyrAV**: Anti-Virus and system security suite.
- **fyrConnect** (`fyrPhone`): Mobile device manager and integration tool.
- **fyr_fetch**: A custom system information tool (like neofetch).

### Productivity & Media
- **Goose** (`fyrBrowser`): A CEF-based web browser designed for fyrDE.
- **fyrCode**: Advanced code editor and IDE.
- **fyrText**: Advanced text and document editor.
- **Sound Booth** (`fyrDaw`): Digital Audio Workstation.
- **Music** (`fyrMusic`): Music library and player.
- **Watchbox** (`fyrVideo`): Media player for videos.
- **Photos** (`fyrPhotos`): Photo library and viewer.
- **Camera** (`fyrCamera`): Camera and video recording application.
- **Calendar** (`fyrCalendar`): Modern calendar with event management.
- **Clock** (`fyrClock`): Sleek clock with World Clock, Alarm, Stopwatch, and Timer.
- **Calculator** (`fyrCalculator`): High-contrast, modern calculator.
- **Journal** (`fyrJournal`): Personal journal and note-taking application.

---

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
| `-a <app>` | Rebuild and reinstall a **specific application** (e.g., `./install.sh -a fyrTaskbar`). |
| `-s` | Reinstall **Sway configuration** and scripts. |
| `-l` | Reinstall **SDDM theme** and configuration. |
| `-t` | Reinstall **GTK and icon themes**. |
| `-d` | Install **system dependencies** only. |
| `-f` | Install **fyr_fetch** tool and add to shell config. |
| `-z` | Setup **ZSH and Oh-My-Zsh** environment. |
| `-h` | Show the help message. |

> **Note:** The script will prompt you for your `sudo` password to install system packages.

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
| Show Workspaces Overview | `Super + W` |
| Show Cheatsheet (**fyrHelp**) | `Super + Ctrl` |
| Open Emoji Picker (**fyrEmoji**) | `Super + .` |
| Open Terminal (**fyrTerm**) | `Super + T` |
| Open File Manager (**fyrFiles**) | `Super + F` |
| Toggle Floating Mode | `Super + M` |
| Take a Screenshot | `Print Screen` |
| Toggle Screen Recording | `Super + Print Screen` |
| **Window Management** | |
| Change Focus | `Super + Arrow Keys` |
| Resize Window | `Super + Shift + Arrow Keys` |
| Split Horizontally | `Super + H` |
| Split Vertically | `Super + V` |
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

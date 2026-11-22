# fyrpak

`fyrpak` is a native Go package manager, AUR helper, and **fyrDE** updater built with zero external Go dependencies.

## Features
- **Drop-in `yay` & `pacman` workflow**:
  - `fyrpak` — full system + AUR upgrade (`-Syu`)
  - `fyrpak <query>` — interactive bottom-up numbered search & install across Arch repos + AUR
  - `fyrpak -S <pkgs>` — recursive dependency resolution across official repos + AUR with topological build ordering (`--needed`, `--noconfirm`, `--asdeps`, `--cleanbuild`, `--devel`)
  - `fyrpak -Ss`, `-Si`, `-Sc`/`-Scc`, `-R*`, `-Q*`, `-Qua`, `-Yc`, `-Ps`, `-G`, `-U`, `-F`, `-D`, `-T`
- **Built-in fyrDE Management**:
  - `fyrpak fyr status` — git branch/commit, SwayFX status, installed app count
  - `fyrpak fyr list` — list every fyrDE app and `/opt` install timestamp
  - `fyrpak fyr update [app...]` / `fyrpak -Syuf` — update specific fyrDE apps, `swayfx`, or all installed fyrDE apps
  - `fyrpak fyr doctor` — audit binaries, running shell daemons, PATH, orphans, and caches
  - `fyrpak fyr clean` — reclaim disk space from Flutter `build/linux` directories and `~/.cache/fyrpak`

## Build & Install
```bash
cd fyrpak
go build -trimpath -ldflags="-s -w" -o ~/.local/bin/fyrpak .
```

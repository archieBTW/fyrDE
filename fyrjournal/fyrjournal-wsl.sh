#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

FORCE_SOFTWARE=0
APP_ARGS=()

for arg in "$@"; do
  case "$arg" in
    --software)
      FORCE_SOFTWARE=1
      ;;
    -h|--help)
      cat <<'EOF'
Usage: fyrjournal-wsl.sh [--software] [fyrjournal args...]

Launch fyrjournal cleanly inside WSL / Arch on WSL (WSLg).

Options:
  --software   Force Mesa software OpenGL rendering (LIBGL_ALWAYS_SOFTWARE=1)
  -h, --help   Show this help message
EOF
      exit 0
      ;;
    *)
      APP_ARGS+=("$arg")
      ;;
  esac
done

# Verify WSLg display sockets/variables are available.
if [[ -z "${WAYLAND_DISPLAY:-}" && -z "${DISPLAY:-}" ]]; then
  echo "Error: Neither WAYLAND_DISPLAY nor DISPLAY is set." >&2
  if [[ -d /mnt/wslg ]]; then
    echo "WSLg appears mounted at /mnt/wslg, but display env vars are unset." >&2
    echo "Try restarting WSL from PowerShell: wsl --shutdown" >&2
  else
    echo "WSLg does not appear enabled in this WSL instance." >&2
    echo "Ensure Windows 11 (or updated WSL) is running, run 'wsl --update'," >&2
    echo "and confirm 'guiApplications=true' in %USERPROFILE%\\.wslconfig." >&2
  fi
  exit 1
fi

# Allow GTK to negotiate Wayland first and fall back to X11 without breaking on
# forced/unsupported backends.
export GDK_BACKEND="wayland,x11"

# Fall back to software OpenGL when GPU render node is missing/unreadable or
# when explicitly requested via --software.
if [[ "$FORCE_SOFTWARE" -eq 1 ]] || [[ ! -r /dev/dri/renderD128 || ! -w /dev/dri/renderD128 ]]; then
  export LIBGL_ALWAYS_SOFTWARE=1
  if [[ "$FORCE_SOFTWARE" -eq 1 ]]; then
    echo "[fyrjournal-wsl] Software rendering enabled (--software)." >&2
  else
    echo "[fyrjournal-wsl] /dev/dri/renderD128 is not accessible; enabling LIBGL_ALWAYS_SOFTWARE=1." >&2
  fi
fi

# Locate the compiled fyrjournal executable.
BIN=""
CANDIDATES=(
  "$SCRIPT_DIR/build/linux/x64/release/bundle/fyrjournal"
  "$SCRIPT_DIR/build/linux/x64/debug/bundle/fyrjournal"
  "$SCRIPT_DIR/build/linux/arm64/release/bundle/fyrjournal"
  "$SCRIPT_DIR/build/linux/arm64/debug/bundle/fyrjournal"
  "/usr/local/bin/fyrjournal"
)

for candidate in "${CANDIDATES[@]}"; do
  if [[ -x "$candidate" ]]; then
    BIN="$candidate"
    break
  fi
done

if [[ -z "$BIN" ]] && command -v fyrjournal >/dev/null 2>&1; then
  BIN="$(command -v fyrjournal)"
fi

if [[ -z "$BIN" ]]; then
  echo "Error: Could not find a built 'fyrjournal' binary." >&2
  echo "Build it first from $SCRIPT_DIR with:" >&2
  echo "  flutter build linux --release" >&2
  exit 1
fi

exec "$BIN" "${APP_ARGS[@]}"

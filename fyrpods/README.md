# fyrPods

**fyrPods** is the native Container, Pod, OCI Image, Persistent Volume & Compose Stack Manager for **fyrDE**, supporting both **Podman (rootless)** and **Docker** engines.

## Features
- **Multi-Runtime Engine**: Automatic detection and switching between rootless Podman (`unix:///run/user/1000/podman/podman.sock`) and Docker (`unix:///var/run/docker.sock`), with full JSON CLI parsing and a stateful fallback simulation engine.
- **Container Lifecycle & Live Telemetry**: Start, stop, pause, unpause, restart, remove, and create containers with live CPU & Memory area sparklines, port forwarding pills, and volume mount inspection.
- **Interactive Container Inspector**:
  - **Summary & Live Charts**: Real-time CPU % and RSS Memory area charts, port bindings, volume mounts, and environment variables.
  - **Streaming Logs**: Filterable container stdout/stderr logs (`ALL`, `INFO`, `WARN`, `ERROR`) with live search.
  - **Interactive Exec Terminal**: Built-in container shell (`podman exec` / `docker exec`) with quick inspection presets (`ps aux`, `env`, `free -m`, `df -h`, `ip addr`, `uname -a`).
  - **Kubernetes Pod & Compose YAML Generator**: One-click export of any container or pod group to `v1` Kubernetes `Pod` YAML (`podman kube generate`) or `docker-compose.yml`.
- **Pods & Stacks Management**: Group containers into shared-namespace Pods, start/stop/restart whole stacks, or deploy directly from Kubernetes YAML (`podman kube play`).
- **OCI Images, Volumes & Netavark Networks**: Pull images from registries, build custom images from a `Containerfile` / `Dockerfile`, manage persistent volumes, and configure bridge/macvlan networks with `aardvark-dns`.

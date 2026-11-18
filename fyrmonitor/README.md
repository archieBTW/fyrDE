# fyrMonitor

A Windows Task Manager style system monitor for **fyrDE**, built with Flutter and
powered entirely by the Linux `/proc` filesystem (no plugins, no native code).

```bash
flutter run -d linux              # run locally
./install.sh -a fyrmonitor        # build + install via the fyrDE installer
```

Launch it from anywhere with **`Ctrl + Shift + Escape`**, or:

```bash
fyrmonitor               # opens on the Open Apps tab
fyrmonitor --performance # opens on the Performance tab
fyrmonitor --processes   # opens on the Processes tab
```

## Tabs

| Tab | Data source | Actions |
|---|---|---|
| **Open Apps** | `swaymsg -t get_tree` + `/proc/[pid]/statm` | Focus (`swaymsg [pid=X] focus`), Close (`swaymsg [pid=X] kill`), Force Kill (`SIGKILL`) |
| **Processes** | `/proc/[pid]/comm`, `statm`, `stat` (+ `status` for the user filter) | Terminate (`SIGTERM`), Kill (`SIGKILL`) |
| **Performance** | `/proc/stat`, `/proc/meminfo`, `/proc/diskstats`, `/proc/net/dev` | — (60 s scrolling area charts) |

## Window chrome

`fyrMonitor` is a compact utility window (**880×600**, minimum **640×430**) and
uses the same left-side traffic lights as the rest of the suite
(`widgets/traffic_lights.dart`: close / minimize / maximize, 12 px circles), with
the tab strip sitting directly under the title bar.

## Design notes

* **Idle cost is near zero.** Each tab polls on its own 1.5 s `Timer`, and only
  the *active* tab runs: switching tabs cancels the outgoing timer and clears its
  counters, so the Processes tab is never scanned while the Performance charts
  are on screen.
* **Only the needed files are parsed.** The Processes sweep reads `comm` first and
  applies the search filter before touching `stat`/`statm`; the Performance tab
  reads exactly four files per tick.
* **Rates, not absolute counters.** CPU %, disk throughput and network throughput
  come from tick/byte deltas. Baselines are discarded on tab re-activation so a
  long pause never produces a spike.
* **Short-lived PIDs are normal.** Every individual `/proc` read is wrapped in a
  `FileSystemException` guard — a process exiting between the directory listing
  and the read simply disappears from that sweep.
* **Charts are hand drawn.** `smooth_area_chart.dart` renders a Catmull-Rom
  spline through a single `CustomPaint`, wrapped in a `RepaintBoundary`; there is
  no charting dependency. The Performance tab lays its four cards out in two
  columns as soon as the window is at least 700 px wide, so the default window
  size shows CPU, memory, disk and network without scrolling.
* **Nothing animates when nothing changes.** The "live" indicator is static on
  purpose: a repeating `AnimationController` kept Flutter scheduling frames
  forever and, measured on this machine, cost ~20% of a core while idle.

### Measured cost

Measured on an 8 core machine with 243 processes (`dart run tool/bench_scan.dart`
plus `/proc/[pid]/stat` deltas of a running release build):

| Scenario | Cost |
|---|---|
| One full `/proc` process sweep | **38 ms** ≈ 2.6% of the 1.5 s budget |
| App open on *Open Apps* (idle) | ~1% of one core |
| App open on *Performance* | ~1% of one core |
| App open on *Processes* | ~13% of one core¹ |

¹ Dominated by repainting a 240-row table at an uncapped frame rate under
`Xvfb` + llvmpipe software rendering. Under SwayFX with vsync the per-frame cost
is bounded by the 60 Hz refresh, and the `/proc` work itself is only the 38 ms
sweep. Hidden tabs cost nothing at all — `test/shell_test.dart` fails if an
inactive tab ever leaves a timer pending.

## Layout

```
lib/
  main.dart                  app shell: title bar, tab strip, IndexedStack
  fyr_theme.dart             re-export of package:fyr_core/fyr_theme.dart
  models/monitor_models.dart plain data holders + unit formatting
  services/
    proc_service.dart        /proc parsing (static, unit-tested) + I/O
    perf_service.dart        delta → per-second rate sampler
    sway_windows.dart        swaymsg get_tree flattening + window actions
  tabs/
    open_apps_tab.dart
    processes_tab.dart
    performance_tab.dart
  widgets/
    fyr_title_bar.dart       shared fyrDE custom title bar (left traffic lights)
    traffic_lights.dart      close / minimize / maximize circles
    fyr_tab_bar.dart         Windows-style tab strip
    smooth_area_chart.dart   CustomPainter area chart
    section_card.dart        performance card / legend / metric
    row_action_button.dart   compact in-row action button
tool/
  bench_scan.dart            measures one /proc sweep (dart run)
```

## Tests

```bash
flutter analyze
flutter test
```

`test/proc_service_test.dart` covers the `/proc` parsers against captured kernel
snippets (including a `comm` containing spaces and a `)`), the delta maths, and a
live sweep. `test/sway_tree_test.dart` covers the `get_tree` flattening rules.

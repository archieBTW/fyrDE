package fyrde

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"

	"fyrpak/internal/builder"
	"fyrpak/internal/pacman"
	"fyrpak/internal/ui"
)

// FindRepoRoot locates the local fyrDE repository directory.
func FindRepoRoot() (string, error) {
	home, _ := os.UserHomeDir()
	candidates := []string{}

	if env := os.Getenv("FYRDE_DIR"); env != "" {
		candidates = append(candidates, env)
	}
	if raw, err := os.ReadFile(filepath.Join(home, ".config", "fyr", "repo_path")); err == nil {
		if p := strings.TrimSpace(string(raw)); p != "" {
			candidates = append(candidates, p)
		}
	}
	if cwd, err := os.Getwd(); err == nil {
		candidates = append(candidates, cwd, filepath.Dir(cwd))
	}
	if exe, err := os.Executable(); err == nil {
		resolved, _ := filepath.EvalSymlinks(exe)
		if resolved != "" {
			candidates = append(candidates, filepath.Dir(resolved), filepath.Dir(filepath.Dir(resolved)))
		}
	}
	candidates = append(candidates,
		filepath.Join(home, "Code", "fyrDE"),
		filepath.Join(home, "Code", "fyrDE.old"),
		filepath.Join(home, "fyrDE"),
	)

	for _, c := range candidates {
		if c == "" {
			continue
		}
		if _, err := os.Stat(filepath.Join(c, "install.sh")); err == nil {
			if _, err2 := os.Stat(filepath.Join(c, "fyrtaskbar")); err2 == nil {
				return c, nil
			}
		}
	}
	return "", fmt.Errorf("could not find fyrDE repository (set FYRDE_DIR or run from inside fyrDE)")
}

// DiscoverApps lists all Flutter app directories inside the fyrDE repository.
func DiscoverApps(repoRoot string) []string {
	entries, err := os.ReadDir(repoRoot)
	if err != nil {
		return nil
	}
	var apps []string
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		name := e.Name()
		if strings.HasPrefix(name, ".") || name == "packages" || name == "swayfx" || name == "fyrandroid" || name == "fyrpak" {
			continue
		}
		if _, err := os.Stat(filepath.Join(repoRoot, name, "pubspec.yaml")); err == nil {
			apps = append(apps, name)
		}
	}
	sort.Strings(apps)
	return apps
}

func ListApps() error {
	root, err := FindRepoRoot()
	if err != nil {
		return err
	}
	apps := DiscoverApps(root)
	ui.Banner(fmt.Sprintf("fyrDE Applications (%d found in %s)", len(apps), root))
	installedCount := 0
	for _, app := range apps {
		binPath := filepath.Join("/opt", app, app)
		status := ui.C(ui.Muted, "not installed")
		if info, err := os.Stat(binPath); err == nil {
			installedCount++
			status = ui.C(ui.Green, fmt.Sprintf("installed (%s)", info.ModTime().Format("2006-01-02 15:04")))
		}
		fmt.Printf("  %-22s %s\n", ui.C(ui.Bold, app), status)
	}
	fmt.Println()
	ui.Success("%d/%d fyrDE Flutter apps installed in /opt", installedCount, len(apps))
	return nil
}

func Status() error {
	root, err := FindRepoRoot()
	if err != nil {
		return err
	}
	ui.Banner("fyrDE Environment Status")
	fmt.Printf("  %-18s %s\n", ui.C(ui.Purple, "Repository:"), root)

	branch, _ := exec.Command("git", "-C", root, "rev-parse", "--abbrev-ref", "HEAD").Output()
	commit, _ := exec.Command("git", "-C", root, "log", "-1", "--format=%h %s").Output()
	dirtyOut, _ := exec.Command("git", "-C", root, "status", "--porcelain").Output()
	fmt.Printf("  %-18s %s\n", ui.C(ui.Purple, "Git Branch:"), strings.TrimSpace(string(branch)))
	fmt.Printf("  %-18s %s\n", ui.C(ui.Purple, "Latest Commit:"), strings.TrimSpace(string(commit)))
	dirtyLines := 0
	for _, l := range strings.Split(strings.TrimSpace(string(dirtyOut)), "\n") {
		if l != "" {
			dirtyLines++
		}
	}
	if dirtyLines > 0 {
		fmt.Printf("  %-18s %s\n", ui.C(ui.Purple, "Working Tree:"), ui.C(ui.Yellow, fmt.Sprintf("%d modified/untracked file(s)", dirtyLines)))
	} else {
		fmt.Printf("  %-18s %s\n", ui.C(ui.Purple, "Working Tree:"), ui.C(ui.Green, "clean"))
	}

	apps := DiscoverApps(root)
	installed := 0
	for _, app := range apps {
		if _, err := os.Stat(filepath.Join("/opt", app, app)); err == nil {
			installed++
		}
	}
	fmt.Printf("  %-18s %d / %d installed\n", ui.C(ui.Purple, "FyrDE Apps:"), installed, len(apps))

	if _, err := os.Stat("/usr/local/bin/sway"); err == nil {
		fmt.Printf("  %-18s %s\n", ui.C(ui.Purple, "SwayFX Binary:"), ui.C(ui.Green, "/usr/local/bin/sway"))
	} else {
		fmt.Printf("  %-18s %s\n", ui.C(ui.Purple, "SwayFX Binary:"), ui.C(ui.Red, "missing"))
	}
	return nil
}

// Update rebuilds and reinstalls requested fyrDE apps (or swayfx / all installed apps).
func Update(targets []string, pullGit bool) error {
	root, err := FindRepoRoot()
	if err != nil {
		return err
	}
	ui.Banner(fmt.Sprintf("Updating fyrDE from %s", root))

	if pullGit {
		dirtyOut, _ := exec.Command("git", "-C", root, "status", "--porcelain").Output()
		if strings.TrimSpace(string(dirtyOut)) == "" {
			ui.Step("Pulling latest fyrDE git changes...")
			cmd := exec.Command("git", "-C", root, "pull", "--ff-only")
			cmd.Stdout = os.Stdout
			cmd.Stderr = os.Stderr
			if err := cmd.Run(); err != nil {
				ui.Warn("git pull skipped/failed: %v", err)
			}
		} else {
			ui.Warn("Working tree has local edits; skipping git pull and building local source.")
		}
	}

	if len(targets) == 0 {
		// Update all currently installed apps in /opt
		for _, app := range DiscoverApps(root) {
			if _, err := os.Stat(filepath.Join("/opt", app, app)); err == nil {
				targets = append(targets, app)
			}
		}
		if len(targets) == 0 {
			return fmt.Errorf("no installed fyrDE apps found in /opt; specify app names or run ./install.sh")
		}
	}

	for _, t := range targets {
		t = strings.TrimSpace(t)
		switch strings.ToLower(t) {
		case "sway", "swayfx":
			ui.Step("Rebuilding & installing SwayFX compositor...")
			cmd := exec.Command("bash", filepath.Join(root, "install.sh"), "-w")
			cmd.Dir = root
			cmd.Stdin = os.Stdin
			cmd.Stdout = os.Stdout
			cmd.Stderr = os.Stderr
			if err := cmd.Run(); err != nil {
				return fmt.Errorf("swayfx update failed: %w", err)
			}
		case "fyrpak":
			ui.Step("Rebuilding & installing fyrpak...")
			cmd := exec.Command("bash", filepath.Join(root, "install.sh"), "-p")
			cmd.Dir = root
			cmd.Stdin = os.Stdin
			cmd.Stdout = os.Stdout
			cmd.Stderr = os.Stderr
			if err := cmd.Run(); err != nil {
				return fmt.Errorf("fyrpak update failed: %w", err)
			}
		case "config", "sway-config":
			ui.Step("Updating Sway config & scripts...")
			cmd := exec.Command("bash", filepath.Join(root, "install.sh"), "-s")
			cmd.Dir = root
			cmd.Stdin = os.Stdin
			cmd.Stdout = os.Stdout
			cmd.Stderr = os.Stderr
			if err := cmd.Run(); err != nil {
				return fmt.Errorf("sway config update failed: %w", err)
			}
		default:
			ui.Step("Rebuilding & reinstalling %s...", ui.C(ui.Purple, t))
			cmd := exec.Command("bash", filepath.Join(root, "install.sh"), "-a", t)
			cmd.Dir = root
			cmd.Stdin = os.Stdin
			cmd.Stdout = os.Stdout
			cmd.Stderr = os.Stderr
			if err := cmd.Run(); err != nil {
				return fmt.Errorf("update of %s failed: %w", t, err)
			}
		}
	}

	ui.Success("fyrDE update complete!")
	return nil
}

// Doctor audits the fyrDE session, daemons, compositor, PATH, and orphan packages.
func Doctor() error {
	ui.Banner("fyrDE System & Environment Doctor")
	ok := func(label, detail string) {
		fmt.Printf("  %s %-22s %s\n", ui.C(ui.Green, "✓"), label, detail)
	}
	warn := func(label, detail string) {
		fmt.Printf("  %s %-22s %s\n", ui.C(ui.Yellow, "!"), label, detail)
	}

	if root, err := FindRepoRoot(); err == nil {
		ok("fyrDE repo", root)
	} else {
		warn("fyrDE repo", err.Error())
	}

	for _, bin := range []string{"sway", "pacman", "makepkg", "git", "go", "flutter", "fyrpak", "fyrfetch"} {
		if path, err := exec.LookPath(bin); err == nil {
			ok(bin, path)
		} else {
			warn(bin, "not found in PATH")
		}
	}

	for _, daemon := range []string{"fyrtaskbar", "fyrdock", "fyrsearch", "fyrclipboard", "fyremoji"} {
		if exec.Command("pgrep", "-x", daemon).Run() == nil {
			ok("daemon: "+daemon, "running")
		} else {
			warn("daemon: "+daemon, "not running")
		}
	}

	orphans := pacman.Orphans()
	if len(orphans) == 0 {
		ok("orphan packages", "none")
	} else {
		warn("orphan packages", fmt.Sprintf("%d unused dependencies (run `fyrpak -Yc` to clean)", len(orphans)))
	}

	cacheSz := builder.DirSize(builder.DefaultCacheDir())
	ok("fyrpak AUR cache", ui.FormatBytes(cacheSz))
	return nil
}

// Clean reclaims disk space by clearing Flutter Linux build caches and fyrpak AUR cache.
func Clean() error {
	ui.Banner("Cleaning fyrDE & fyrpak Build Caches")
	var freed int64

	cacheDir := builder.DefaultCacheDir()
	if sz, err := builder.CleanCache(cacheDir); err == nil && sz > 0 {
		freed += sz
		ui.SubStep("Removed fyrpak AUR cache (%s)", ui.FormatBytes(sz))
	}

	if root, err := FindRepoRoot(); err == nil {
		for _, app := range DiscoverApps(root) {
			buildDir := filepath.Join(root, app, "build", "linux")
			if info, err := os.Stat(buildDir); err == nil && info.IsDir() {
				sz := builder.DirSize(buildDir)
				if err := os.RemoveAll(buildDir); err == nil {
					freed += sz
					ui.SubStep("Cleaned %s/build/linux (%s)", app, ui.FormatBytes(sz))
				}
			}
		}
	}

	ui.Success("Reclaimed %s of disk space", ui.FormatBytes(freed))
	return nil
}

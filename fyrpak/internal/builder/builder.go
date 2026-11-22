package builder

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"fyrpak/internal/aur"
	"fyrpak/internal/ui"
)

type Options struct {
	CacheDir   string
	NoConfirm  bool
	Needed     bool
	CleanBuild bool
	AsDeps     bool
	ReviewDiff bool
}

func DefaultCacheDir() string {
	if xdg := os.Getenv("XDG_CACHE_HOME"); xdg != "" {
		return filepath.Join(xdg, "fyrpak")
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".cache", "fyrpak")
}

// FetchOrUpdate clones or updates an AUR package base into CacheDir/<pkgbase>.
func FetchOrUpdate(pkg aur.Package, opts Options) (string, string, error) {
	base := pkg.PackageBase
	if base == "" {
		base = pkg.Name
	}
	if err := os.MkdirAll(opts.CacheDir, 0o755); err != nil {
		return "", "", err
	}
	dir := filepath.Join(opts.CacheDir, base)
	repoURL := fmt.Sprintf("https://aur.archlinux.org/%s.git", base)

	if opts.CleanBuild {
		_ = os.RemoveAll(dir)
	}

	if _, err := os.Stat(filepath.Join(dir, ".git")); err == nil {
		prevHead := gitRevParse(dir, "HEAD")
		ui.SubStep("Updating cached AUR repo %s", ui.C(ui.Cyan, base))
		if err := runQuiet(dir, "git", "fetch", "--all", "--prune"); err != nil {
			return "", "", fmt.Errorf("git fetch %s failed: %w", base, err)
		}
		if err := runQuiet(dir, "git", "reset", "--hard", "origin/master"); err != nil {
			// Fallback to FETCH_HEAD if branch name differs
			if err2 := runQuiet(dir, "git", "reset", "--hard", "FETCH_HEAD"); err2 != nil {
				return "", "", fmt.Errorf("git reset %s failed: %w", base, err2)
			}
		}
		if opts.CleanBuild {
			_ = runQuiet(dir, "git", "clean", "-fdx")
		}
		return dir, prevHead, nil
	}

	ui.SubStep("Cloning AUR repo %s", ui.C(ui.Cyan, repoURL))
	if err := runQuiet(opts.CacheDir, "git", "clone", "--depth", "1", repoURL, dir); err != nil {
		return "", "", fmt.Errorf("git clone %s failed: %w", base, err)
	}
	return dir, "", nil
}

// CloneToDir downloads an AUR PKGBUILD repo into a destination directory (`fyrpak -G`).
func CloneToDir(pkg aur.Package, destParent string) (string, error) {
	base := pkg.PackageBase
	if base == "" {
		base = pkg.Name
	}
	dest := filepath.Join(destParent, base)
	repoURL := fmt.Sprintf("https://aur.archlinux.org/%s.git", base)
	ui.SubStep("Cloning %s -> %s", ui.C(ui.Cyan, repoURL), dest)
	if err := runQuiet(destParent, "git", "clone", repoURL, dest); err != nil {
		return "", err
	}
	return dest, nil
}

// BuildAndInstall builds and installs an AUR package using makepkg.
func BuildAndInstall(pkg aur.Package, dir string, prevHead string, opts Options) error {
	if !opts.NoConfirm && opts.ReviewDiff {
		if prevHead != "" && prevHead != gitRevParse(dir, "HEAD") {
			if ui.Confirm(fmt.Sprintf("Show PKGBUILD diff for %s?", pkg.Name), false) {
				_ = runInteractive(dir, "git", "diff", prevHead, "HEAD")
			}
		} else if ui.Confirm(fmt.Sprintf("Inspect PKGBUILD for %s?", pkg.Name), false) {
			pager := os.Getenv("PAGER")
			if pager == "" {
				pager = "less"
			}
			_ = runInteractive(dir, pager, filepath.Join(dir, "PKGBUILD"))
		}
	}

	args := []string{"-si"}
	if opts.NoConfirm {
		args = append(args, "--noconfirm")
	}
	if opts.Needed {
		args = append(args, "--needed")
	}
	if opts.AsDeps {
		args = append(args, "--asdeps")
	}

	ui.Step("Building & installing AUR package %s (%s)", ui.C(ui.Purple, pkg.Name), pkg.Version)
	return runInteractive(dir, "makepkg", args...)
}

// CleanCache removes cached AUR builds in CacheDir.
func CleanCache(cacheDir string) (int64, error) {
	sz := DirSize(cacheDir)
	if err := os.RemoveAll(cacheDir); err != nil {
		return 0, err
	}
	return sz, nil
}

func DirSize(path string) int64 {
	var total int64
	_ = filepath.Walk(path, func(_ string, info os.FileInfo, err error) error {
		if err == nil && info != nil && !info.IsDir() {
			total += info.Size()
		}
		return nil
	})
	return total
}

func gitRevParse(dir, ref string) string {
	out, err := exec.Command("git", "-C", dir, "rev-parse", ref).Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}

func runQuiet(dir, name string, args ...string) error {
	cmd := exec.Command(name, args...)
	cmd.Dir = dir
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

func runInteractive(dir, name string, args ...string) error {
	cmd := exec.Command(name, args...)
	cmd.Dir = dir
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

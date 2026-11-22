package cli

import (
	"testing"

	"fyrpak/internal/pacman"
	"fyrpak/internal/ui"
)

func TestParseArgsYayCompatibility(t *testing.T) {
	// Bare fyrpak == -Syu
	p := ParseArgs(nil)
	if p.Mode != "sync" || p.SubFlags['y'] != 1 || p.SubFlags['u'] != 1 {
		t.Fatalf("expected bare fyrpak to default to -Syu, got %+v", p)
	}

	// Bare search query
	p = ParseArgs([]string{"neovim", "lsp"})
	if p.Mode != "search_install" || len(p.Targets) != 2 {
		t.Fatalf("expected search_install for bare terms, got %+v", p)
	}

	// -S --needed --noconfirm pkg
	p = ParseArgs([]string{"-S", "--needed", "--noconfirm", "foo-git"})
	if p.Mode != "sync" || !p.Needed || !p.NoConfirm || len(p.Targets) != 1 || p.Targets[0] != "foo-git" {
		t.Fatalf("unexpected parse for -S: %+v", p)
	}

	// -Syuf (repo + AUR + fyrDE)
	p = ParseArgs([]string{"-Syuf"})
	if p.Mode != "sync" || p.SubFlags['y'] != 1 || p.SubFlags['u'] != 1 || !p.WithFyrDE {
		t.Fatalf("expected -Syuf to enable WithFyrDE, got %+v", p)
	}

	// -Yc (orphan cleanup)
	p = ParseArgs([]string{"-Yc", "--noconfirm"})
	if p.Mode != "yayclean" || !p.NoConfirm {
		t.Fatalf("expected yayclean mode for -Yc, got %+v", p)
	}

	// fyr subcommand
	p = ParseArgs([]string{"fyr", "update", "fyrtaskbar"})
	if p.Mode != "fyr" || len(p.Targets) != 2 || p.Targets[0] != "update" || p.Targets[1] != "fyrtaskbar" {
		t.Fatalf("unexpected fyr subcommand parse: %+v", p)
	}
}

func TestParseNumberSelection(t *testing.T) {
	got := ui.ParseNumberSelection("1 3-5 ^4", 10)
	want := []int{1, 3, 5}
	if len(got) != len(want) {
		t.Fatalf("got %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("got %v, want %v", got, want)
		}
	}
}

func TestFallbackCompareVersions(t *testing.T) {
	if pacman.FallbackCompareVersions("1.0.0-1", "1.0.1-1") >= 0 {
		t.Fatal("expected 1.0.0-1 < 1.0.1-1")
	}
	if pacman.FallbackCompareVersions("1:1.0-1", "2.0-1") <= 0 {
		t.Fatal("expected epoch 1:1.0-1 > 2.0-1")
	}
	if pacman.FallbackCompareVersions("2.10-1", "2.2-1") <= 0 {
		t.Fatal("expected 2.10-1 > 2.2-1")
	}
}

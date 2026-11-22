package resolver

import (
	"testing"

	"fyrpak/internal/aur"
)

type fakeEnv struct {
	satisfied map[string]bool
	syncDB    map[string]bool
	provides  map[string]bool
	aurPkgs   map[string]aur.Package
}

func (f *fakeEnv) IsSatisfied(depSpec string) bool {
	return f.satisfied[depSpec] || f.satisfied[StripDepName(depSpec)]
}
func (f *fakeEnv) ExistsInSyncDB(name string) bool { return f.syncDB[name] }
func (f *fakeEnv) SyncProvides(depName string) bool {
	return f.provides[depName] || f.syncDB[depName]
}
func (f *fakeEnv) AURInfoMap(names []string) (map[string]aur.Package, error) {
	out := map[string]aur.Package{}
	for _, n := range names {
		if p, ok := f.aurPkgs[n]; ok {
			out[n] = p
		}
	}
	return out, nil
}

func TestStripDepName(t *testing.T) {
	cases := map[string]string{
		"wlroots>=0.18":          "wlroots",
		"foo=1.2.3-1":            "foo",
		"bar: optional feature":  "bar",
		"baz<=2.0":               "baz",
		"  plain-pkg  ":          "plain-pkg",
	}
	for in, want := range cases {
		if got := StripDepName(in); got != want {
			t.Errorf("StripDepName(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestResolveTopologicalOrder(t *testing.T) {
	env := &fakeEnv{
		satisfied: map[string]bool{"glibc": true},
		syncDB:    map[string]bool{"git": true, "meson": true, "ripgrep": true},
		provides:  map[string]bool{},
		aurPkgs: map[string]aur.Package{
			"app-top": {
				Name:        "app-top",
				Depends:     []string{"lib-mid>=1.0", "glibc"},
				MakeDepends: []string{"meson"},
			},
			"lib-mid": {
				Name:        "lib-mid",
				Depends:     []string{"lib-base"},
				MakeDepends: []string{"git"},
			},
			"lib-base": {
				Name:    "lib-base",
				Depends: []string{"glibc"},
			},
		},
	}

	plan, err := Resolve([]string{"ripgrep", "app-top"}, env, false, false, true)
	if err != nil {
		t.Fatalf("Resolve failed: %v", err)
	}
	if len(plan.Missing) != 0 {
		t.Fatalf("unexpected missing packages: %v", plan.Missing)
	}
	if len(plan.RepoExplicit) != 1 || plan.RepoExplicit[0] != "ripgrep" {
		t.Fatalf("expected RepoExplicit=[ripgrep], got %v", plan.RepoExplicit)
	}
	if len(plan.AURBuild) != 3 {
		t.Fatalf("expected 3 AUR packages in build order, got %d", len(plan.AURBuild))
	}
	if plan.AURBuild[0].Name != "lib-base" || plan.AURBuild[1].Name != "lib-mid" || plan.AURBuild[2].Name != "app-top" {
		t.Fatalf("wrong build order: %s -> %s -> %s",
			plan.AURBuild[0].Name, plan.AURBuild[1].Name, plan.AURBuild[2].Name)
	}
}

func TestResolveDetectsCycle(t *testing.T) {
	env := &fakeEnv{
		satisfied: map[string]bool{},
		syncDB:    map[string]bool{},
		provides:  map[string]bool{},
		aurPkgs: map[string]aur.Package{
			"a": {Name: "a", Depends: []string{"b"}},
			"b": {Name: "b", Depends: []string{"a"}},
		},
	}

	if _, err := Resolve([]string{"a"}, env, true, false, false); err == nil {
		t.Fatal("expected cycle error, got nil")
	}
}

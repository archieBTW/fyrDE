package resolver

import (
	"fmt"
	"strings"

	"fyrpak/internal/aur"
)

type Plan struct {
	RepoExplicit []string      // User-requested packages from official repos
	RepoDeps     []string      // Repo dependencies required by AUR builds
	AURBuild     []aur.Package // Topologically sorted AUR packages to build & install
	Missing      []string      // Unresolved packages
}

// Env abstracts pacman queries so the resolver can be thoroughly unit-tested offline.
type Env interface {
	IsSatisfied(depSpec string) bool
	ExistsInSyncDB(name string) bool
	SyncProvides(depName string) bool
	AURInfoMap(names []string) (map[string]aur.Package, error)
}

// StripDepName extracts the bare package name from a versioned/described dep spec
// (e.g. "wlroots>=0.18", "foo: optional description", "bar=1.0").
func StripDepName(spec string) string {
	s := strings.TrimSpace(spec)
	if idx := strings.IndexByte(s, ':'); idx != -1 {
		s = strings.TrimSpace(s[:idx])
	}
	for _, op := range []string{">=", "<=", "=", ">", "<"} {
		if idx := strings.Index(s, op); idx != -1 {
			s = strings.TrimSpace(s[:idx])
		}
	}
	return s
}

func Resolve(targets []string, env Env, forceAUR, forceRepo, needed bool) (*Plan, error) {
	plan := &Plan{}
	repoDepSet := map[string]bool{}
	aurMeta := map[string]aur.Package{}
	explicitAUR := []string{}
	candidateAUR := []string{}

	for _, raw := range targets {
		name := StripDepName(raw)
		if name == "" {
			continue
		}
		if needed && env.IsSatisfied(raw) {
			continue
		}
		if !forceAUR && env.ExistsInSyncDB(name) {
			plan.RepoExplicit = append(plan.RepoExplicit, name)
			continue
		}
		if forceRepo {
			plan.Missing = append(plan.Missing, name)
			continue
		}
		candidateAUR = append(candidateAUR, name)
	}

	if len(candidateAUR) == 0 {
		return plan, nil
	}

	infoMap, err := env.AURInfoMap(candidateAUR)
	if err != nil {
		return nil, err
	}
	for _, name := range candidateAUR {
		pkg, ok := infoMap[name]
		if !ok {
			// Fall back to checking repo virtual provides
			if !forceAUR && env.SyncProvides(name) {
				plan.RepoExplicit = append(plan.RepoExplicit, name)
			} else {
				plan.Missing = append(plan.Missing, name)
			}
			continue
		}
		aurMeta[name] = pkg
		explicitAUR = append(explicitAUR, name)
	}

	// BFS to fetch metadata for transitive AUR dependencies
	queue := append([]string{}, explicitAUR...)
	visited := map[string]bool{}
	for _, n := range queue {
		visited[n] = true
	}

	for len(queue) > 0 {
		var toQueryAUR []string
		for _, pkgName := range queue {
			pkg := aurMeta[pkgName]
			allDeps := make([]string, 0, len(pkg.Depends)+len(pkg.MakeDepends))
			allDeps = append(allDeps, pkg.Depends...)
			allDeps = append(allDeps, pkg.MakeDepends...)

			for _, depSpec := range allDeps {
				if env.IsSatisfied(depSpec) {
					continue
				}
				depName := StripDepName(depSpec)
				if depName == "" || depName == pkgName {
					continue
				}
				if env.ExistsInSyncDB(depName) || env.SyncProvides(depName) {
					repoDepSet[depName] = true
					continue
				}
				if !visited[depName] {
					visited[depName] = true
					toQueryAUR = append(toQueryAUR, depName)
				}
			}
		}
		queue = nil
		if len(toQueryAUR) > 0 {
			depInfo, err := env.AURInfoMap(toQueryAUR)
			if err != nil {
				return nil, err
			}
			for _, depName := range toQueryAUR {
				if p, ok := depInfo[depName]; ok {
					aurMeta[depName] = p
					queue = append(queue, depName)
				} else {
					plan.Missing = append(plan.Missing, depName)
				}
			}
		}
	}

	for dep := range repoDepSet {
		plan.RepoDeps = append(plan.RepoDeps, dep)
	}

	// Topological sort (post-order DFS) over AUR packages so dependencies build first
	const (
		unvisited = 0
		visiting  = 1
		done      = 2
	)
	state := map[string]int{}
	var ordered []aur.Package

	var dfs func(name string) error
	dfs = func(name string) error {
		if state[name] == done {
			return nil
		}
		if state[name] == visiting {
			return fmt.Errorf("circular AUR dependency detected involving %q", name)
		}
		pkg, ok := aurMeta[name]
		if !ok {
			return nil
		}
		state[name] = visiting

		allDeps := make([]string, 0, len(pkg.Depends)+len(pkg.MakeDepends))
		allDeps = append(allDeps, pkg.Depends...)
		allDeps = append(allDeps, pkg.MakeDepends...)
		for _, depSpec := range allDeps {
			depName := StripDepName(depSpec)
			if _, isAUR := aurMeta[depName]; isAUR {
				if err := dfs(depName); err != nil {
					return err
				}
			}
		}

		state[name] = done
		ordered = append(ordered, pkg)
		return nil
	}

	for _, name := range explicitAUR {
		if err := dfs(name); err != nil {
			return nil, err
		}
	}

	plan.AURBuild = ordered
	return plan, nil
}

package cli

import (
	"fmt"
	"os"
	"sort"
	"strings"

	"fyrpak/internal/aur"
	"fyrpak/internal/builder"
	"fyrpak/internal/fyrde"
	"fyrpak/internal/pacman"
	"fyrpak/internal/resolver"
	"fyrpak/internal/ui"
)

const Version = "1.0.0"

type ParsedArgs struct {
	Mode       string // "", "sync", "remove", "query", "upgrade", "files", "database", "deptest", "yayclean", "stats", "getpkgbuild", "fyr", "help", "version"
	SubFlags   map[rune]int
	LongFlags  map[string]bool
	Targets    []string
	RawArgs    []string
	NoConfirm  bool
	Needed     bool
	AsDeps     bool
	AsExplicit bool
	CleanBuild bool
	Devel      bool
	AUROnly    bool
	RepoOnly   bool
	WithFyrDE  bool
	Overwrite  string
}

func ParseArgs(args []string) ParsedArgs {
	p := ParsedArgs{
		SubFlags:  map[rune]int{},
		LongFlags: map[string]bool{},
		RawArgs:   append([]string{}, args...),
	}

	if len(args) == 0 {
		// Bare `fyrpak` == `fyrpak -Syu` (yay behavior)
		p.Mode = "sync"
		p.SubFlags['y'] = 1
		p.SubFlags['u'] = 1
		return p
	}

	// Subcommand style (`fyrpak fyr ...`, `fyrpak help`, `fyrpak version`)
	switch args[0] {
	case "fyr", "fyrde":
		p.Mode = "fyr"
		p.Targets = args[1:]
		return p
	case "help", "-h", "--help":
		p.Mode = "help"
		return p
	case "version", "-V", "--version":
		p.Mode = "version"
		return p
	}

	for i := 0; i < len(args); i++ {
		arg := args[i]
		if arg == "--" {
			p.Targets = append(p.Targets, args[i+1:]...)
			break
		}
		if strings.HasPrefix(arg, "--") {
			flag := strings.TrimPrefix(arg, "--")
			p.LongFlags[flag] = true
			switch {
			case flag == "noconfirm":
				p.NoConfirm = true
			case flag == "needed":
				p.Needed = true
			case flag == "asdeps":
				p.AsDeps = true
			case flag == "asexplicit":
				p.AsExplicit = true
			case flag == "cleanbuild" || flag == "rebuild":
				p.CleanBuild = true
			case flag == "devel":
				p.Devel = true
			case flag == "aur":
				p.AUROnly = true
			case flag == "repo":
				p.RepoOnly = true
			case flag == "fyr" || flag == "fyrde":
				p.WithFyrDE = true
			case flag == "sync":
				p.Mode = "sync"
			case flag == "remove":
				p.Mode = "remove"
			case flag == "query":
				p.Mode = "query"
			case flag == "upgrade":
				p.Mode = "upgrade"
			case flag == "files":
				p.Mode = "files"
			case flag == "database":
				p.Mode = "database"
			case flag == "deptest":
				p.Mode = "deptest"
			case flag == "yay":
				p.Mode = "yayclean"
			case flag == "show":
				p.Mode = "stats"
			case flag == "getpkgbuild":
				p.Mode = "getpkgbuild"
			case strings.HasPrefix(flag, "overwrite="):
				p.Overwrite = strings.TrimPrefix(flag, "overwrite=")
			case flag == "overwrite" && i+1 < len(args):
				i++
				p.Overwrite = args[i]
			case flag == "help":
				p.Mode = "help"
			case flag == "version":
				p.Mode = "version"
			}
			continue
		}

		if strings.HasPrefix(arg, "-") && len(arg) > 1 {
			for _, r := range arg[1:] {
				switch r {
				case 'S':
					p.Mode = "sync"
				case 'R':
					p.Mode = "remove"
				case 'Q':
					p.Mode = "query"
				case 'U':
					p.Mode = "upgrade"
				case 'F':
					p.Mode = "files"
				case 'D':
					p.Mode = "database"
				case 'T':
					p.Mode = "deptest"
				case 'Y':
					p.Mode = "yayclean"
				case 'P':
					p.Mode = "stats"
				case 'G':
					p.Mode = "getpkgbuild"
				case 'a':
					p.AUROnly = true
					p.SubFlags[r]++
				case 'f':
					p.WithFyrDE = true
					p.SubFlags[r]++
				default:
					p.SubFlags[r]++
				}
			}
			continue
		}

		p.Targets = append(p.Targets, arg)
	}

	// Bare words without operation flags: interactive search & install (`fyrpak firefox`)
	if p.Mode == "" && len(p.Targets) > 0 {
		p.Mode = "search_install"
	}

	return p
}

type liveResolverEnv struct {
	aurClient *aur.Client
}

func (e *liveResolverEnv) IsSatisfied(depSpec string) bool {
	return pacman.IsSatisfied(depSpec)
}
func (e *liveResolverEnv) ExistsInSyncDB(name string) bool {
	return pacman.ExistsInSyncDB(name)
}
func (e *liveResolverEnv) SyncProvides(depName string) bool {
	return pacman.SyncProvides(depName)
}
func (e *liveResolverEnv) AURInfoMap(names []string) (map[string]aur.Package, error) {
	return e.aurClient.InfoMap(names)
}

func Run(args []string) int {
	parsed := ParseArgs(args)
	aurClient := aur.NewClient()

	var err error
	switch parsed.Mode {
	case "help":
		printHelp()
		return 0
	case "version":
		fmt.Printf("%s %s (fyrDE Go package manager & AUR helper)\n", ui.C(ui.Bold+ui.Purple, "fyrpak"), Version)
		return 0
	case "fyr":
		err = handleFyrSubcommand(parsed.Targets)
	case "search_install":
		err = handleInteractiveSearchInstall(parsed, aurClient)
	case "sync":
		err = handleSync(parsed, aurClient)
	case "query":
		err = handleQuery(parsed, aurClient)
	case "remove":
		err = pacman.RunInteractive(true, parsed.RawArgs...)
	case "upgrade", "database":
		err = pacman.RunInteractive(true, parsed.RawArgs...)
	case "files":
		needSudo := parsed.SubFlags['y'] > 0
		err = pacman.RunInteractive(needSudo, parsed.RawArgs...)
	case "deptest":
		err = pacman.RunInteractive(false, parsed.RawArgs...)
	case "yayclean":
		err = handleOrphanClean(parsed)
	case "stats":
		err = handleStats()
	case "getpkgbuild":
		err = handleGetPKGBUILD(parsed, aurClient)
	default:
		printHelp()
		return 1
	}

	if err != nil {
		ui.Error("%v", err)
		return 1
	}
	return 0
}

func handleFyrSubcommand(args []string) error {
	if len(args) == 0 {
		return fyrde.Status()
	}
	switch args[0] {
	case "list", "ls":
		return fyrde.ListApps()
	case "status", "st":
		return fyrde.Status()
	case "update", "up", "upgrade":
		return fyrde.Update(args[1:], true)
	case "rebuild":
		return fyrde.Update(args[1:], false)
	case "doctor", "check":
		return fyrde.Doctor()
	case "clean":
		return fyrde.Clean()
	default:
		return fmt.Errorf("unknown fyr subcommand %q (try: list, status, update, rebuild, doctor, clean)", args[0])
	}
}

func handleSync(p ParsedArgs, aurClient *aur.Client) error {
	// Search: -Ss
	if p.SubFlags['s'] > 0 {
		return handleSearchOnly(p, aurClient)
	}
	// Info: -Si
	if p.SubFlags['i'] > 0 {
		return handleSyncInfo(p, aurClient)
	}
	// Clean cache: -Sc / -Scc
	if p.SubFlags['c'] > 0 {
		return handleCleanCache(p)
	}

	// System + AUR upgrade: -Syu / -Sua / -Syuf
	if p.SubFlags['u'] > 0 {
		if !p.AUROnly {
			syncFlags := "-Su"
			if p.SubFlags['y'] >= 2 {
				syncFlags = "-Syyu"
			} else if p.SubFlags['y'] == 1 {
				syncFlags = "-Syu"
			}
			pacArgs := []string{syncFlags}
			if p.NoConfirm {
				pacArgs = append(pacArgs, "--noconfirm")
			}
			if p.Overwrite != "" {
				pacArgs = append(pacArgs, "--overwrite", p.Overwrite)
			}
			ui.Banner("Synchronizing & upgrading official Arch repositories...")
			if err := pacman.RunInteractive(true, pacArgs...); err != nil {
				return err
			}
		}

		if !p.RepoOnly {
			if err := upgradeAURPackages(p, aurClient); err != nil {
				return err
			}
		}

		if p.WithFyrDE {
			if err := fyrde.Update(nil, true); err != nil {
				return err
			}
		}

		if len(p.Targets) == 0 {
			return nil
		}
	} else if p.SubFlags['y'] > 0 && len(p.Targets) == 0 {
		flag := "-Sy"
		if p.SubFlags['y'] >= 2 {
			flag = "-Syy"
		}
		return pacman.RunInteractive(true, flag)
	}

	if len(p.Targets) == 0 {
		return fmt.Errorf("no targets specified (use `fyrpak -h` for help)")
	}

	return installTargets(p.Targets, p, aurClient)
}

func installTargets(targets []string, p ParsedArgs, aurClient *aur.Client) error {
	env := &liveResolverEnv{aurClient: aurClient}
	ui.Banner("Resolving dependencies...")
	plan, err := resolver.Resolve(targets, env, p.AUROnly, p.RepoOnly, p.Needed)
	if err != nil {
		return err
	}
	if len(plan.Missing) > 0 {
		return fmt.Errorf("could not find package(s): %s", strings.Join(plan.Missing, ", "))
	}

	if len(plan.RepoExplicit) == 0 && len(plan.RepoDeps) == 0 && len(plan.AURBuild) == 0 {
		ui.Success("Nothing to do (targets already satisfied).")
		return nil
	}

	// Summary preview
	if len(plan.RepoExplicit) > 0 {
		fmt.Printf("  %s %s\n", ui.C(ui.Bold+ui.Cyan, "Repo Explicit:"), strings.Join(plan.RepoExplicit, "  "))
	}
	if len(plan.RepoDeps) > 0 {
		fmt.Printf("  %s %s\n", ui.C(ui.Bold+ui.Cyan, "Repo Deps:    "), strings.Join(plan.RepoDeps, "  "))
	}
	if len(plan.AURBuild) > 0 {
		var names []string
		for _, a := range plan.AURBuild {
			names = append(names, fmt.Sprintf("%s-%s", a.Name, a.Version))
		}
		fmt.Printf("  %s %s\n", ui.C(ui.Bold+ui.Purple, "AUR Build:    "), strings.Join(names, "  "))
	}

	// 1. Install explicit repo packages
	if len(plan.RepoExplicit) > 0 {
		args := []string{"-S"}
		if p.Needed {
			args = append(args, "--needed")
		}
		if p.NoConfirm {
			args = append(args, "--noconfirm")
		}
		if p.AsDeps {
			args = append(args, "--asdeps")
		}
		if p.AsExplicit {
			args = append(args, "--asexplicit")
		}
		if p.Overwrite != "" {
			args = append(args, "--overwrite", p.Overwrite)
		}
		args = append(args, plan.RepoExplicit...)
		if err := pacman.RunInteractive(true, args...); err != nil {
			return err
		}
	}

	// 2. Install repo dependencies for AUR builds
	if len(plan.RepoDeps) > 0 {
		args := []string{"-S", "--needed", "--asdeps"}
		if p.NoConfirm {
			args = append(args, "--noconfirm")
		}
		args = append(args, plan.RepoDeps...)
		if err := pacman.RunInteractive(true, args...); err != nil {
			return err
		}
	}

	// 3. Build & install AUR packages in dependency order
	explicitSet := map[string]bool{}
	for _, t := range targets {
		explicitSet[resolver.StripDepName(t)] = true
	}

	opts := builder.Options{
		CacheDir:   builder.DefaultCacheDir(),
		NoConfirm:  p.NoConfirm,
		Needed:     p.Needed,
		CleanBuild: p.CleanBuild,
		ReviewDiff: !p.NoConfirm,
	}

	for _, pkg := range plan.AURBuild {
		pkgOpts := opts
		pkgOpts.AsDeps = p.AsDeps || !explicitSet[pkg.Name]
		dir, prevHead, err := builder.FetchOrUpdate(pkg, pkgOpts)
		if err != nil {
			return err
		}
		if err := builder.BuildAndInstall(pkg, dir, prevHead, pkgOpts); err != nil {
			return fmt.Errorf("failed building %s: %w", pkg.Name, err)
		}
	}

	ui.Success("Installation complete.")
	return nil
}

func upgradeAURPackages(p ParsedArgs, aurClient *aur.Client) error {
	ui.Banner("Checking AUR for upgrades...")
	foreign, err := pacman.ForeignMap()
	if err != nil {
		return err
	}
	if len(foreign) == 0 {
		ui.Success("No foreign/AUR packages installed.")
		return nil
	}

	var names []string
	for name := range foreign {
		names = append(names, name)
	}
	sort.Strings(names)

	infoMap, err := aurClient.InfoMap(names)
	if err != nil {
		return err
	}

	var toUpgrade []string
	for _, name := range names {
		localVer := foreign[name]
		remote, ok := infoMap[name]
		if !ok {
			continue
		}
		isVCS := p.Devel && (strings.HasSuffix(name, "-git") || strings.HasSuffix(name, "-hg") || strings.HasSuffix(name, "-svn"))
		if pacman.CompareVersions(localVer, remote.Version) < 0 || isVCS {
			fmt.Println(pacman.FormatUpdateLine(
				ui.C(ui.Purple, name),
				ui.C(ui.Muted, localVer),
				ui.C(ui.Green, remote.Version),
			))
			toUpgrade = append(toUpgrade, name)
		}
	}

	if len(toUpgrade) == 0 {
		ui.Success("All AUR packages are up to date.")
		return nil
	}

	if !p.NoConfirm && !ui.Confirm(fmt.Sprintf("Upgrade %d AUR package(s)?", len(toUpgrade)), true) {
		return nil
	}

	upgradeArgs := p
	upgradeArgs.AUROnly = true
	upgradeArgs.Needed = false
	return installTargets(toUpgrade, upgradeArgs, aurClient)
}

func handleSearchOnly(p ParsedArgs, aurClient *aur.Client) error {
	if len(p.Targets) == 0 {
		return fmt.Errorf("no search terms provided")
	}
	installed, _ := pacman.InstalledMap()

	if !p.AUROnly {
		repoRes, _ := pacman.SearchSync(p.Targets)
		for _, r := range repoRes {
			badge := ""
			if r.Installed {
				badge = " " + ui.C(ui.Green, "[installed]")
			}
			fmt.Printf("%s/%s %s%s\n    %s\n",
				ui.C(ui.Bold+ui.Cyan, r.Repo),
				ui.C(ui.Bold, r.Name),
				ui.C(ui.Green, r.Version),
				badge,
				r.Description,
			)
		}
	}

	if !p.RepoOnly {
		aurRes, err := aurClient.Search(p.Targets)
		if err != nil {
			return err
		}
		for _, a := range aurRes {
			badge := ""
			if _, ok := installed[a.Name]; ok {
				badge += " " + ui.C(ui.Green, "[installed]")
			}
			if a.OutOfDate != nil && *a.OutOfDate > 0 {
				badge += " " + ui.C(ui.Red, "[out-of-date]")
			}
			fmt.Printf("%s/%s %s %s%s\n    %s\n",
				ui.C(ui.Bold+ui.Purple, "aur"),
				ui.C(ui.Bold, a.Name),
				ui.C(ui.Green, a.Version),
				ui.C(ui.Muted, fmt.Sprintf("(+%d %.2f)", a.NumVotes, a.Popularity)),
				badge,
				a.Description,
			)
		}
	}
	return nil
}

func handleInteractiveSearchInstall(p ParsedArgs, aurClient *aur.Client) error {
	type entry struct {
		repo        string
		name        string
		version     string
		desc        string
		installed   bool
		extra       string
		isAUR       bool
		outOfDate   bool
	}

	installed, _ := pacman.InstalledMap()
	var list []entry

	if !p.AUROnly {
		repoRes, _ := pacman.SearchSync(p.Targets)
		for _, r := range repoRes {
			list = append(list, entry{
				repo:      r.Repo,
				name:      r.Name,
				version:   r.Version,
				desc:      r.Description,
				installed: r.Installed,
			})
		}
	}
	if !p.RepoOnly {
		aurRes, err := aurClient.Search(p.Targets)
		if err != nil {
			ui.Warn("AUR search failed: %v", err)
		} else {
			maxAUR := 30
			if len(aurRes) < maxAUR {
				maxAUR = len(aurRes)
			}
			for _, a := range aurRes[:maxAUR] {
				_, inst := installed[a.Name]
				list = append(list, entry{
					repo:      "aur",
					name:      a.Name,
					version:   a.Version,
					desc:      a.Description,
					installed: inst,
					extra:     fmt.Sprintf("(+%d %.2f)", a.NumVotes, a.Popularity),
					isAUR:     true,
					outOfDate: a.OutOfDate != nil && *a.OutOfDate > 0,
				})
			}
		}
	}

	if len(list) == 0 {
		ui.Warn("No packages found matching %q", strings.Join(p.Targets, " "))
		return nil
	}

	// Print bottom-up numbered list just like yay (1 is closest to prompt)
	for i := len(list) - 1; i >= 0; i-- {
		e := list[i]
		num := i + 1
		repoColor := ui.Cyan
		if e.isAUR {
			repoColor = ui.Purple
		}
		badge := ""
		if e.installed {
			badge += " " + ui.C(ui.Green, "[installed]")
		}
		if e.outOfDate {
			badge += " " + ui.C(ui.Red, "[out-of-date]")
		}
		extra := ""
		if e.extra != "" {
			extra = " " + ui.C(ui.Muted, e.extra)
		}
		fmt.Printf("%s %s/%s %s%s%s\n    %s\n",
			ui.C(ui.Bold+ui.Violet, fmt.Sprintf("%d", num)),
			ui.C(ui.Bold+repoColor, e.repo),
			ui.C(ui.Bold, e.name),
			ui.C(ui.Green, e.version),
			extra,
			badge,
			e.desc,
		)
	}

	selRaw := ui.PromptLine("Packages to install (e.g. 1 2 3, 1-3, ^2, or empty to cancel):")
	nums := ui.ParseNumberSelection(selRaw, len(list))
	if len(nums) == 0 {
		return nil
	}
	var chosen []string
	for _, n := range nums {
		chosen = append(chosen, list[n-1].name)
	}
	return installTargets(chosen, p, aurClient)
}

func handleSyncInfo(p ParsedArgs, aurClient *aur.Client) error {
	if len(p.Targets) == 0 {
		return pacman.RunInteractive(false, "-Si")
	}
	var repoPkgs, aurCandidates []string
	for _, t := range p.Targets {
		if !p.AUROnly && pacman.ExistsInSyncDB(t) {
			repoPkgs = append(repoPkgs, t)
		} else {
			aurCandidates = append(aurCandidates, t)
		}
	}
	if len(repoPkgs) > 0 {
		args := append([]string{"-Si"}, repoPkgs...)
		_ = pacman.RunInteractive(false, args...)
	}
	if len(aurCandidates) > 0 {
		info, err := aurClient.Info(aurCandidates)
		if err != nil {
			return err
		}
		for _, a := range info {
			fmt.Printf("%-18s : %s\n", ui.C(ui.Bold+ui.Purple, "Repository"), "aur")
			fmt.Printf("%-18s : %s\n", ui.C(ui.Bold, "Name"), a.Name)
			fmt.Printf("%-18s : %s\n", ui.C(ui.Bold, "Version"), a.Version)
			fmt.Printf("%-18s : %s\n", ui.C(ui.Bold, "Description"), a.Description)
			fmt.Printf("%-18s : %s\n", ui.C(ui.Bold, "URL"), a.URL)
			fmt.Printf("%-18s : %s\n", ui.C(ui.Bold, "Maintainer"), a.Maintainer)
			fmt.Printf("%-18s : %d (Popularity: %.2f)\n", ui.C(ui.Bold, "Votes"), a.NumVotes, a.Popularity)
			if len(a.Depends) > 0 {
				fmt.Printf("%-18s : %s\n", ui.C(ui.Bold, "Depends On"), strings.Join(a.Depends, "  "))
			}
			if len(a.MakeDepends) > 0 {
				fmt.Printf("%-18s : %s\n", ui.C(ui.Bold, "Make Deps"), strings.Join(a.MakeDepends, "  "))
			}
			fmt.Println()
		}
	}
	return nil
}

func handleQuery(p ParsedArgs, aurClient *aur.Client) error {
	// -Qua: list available AUR updates
	if p.SubFlags['u'] > 0 && p.AUROnly {
		foreign, err := pacman.ForeignMap()
		if err != nil {
			return err
		}
		var names []string
		for n := range foreign {
			names = append(names, n)
		}
		sort.Strings(names)
		infoMap, err := aurClient.InfoMap(names)
		if err != nil {
			return err
		}
		for _, n := range names {
			if r, ok := infoMap[n]; ok && pacman.CompareVersions(foreign[n], r.Version) < 0 {
				fmt.Printf("%s %s -> %s\n", n, foreign[n], r.Version)
			}
		}
		return nil
	}
	return pacman.RunInteractive(false, p.RawArgs...)
}

func handleCleanCache(p ParsedArgs) error {
	flag := "-Sc"
	if p.SubFlags['c'] >= 2 {
		flag = "-Scc"
	}
	pacArgs := []string{flag}
	if p.NoConfirm {
		pacArgs = append(pacArgs, "--noconfirm")
	}
	if err := pacman.RunInteractive(true, pacArgs...); err != nil {
		return err
	}
	cacheDir := builder.DefaultCacheDir()
	sz := builder.DirSize(cacheDir)
	if sz > 0 {
		if p.NoConfirm || ui.Confirm(fmt.Sprintf("Remove fyrpak AUR build cache (%s at %s)?", ui.FormatBytes(sz), cacheDir), true) {
			_, err := builder.CleanCache(cacheDir)
			if err != nil {
				return err
			}
			ui.Success("Cleaned fyrpak AUR cache (%s)", ui.FormatBytes(sz))
		}
	}
	return nil
}

func handleOrphanClean(p ParsedArgs) error {
	orphans := pacman.Orphans()
	if len(orphans) == 0 {
		ui.Success("No unneeded orphan dependencies found.")
		return nil
	}
	ui.Banner(fmt.Sprintf("Removing %d orphan package(s)...", len(orphans)))
	args := []string{"-Rns"}
	if p.NoConfirm {
		args = append(args, "--noconfirm")
	}
	args = append(args, orphans...)
	return pacman.RunInteractive(true, args...)
}

func handleStats() error {
	all, _ := pacman.InstalledMap()
	foreign, _ := pacman.ForeignMap()
	explicit := pacman.ExplicitCount()
	sizes, totalBytes := pacman.TopInstalledSizes()

	sort.Slice(sizes, func(i, j int) bool {
		return sizes[i].SizeBytes > sizes[j].SizeBytes
	})

	ui.Banner(fmt.Sprintf("fyrpak %s — System Package Statistics", Version))
	fmt.Printf("  %-28s %s\n", ui.C(ui.Purple, "Total installed packages:"), ui.C(ui.Bold, fmt.Sprintf("%d", len(all))))
	fmt.Printf("  %-28s %s\n", ui.C(ui.Purple, "Explicitly installed:"), ui.C(ui.Bold, fmt.Sprintf("%d", explicit)))
	fmt.Printf("  %-28s %s\n", ui.C(ui.Purple, "Foreign / AUR packages:"), ui.C(ui.Bold, fmt.Sprintf("%d", len(foreign))))
	fmt.Printf("  %-28s %s\n", ui.C(ui.Purple, "Total installed size:"), ui.C(ui.Bold, ui.FormatBytes(totalBytes)))
	fmt.Printf("  %-28s %s\n", ui.C(ui.Purple, "fyrpak AUR cache size:"), ui.C(ui.Bold, ui.FormatBytes(builder.DirSize(builder.DefaultCacheDir()))))

	if root, err := fyrde.FindRepoRoot(); err == nil {
		apps := fyrde.DiscoverApps(root)
		fmt.Printf("  %-28s %s\n", ui.C(ui.Purple, "fyrDE apps in repo:"), ui.C(ui.Bold, fmt.Sprintf("%d", len(apps))))
	}

	fmt.Printf("\n%s\n", ui.C(ui.Bold+ui.Cyan, "Ten largest installed packages:"))
	limit := 10
	if len(sizes) < limit {
		limit = len(sizes)
	}
	for i := 0; i < limit; i++ {
		fmt.Printf("  %-30s %s\n", sizes[i].Name, ui.C(ui.Muted, ui.FormatBytes(sizes[i].SizeBytes)))
	}
	return nil
}

func handleGetPKGBUILD(p ParsedArgs, aurClient *aur.Client) error {
	if len(p.Targets) == 0 {
		return fmt.Errorf("specify one or more AUR package names for -G")
	}
	cwd, err := os.Getwd()
	if err != nil {
		return err
	}
	infoMap, err := aurClient.InfoMap(p.Targets)
	if err != nil {
		return err
	}
	for _, name := range p.Targets {
		pkg, ok := infoMap[name]
		if !ok {
			ui.Warn("AUR package %q not found", name)
			continue
		}
		if _, err := builder.CloneToDir(pkg, cwd); err != nil {
			return err
		}
	}
	ui.Success("Fetched PKGBUILD(s) into %s", cwd)
	return nil
}

func printHelp() {
	fmt.Printf(`%s %s — Native Go Package Manager, AUR Helper & fyrDE Manager

%s
  fyrpak                     Full system + AUR upgrade (-Syu)
  fyrpak <terms...>          Interactive search & install (official repos + AUR)
  fyrpak -S <pkgs...>        Install repo & AUR packages (--needed --noconfirm --cleanbuild)
  fyrpak -Syu                Upgrade official repos + AUR (--devel for -git packages)
  fyrpak -Syuf / -Syu --fyr  Upgrade official repos + AUR + all installed fyrDE apps
  fyrpak -Sua                Upgrade AUR packages only
  fyrpak -Ss <terms...>      Search official repos + AUR
  fyrpak -Si <pkgs...>       Show package details (repo or AUR)
  fyrpak -Sc / -Scc          Clean pacman & fyrpak AUR build cache
  fyrpak -R[ns] <pkgs...>    Remove packages via pacman
  fyrpak -Q[m|e|i|l|dt|ua]   Query local packages (-Qua lists AUR updates)
  fyrpak -Yc                 Remove unneeded orphan dependencies
  fyrpak -Ps                 Show system, package & fyrDE statistics
  fyrpak -G <pkgs...>        Clone AUR PKGBUILDs into the current directory

%s
  fyrpak fyr status          Show fyrDE repo, branch, compositor & app install status
  fyrpak fyr list            List all fyrDE apps and /opt install timestamps
  fyrpak fyr update [apps]   Pull & rebuild/reinstall specific fyrDE apps (or swayfx / all)
  fyrpak fyr rebuild [apps]  Rebuild/reinstall local fyrDE apps without git pull
  fyrpak fyr doctor          Audit fyrDE binaries, running daemons, PATH & orphans
  fyrpak fyr clean           Reclaim space from Flutter build/linux & AUR caches
`, ui.C(ui.Bold+ui.Purple, "fyrpak"), Version, ui.C(ui.Bold+ui.Cyan, "Usage (yay / pacman compatible):"), ui.C(ui.Bold+ui.Cyan, "fyrDE Commands:"))
}

package pacman

import (
	"bufio"
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"
)

type RepoSearchResult struct {
	Repo        string
	Name        string
	Version     string
	Description string
	Installed   bool
}

type InstalledPkg struct {
	Name    string
	Version string
}

type PkgSize struct {
	Name      string
	SizeBytes int64
}

func RunInteractive(useSudo bool, args ...string) error {
	var cmd *exec.Cmd
	if useSudo && os.Geteuid() != 0 {
		all := append([]string{"pacman"}, args...)
		cmd = exec.Command("sudo", all...)
	} else {
		cmd = exec.Command("pacman", args...)
	}
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

func RunCapture(args ...string) (string, error) {
	cmd := exec.Command("pacman", args...)
	var out bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &bytes.Buffer{}
	err := cmd.Run()
	return out.String(), err
}

func InstalledMap() (map[string]string, error) {
	out, err := RunCapture("-Q")
	if err != nil {
		return nil, err
	}
	return parsePkgLines(out), nil
}

func ForeignMap() (map[string]string, error) {
	out, err := RunCapture("-Qm")
	if err != nil {
		// pacman -Qm exits 1 when there are zero foreign packages.
		return map[string]string{}, nil
	}
	return parsePkgLines(out), nil
}

func ExplicitCount() int {
	out, err := RunCapture("-Qe")
	if err != nil {
		return 0
	}
	return len(parsePkgLines(out))
}

func Orphans() []string {
	out, err := RunCapture("-Qdtq")
	if err != nil {
		return nil
	}
	var list []string
	for _, line := range strings.Split(out, "\n") {
		if t := strings.TrimSpace(line); t != "" {
			list = append(list, t)
		}
	}
	return list
}

func IsSatisfied(depSpec string) bool {
	cmd := exec.Command("pacman", "-T", depSpec)
	return cmd.Run() == nil
}

func ExistsInSyncDB(name string) bool {
	cmd := exec.Command("pacman", "-Si", name)
	return cmd.Run() == nil
}

func SyncProvides(depName string) bool {
	out, err := RunCapture("-Ssq", "^"+depName+"$")
	if err == nil && strings.TrimSpace(out) != "" {
		return true
	}
	// Also check if pacman -Sp resolves a virtual provide
	cmd := exec.Command("pacman", "-Sp", "--print-format", "%n", depName)
	return cmd.Run() == nil
}

func SearchSync(terms []string) ([]RepoSearchResult, error) {
	if len(terms) == 0 {
		return nil, nil
	}
	args := append([]string{"-Ss"}, terms...)
	out, err := RunCapture(args...)
	if err != nil {
		// pacman -Ss returns exit code 1 when nothing matches.
		return nil, nil
	}
	return parseSearchOutput(out), nil
}

func parseSearchOutput(out string) []RepoSearchResult {
	var results []RepoSearchResult
	scanner := bufio.NewScanner(strings.NewReader(out))
	var current *RepoSearchResult

	for scanner.Scan() {
		line := scanner.Text()
		if !strings.HasPrefix(line, " ") && !strings.HasPrefix(line, "\t") && strings.Contains(line, "/") {
			if current != nil {
				results = append(results, *current)
			}
			fields := strings.Fields(line)
			if len(fields) < 2 {
				current = nil
				continue
			}
			repoName := strings.SplitN(fields[0], "/", 2)
			if len(repoName) != 2 {
				current = nil
				continue
			}
			current = &RepoSearchResult{
				Repo:      repoName[0],
				Name:      repoName[1],
				Version:   fields[1],
				Installed: strings.Contains(line, "[installed"),
			}
		} else if current != nil {
			desc := strings.TrimSpace(line)
			if current.Description == "" {
				current.Description = desc
			} else {
				current.Description += " " + desc
			}
		}
	}
	if current != nil {
		results = append(results, *current)
	}
	return results
}

func parsePkgLines(out string) map[string]string {
	m := make(map[string]string)
	for _, line := range strings.Split(out, "\n") {
		fields := strings.Fields(line)
		if len(fields) >= 2 {
			m[fields[0]] = fields[1]
		}
	}
	return m
}

// CompareVersions compares two Arch package versions using `vercmp` when available,
// returning -1 if a < b, 0 if a == b, 1 if a > b.
func CompareVersions(a, b string) int {
	if a == b {
		return 0
	}
	out, err := exec.Command("vercmp", a, b).Output()
	if err == nil {
		if n, parseErr := strconv.Atoi(strings.TrimSpace(string(out))); parseErr == nil {
			switch {
			case n < 0:
				return -1
			case n > 0:
				return 1
			default:
				return 0
			}
		}
	}
	return FallbackCompareVersions(a, b)
}

// FallbackCompareVersions implements Arch EVR comparison when vercmp is absent.
func FallbackCompareVersions(a, b string) int {
	ea, va := splitEpoch(a)
	eb, vb := splitEpoch(b)
	if ea != eb {
		if ea < eb {
			return -1
		}
		return 1
	}
	if va == vb {
		return 0
	}
	pa := splitVersionTokens(va)
	pb := splitVersionTokens(vb)
	n := len(pa)
	if len(pb) < n {
		n = len(pb)
	}
	for i := 0; i < n; i++ {
		if pa[i] == pb[i] {
			continue
		}
		na, errA := strconv.Atoi(pa[i])
		nb, errB := strconv.Atoi(pb[i])
		if errA == nil && errB == nil {
			if na < nb {
				return -1
			}
			return 1
		}
		if pa[i] < pb[i] {
			return -1
		}
		return 1
	}
	if len(pa) < len(pb) {
		return -1
	}
	if len(pa) > len(pb) {
		return 1
	}
	return 0
}

func splitEpoch(v string) (int, string) {
	if idx := strings.IndexByte(v, ':'); idx > 0 {
		if e, err := strconv.Atoi(v[:idx]); err == nil {
			return e, v[idx+1:]
		}
	}
	return 0, v
}

func splitVersionTokens(v string) []string {
	var tokens []string
	var cur strings.Builder
	isNum := false
	for i := 0; i < len(v); i++ {
		ch := v[i]
		if (ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') {
			chNum := ch >= '0' && ch <= '9'
			if cur.Len() > 0 && chNum != isNum {
				tokens = append(tokens, cur.String())
				cur.Reset()
			}
			isNum = chNum
			cur.WriteByte(ch)
		} else if cur.Len() > 0 {
			tokens = append(tokens, cur.String())
			cur.Reset()
		}
	}
	if cur.Len() > 0 {
		tokens = append(tokens, cur.String())
	}
	return tokens
}

// TopInstalledSizes returns installed packages with their disk size in bytes.
func TopInstalledSizes() ([]PkgSize, int64) {
	out, err := RunCapture("-Qi")
	if err != nil {
		return nil, 0
	}
	var list []PkgSize
	var total int64
	var name string

	scanner := bufio.NewScanner(strings.NewReader(out))
	for scanner.Scan() {
		line := scanner.Text()
		if strings.HasPrefix(line, "Name") {
			if idx := strings.IndexByte(line, ':'); idx != -1 {
				name = strings.TrimSpace(line[idx+1:])
			}
		} else if strings.HasPrefix(line, "Installed Size") && name != "" {
			if idx := strings.IndexByte(line, ':'); idx != -1 {
				sz := parseHumanSize(strings.TrimSpace(line[idx+1:]))
				list = append(list, PkgSize{Name: name, SizeBytes: sz})
				total += sz
				name = ""
			}
		}
	}
	return list, total
}

func parseHumanSize(s string) int64 {
	fields := strings.Fields(s)
	if len(fields) == 0 {
		return 0
	}
	val, err := strconv.ParseFloat(fields[0], 64)
	if err != nil {
		return 0
	}
	unit := ""
	if len(fields) > 1 {
		unit = strings.ToLower(fields[1])
	}
	switch {
	case strings.HasPrefix(unit, "g"):
		return int64(val * 1024 * 1024 * 1024)
	case strings.HasPrefix(unit, "m"):
		return int64(val * 1024 * 1024)
	case strings.HasPrefix(unit, "k"):
		return int64(val * 1024)
	default:
		return int64(val)
	}
}

func FormatUpdateLine(name, oldVer, newVer string) string {
	return fmt.Sprintf("  %-32s %s -> %s", name, oldVer, newVer)
}

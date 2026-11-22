package ui

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"
)

const (
	Reset  = "\033[0m"
	Bold   = "\033[1m"
	Dim    = "\033[2m"
	Purple = "\033[38;5;177m"
	Violet = "\033[38;5;135m"
	Cyan   = "\033[38;5;81m"
	Green  = "\033[38;5;114m"
	Yellow = "\033[38;5;221m"
	Red    = "\033[38;5;203m"
	Muted  = "\033[38;5;245m"
)

func noColor() bool {
	return os.Getenv("NO_COLOR") != ""
}

func C(code, text string) string {
	if noColor() {
		return text
	}
	return code + text + Reset
}

func Banner(title string) {
	fmt.Printf("%s %s\n", C(Bold+Purple, "::"), C(Bold, title))
}

func Step(format string, args ...any) {
	msg := fmt.Sprintf(format, args...)
	fmt.Printf("%s %s\n", C(Bold+Cyan, "==>"), C(Bold, msg))
}

func SubStep(format string, args ...any) {
	msg := fmt.Sprintf(format, args...)
	fmt.Printf("  %s %s\n", C(Purple, "->"), msg)
}

func Success(format string, args ...any) {
	msg := fmt.Sprintf(format, args...)
	fmt.Printf("%s %s\n", C(Bold+Green, "✓"), msg)
}

func Warn(format string, args ...any) {
	msg := fmt.Sprintf(format, args...)
	fmt.Fprintf(os.Stderr, "%s %s\n", C(Bold+Yellow, "warning:"), msg)
}

func Error(format string, args ...any) {
	msg := fmt.Sprintf(format, args...)
	fmt.Fprintf(os.Stderr, "%s %s\n", C(Bold+Red, "error:"), msg)
}

func Confirm(prompt string, defaultYes bool) bool {
	suffix := "[y/N]"
	if defaultYes {
		suffix = "[Y/n]"
	}
	fmt.Printf("%s %s %s ", C(Bold+Purple, "::"), prompt, C(Muted, suffix))
	reader := bufio.NewReader(os.Stdin)
	line, err := reader.ReadString('\n')
	if err != nil {
		return defaultYes
	}
	ans := strings.TrimSpace(strings.ToLower(line))
	if ans == "" {
		return defaultYes
	}
	return ans == "y" || ans == "yes"
}

// ParseNumberSelection parses yay-style selections such as "1 3 5-7 ^6".
func ParseNumberSelection(input string, max int) []int {
	fields := strings.Fields(strings.ReplaceAll(input, ",", " "))
	if len(fields) == 0 {
		return nil
	}
	selected := map[int]bool{}
	excluded := map[int]bool{}

	for _, f := range fields {
		neg := false
		if strings.HasPrefix(f, "^") {
			neg = true
			f = strings.TrimPrefix(f, "^")
		}
		if strings.Contains(f, "-") {
			parts := strings.SplitN(f, "-", 2)
			a, err1 := strconv.Atoi(parts[0])
			b, err2 := strconv.Atoi(parts[1])
			if err1 != nil || err2 != nil {
				continue
			}
			if a > b {
				a, b = b, a
			}
			for i := a; i <= b; i++ {
				if i >= 1 && i <= max {
					if neg {
						excluded[i] = true
					} else {
						selected[i] = true
					}
				}
			}
		} else {
			n, err := strconv.Atoi(f)
			if err == nil && n >= 1 && n <= max {
				if neg {
					excluded[n] = true
				} else {
					selected[n] = true
				}
			}
		}
	}

	var out []int
	for i := 1; i <= max; i++ {
		if selected[i] && !excluded[i] {
			out = append(out, i)
		}
	}
	return out
}

func PromptLine(prompt string) string {
	fmt.Printf("%s %s ", C(Bold+Purple, "::"), prompt)
	reader := bufio.NewReader(os.Stdin)
	line, _ := reader.ReadString('\n')
	return strings.TrimSpace(line)
}

func FormatBytes(bytes int64) string {
	const unit = 1024
	if bytes < unit {
		return fmt.Sprintf("%d B", bytes)
	}
	div, exp := int64(unit), 0
	for n := bytes / unit; n >= unit; n /= unit {
		div *= unit
		exp++
	}
	return fmt.Sprintf("%.1f %ciB", float64(bytes)/float64(div), "KMGTPE"[exp])
}

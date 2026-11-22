package main

import (
	"os"

	"fyrpak/internal/cli"
)

func main() {
	os.Exit(cli.Run(os.Args[1:]))
}

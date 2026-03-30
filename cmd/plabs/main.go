package main

import (
	"os"

	"github.com/DataDog/pathfinding-labs/internal/cmd"
)

func main() {
	if err := cmd.Execute(); err != nil {
		os.Exit(1)
	}
}

package main

import (
	"fmt"
	"os"

	"github.com/DataDog/pathfinding-labs/internal/cmd"
)

func main() {
	if err := cmd.Execute(); err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err)
		os.Exit(1)
	}
}

package main

import (
	"context"
	"fmt"
	"log"
	"math/rand"
	"os"
	"os/signal"
	"time"

	"github.com/ostcar/gebot/config"
	"github.com/ostcar/gebot/model"
	"github.com/ostcar/gebot/web"
)

func main() {
	rand.Seed(time.Now().UnixNano())

	if err := run(); err != nil {
		log.Printf("Error: %v", err)
		os.Exit(1)
	}
}

func run() error {
	ctx, cancel := interruptContext()
	defer cancel()

	model, err := model.New(model.FileDB{File: "db.jsonl"})
	if err != nil {
		return fmt.Errorf("loading model: %w", err)
	}

	config, err := config.LoadConfig("config.toml")
	if err != nil {
		return fmt.Errorf("loading config: %w", err)
	}

	if err := web.Run(ctx, model, config); err != nil {
		return fmt.Errorf("running http server: %w", err)
	}
	return nil
}

// interruptContext works like signal.NotifyContext
//
// In only listens on os.Interrupt. If the signal is received two times,
// os.Exit(1) is called.
func interruptContext() (context.Context, context.CancelFunc) {
	ctx, cancel := context.WithCancel(context.Background())
	go func() {
		sigint := make(chan os.Signal, 1)
		signal.Notify(sigint, os.Interrupt)
		<-sigint
		cancel()

		// If the signal was send for the second time, make a hard cut.
		<-sigint
		os.Exit(1)
	}()
	return ctx, cancel
}

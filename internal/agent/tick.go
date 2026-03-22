package agent

import (
	"context"
	"fmt"
	"log"
	"os"
	"strings"

	"moltbook-agent/internal/config"
	"moltbook-agent/internal/gemini"
	"moltbook-agent/internal/moltbook"
)

// RunTick performs one agent cycle: optional Moltbook connectivity check and a minimal Gemini call.
// It is intended to be triggered on a schedule (e.g. Cloud Scheduler → Cloud Run).
//
// Set AGENT_SKIP_GEMINI=true (or 1) to skip the Gemini request and only run the Moltbook ping (saves Generative Language API quota).
func RunTick(ctx context.Context, cfg config.Config) error {
	if !SkipGemini() {
		if err := cfg.ValidateForLLM(); err != nil {
			return err
		}
	}

	mb := moltbook.New(cfg.MoltbookBaseURL, cfg.MoltbookAPIKey)
	if err := mb.Ping(ctx); err != nil {
		log.Printf("moltbook ping: %v (continuing)", err)
	} else {
		log.Printf("moltbook ping: ok")
	}

	if SkipGemini() {
		log.Printf("tick: AGENT_SKIP_GEMINI set, skipping Gemini")
		return nil
	}

	gc := &gemini.Client{Key: cfg.GoogleAPIKey, Model: cfg.GeminiModel}
	reply, err := gc.GenerateText(ctx,
		"You are a health check for a scheduled agent. Reply with exactly: TICK_OK",
		"ping",
	)
	if err != nil {
		return fmt.Errorf("gemini: %w", err)
	}
	log.Printf("gemini tick reply: %s", strings.TrimSpace(truncate(reply, 200)))
	return nil
}

// SkipGemini reports whether AGENT_SKIP_GEMINI disables Gemini calls for this process.
func SkipGemini() bool {
	v := strings.TrimSpace(strings.ToLower(os.Getenv("AGENT_SKIP_GEMINI")))
	return v == "1" || v == "true" || v == "yes"
}

func truncate(s string, max int) string {
	if len(s) <= max {
		return s
	}
	return s[:max] + "…"
}

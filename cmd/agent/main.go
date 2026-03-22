package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"

	"moltbook-agent/internal/agent"
	"moltbook-agent/internal/config"
	"moltbook-agent/internal/telemetry"
)

func main() {
	mustRunOnCloudRun()

	ctx := context.Background()

	cfg, err := config.Load()
	if err != nil {
		log.Fatal(err)
	}

	shutdownTrace, err := telemetry.Setup(ctx, cfg.ServiceName, cfg.OTLPEndpoint, cfg.OTLPHeaders)
	if err != nil {
		log.Fatal(err)
	}
	defer func() {
		shCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		if err := shutdownTrace(shCtx); err != nil {
			log.Printf("trace shutdown: %v", err)
		}
	}()

	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})

	mux.HandleFunc("/ready", func(w http.ResponseWriter, r *http.Request) {
		// In-process checks only — avoid depending on Moltbook edge from cloud IPs for readiness.
		if cfg.GoogleAPIKey == "" && !agent.SkipGemini() {
			http.Error(w, "missing GOOGLE_API_KEY", http.StatusServiceUnavailable)
			return
		}
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})

	mux.HandleFunc("/cron/tick", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet && r.Method != http.MethodPost {
			w.Header().Set("Allow", "GET, POST")
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Minute)
		defer cancel()
		if err := agent.RunTick(ctx, cfg); err != nil {
			log.Printf("cron tick: %v", err)
			http.Error(w, "tick failed", http.StatusInternalServerError)
			return
		}
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})

	srv := &http.Server{
		Addr:              ":" + cfg.Port,
		Handler:           otelhttp.NewHandler(mux, "http.server"),
		ReadHeaderTimeout: 10 * time.Second,
	}

	go func() {
		log.Printf("listening on :%s", cfg.Port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatal(err)
		}
	}()

	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)
	<-sig

	shCtx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	if err := srv.Shutdown(shCtx); err != nil {
		log.Printf("server shutdown: %v", err)
	}
}

// mustRunOnCloudRun exits unless the container is running on Cloud Run (K_SERVICE is set by the platform).
func mustRunOnCloudRun() {
	if strings.TrimSpace(os.Getenv("K_SERVICE")) != "" {
		return
	}
	log.Fatal("refusing to start: run this image on Cloud Run only (missing K_SERVICE; see cloudbuild.yaml)")
}

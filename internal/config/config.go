package config

import (
	"fmt"
	"os"
	"strings"
)

// Config holds runtime settings loaded from the environment (no secrets in code).
type Config struct {
	Port            string
	GoogleAPIKey    string
	MoltbookAPIKey  string
	MoltbookBaseURL string
	GeminiModel     string

	OTLPEndpoint string
	OTLPHeaders  map[string]string
	ServiceName  string
}

// Load reads configuration from environment variables.
func Load() (Config, error) {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	cfg := Config{
		Port:            port,
		GoogleAPIKey:    os.Getenv("GOOGLE_API_KEY"),
		MoltbookAPIKey:  os.Getenv("MOLTBOOK_API_KEY"),
		MoltbookBaseURL: getenvDefault("MOLTBOOK_BASE_URL", "https://www.moltbook.com"),
		GeminiModel:     getenvDefault("GEMINI_MODEL", "gemini-2.0-flash"),

		OTLPEndpoint: strings.TrimSpace(os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT")),
		OTLPHeaders:  parseKeyValueList(os.Getenv("OTEL_EXPORTER_OTLP_HEADERS")),
		ServiceName:  getenvDefault("OTEL_SERVICE_NAME", "moltbook-agent"),
	}

	return cfg, nil
}

func getenvDefault(key, fallback string) string {
	if v := strings.TrimSpace(os.Getenv(key)); v != "" {
		return v
	}
	return fallback
}

// parseKeyValueList parses "k=v,k2=v2" as used by OTEL_EXPORTER_OTLP_HEADERS.
func parseKeyValueList(raw string) map[string]string {
	out := make(map[string]string)
	for _, part := range strings.Split(raw, ",") {
		part = strings.TrimSpace(part)
		if part == "" {
			continue
		}
		k, v, ok := strings.Cut(part, "=")
		if !ok {
			continue
		}
		out[strings.TrimSpace(k)] = strings.TrimSpace(v)
	}
	return out
}

// ValidateForLLM returns an error if Gemini cannot be called.
func (c Config) ValidateForLLM() error {
	if c.GoogleAPIKey == "" {
		return fmt.Errorf("GOOGLE_API_KEY is required for Gemini calls")
	}
	return nil
}

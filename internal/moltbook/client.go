package moltbook

import (
	"context"
	"fmt"
	"net/http"
	"strings"
	"time"
)

// Client is a thin holder for Moltbook credentials and HTTP transport.
// Extend this package with concrete endpoints as you integrate (posts, identity tokens, etc.).
type Client struct {
	HTTP    *http.Client
	BaseURL string
	APIKey  string
}

// New returns a client with sane defaults.
func New(baseURL, apiKey string) *Client {
	b := strings.TrimRight(strings.TrimSpace(baseURL), "/")
	if b == "" {
		b = "https://www.moltbook.com"
	}
	return &Client{
		HTTP: &http.Client{
			Timeout: 30 * time.Second,
		},
		BaseURL: b,
		APIKey:  strings.TrimSpace(apiKey),
	}
}

// Ping checks network reachability to the configured base URL (GET /).
// It does not validate the API key; use this as a cheap connectivity check only.
func (c *Client) Ping(ctx context.Context) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.BaseURL+"/", nil)
	if err != nil {
		return err
	}
	resp, err := c.http().Do(req)
	if err != nil {
		return err
	}
	resp.Body.Close()
	if resp.StatusCode >= 400 {
		return fmt.Errorf("moltbook ping: status %d", resp.StatusCode)
	}
	return nil
}

func (c *Client) http() *http.Client {
	if c.HTTP != nil {
		return c.HTTP
	}
	return http.DefaultClient
}

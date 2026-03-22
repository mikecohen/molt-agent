package gemini

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
)

// Client calls the Gemini API using an API key (Google AI Studio / Generative Language API).
type Client struct {
	HTTP *http.Client
	Key  string
	// Model is the model id, e.g. "gemini-2.0-flash".
	Model string
}

type generateRequest struct {
	SystemInstruction *contentObj `json:"systemInstruction,omitempty"`
	Contents          []content   `json:"contents"`
}

type content struct {
	Role  string      `json:"role,omitempty"`
	Parts []part      `json:"parts"`
}

type contentObj struct {
	Parts []part `json:"parts"`
}

type part struct {
	Text string `json:"text"`
}

type generateResponse struct {
	Candidates []struct {
		Content struct {
			Parts []part `json:"parts"`
		} `json:"content"`
	} `json:"candidates"`
	Error *struct {
		Message string `json:"message"`
		Code    int    `json:"code"`
	} `json:"error"`
}

// GenerateText runs a single user turn with an optional system instruction.
func (c *Client) GenerateText(ctx context.Context, systemInstruction, user string) (string, error) {
	if strings.TrimSpace(c.Key) == "" {
		return "", fmt.Errorf("gemini: missing API key")
	}
	model := c.Model
	if model == "" {
		model = "gemini-2.0-flash"
	}

	endpoint := fmt.Sprintf(
		"https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent",
		url.PathEscape(model),
	)
	q := url.Values{}
	q.Set("key", c.Key)
	u := endpoint + "?" + q.Encode()

	body := generateRequest{Contents: []content{{Role: "user", Parts: []part{{Text: user}}}}}
	if strings.TrimSpace(systemInstruction) != "" {
		body.SystemInstruction = &contentObj{Parts: []part{{Text: systemInstruction}}}
	}
	payload, err := json.Marshal(body)
	if err != nil {
		return "", err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, u, bytes.NewReader(payload))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")

	client := c.HTTP
	if client == nil {
		client = http.DefaultClient
	}
	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	raw, err := io.ReadAll(io.LimitReader(resp.Body, 8<<20))
	if err != nil {
		return "", err
	}

	var out generateResponse
	if err := json.Unmarshal(raw, &out); err != nil {
		return "", fmt.Errorf("gemini: decode response: %w; body=%s", err, truncate(string(raw), 512))
	}
	if out.Error != nil {
		return "", fmt.Errorf("gemini api: %s (code %d)", out.Error.Message, out.Error.Code)
	}
	if len(out.Candidates) == 0 || len(out.Candidates[0].Content.Parts) == 0 {
		return "", fmt.Errorf("gemini: empty candidates")
	}
	var b strings.Builder
	for _, p := range out.Candidates[0].Content.Parts {
		b.WriteString(p.Text)
	}
	return b.String(), nil
}

func truncate(s string, max int) string {
	if len(s) <= max {
		return s
	}
	return s[:max] + "…"
}

package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestGameIDFromURL(t *testing.T) {
	tests := []struct {
		name string
		raw  string
		want string
	}{
		{
			name: "encounter play url",
			raw:  "https://moscow.en.cx/gameengines/encounter/play/82420?json=1&lang=ru",
			want: "82420",
		},
		{
			name: "mobile encounter play url",
			raw:  "https://m.svk.en.cx/gameengines/encounter/play/82448?lang=ru",
			want: "82448",
		},
		{
			name: "missing game id",
			raw:  "https://svk.en.cx/home/?json=1",
			want: "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := gameIDFromURL(tt.raw); got != tt.want {
				t.Fatalf("gameIDFromURL(%q) = %q, want %q", tt.raw, got, tt.want)
			}
		})
	}
}

func TestSanitizeFilename(t *testing.T) {
	got := sanitizeFilename("2026-07-05 21:48:10_moscow.en.cx_game-82420_id/with spaces")
	want := "2026-07-05-21-48-10_moscow.en.cx_game-82420_id-with-spaces"
	if got != want {
		t.Fatalf("sanitizeFilename() = %q, want %q", got, want)
	}
}

func TestPrettyJSON(t *testing.T) {
	got := prettyJSON(`{"ok":true,"items":[1,2]}`)
	want := "{\n  \"ok\": true,\n  \"items\": [\n    1,\n    2\n  ]\n}"
	if got != want {
		t.Fatalf("prettyJSON() = %q, want %q", got, want)
	}

	if got := prettyJSON(`<html></html>`); got != "" {
		t.Fatalf("prettyJSON(invalid) = %q, want empty", got)
	}
}

func TestDefaultResponseView(t *testing.T) {
	tests := []struct {
		name        string
		contentType string
		hasJSON     bool
		want        string
	}{
		{name: "json", contentType: "application/json; charset=utf-8", hasJSON: true, want: "json"},
		{name: "json invalid body fallback", contentType: "application/json", hasJSON: false, want: "raw"},
		{name: "html", contentType: "text/html; charset=utf-8", hasJSON: false, want: "html"},
		{name: "other", contentType: "text/plain", hasJSON: false, want: "raw"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := defaultResponseView(tt.contentType, tt.hasJSON); got != tt.want {
				t.Fatalf("defaultResponseView(%q, %v) = %q, want %q", tt.contentType, tt.hasJSON, got, tt.want)
			}
		})
	}
}

func TestResponseContentTypePrefersHeader(t *testing.T) {
	entry := harEntry{
		Response: harResponse{
			Headers: []nameValue{{Name: "Content-Type", Value: "application/json"}},
			Content: harContent{MimeType: "text/html"},
		},
	}
	if got := responseContentType(entry); got != "application/json" {
		t.Fatalf("responseContentType() = %q, want header value", got)
	}
}

func TestHandleShareCreatesPublicURL(t *testing.T) {
	srv, sub := testServerWithSubmission(t)

	form := url.Values{"id": {sub.ID}}
	req := httptest.NewRequest(http.MethodPost, "/api/sessions/share", strings.NewReader(form.Encode()))
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("X-Forwarded-Proto", "https")
	req.Header.Set("X-Forwarded-Host", "enkapp-telemetry.exe.xyz")
	rec := httptest.NewRecorder()

	srv.handleShare(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("handleShare status = %d, body %q", rec.Code, rec.Body.String())
	}

	var payload shareResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &payload); err != nil {
		t.Fatalf("decode share response: %v", err)
	}
	if !strings.HasPrefix(payload.URL, "https://enkapp-telemetry.exe.xyz/share/") {
		t.Fatalf("share URL = %q, want public share URL", payload.URL)
	}
	if sub.ShareToken == "" {
		t.Fatal("ShareToken was not saved on submission")
	}

	data, err := os.ReadFile(filepath.Join(srv.dataDir, sub.ID+".json"))
	if err != nil {
		t.Fatalf("read saved submission: %v", err)
	}
	var saved submission
	if err := json.Unmarshal(data, &saved); err != nil {
		t.Fatalf("decode saved submission: %v", err)
	}
	if saved.ShareToken != sub.ShareToken {
		t.Fatalf("saved ShareToken = %q, want %q", saved.ShareToken, sub.ShareToken)
	}
}

func TestHandleSharedSessionDoesNotRequireAuth(t *testing.T) {
	srv, sub := testServerWithSubmission(t)
	sub.ShareToken = "0123456789abcdef0123456789abcdef"
	if err := srv.save(sub); err != nil {
		t.Fatalf("save shared submission: %v", err)
	}

	req := httptest.NewRequest(http.MethodGet, "/share/"+sub.ShareToken, nil)
	rec := httptest.NewRecorder()
	srv.handleSharedSession(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("shared session status = %d, body %q", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "moscow.en.cx") {
		t.Fatalf("shared session body does not include session content: %q", rec.Body.String())
	}
	if strings.Contains(rec.Body.String(), "/api/state") {
		t.Fatal("public shared session should not poll authenticated state endpoint")
	}
}

func TestHandleSharedSessionRawJSON(t *testing.T) {
	srv, sub := testServerWithSubmission(t)
	sub.ShareToken = "abcdef0123456789abcdef0123456789"
	if err := srv.save(sub); err != nil {
		t.Fatalf("save shared submission: %v", err)
	}

	req := httptest.NewRequest(http.MethodGet, "/share/"+sub.ShareToken+"?raw=1", nil)
	rec := httptest.NewRecorder()
	srv.handleSharedSession(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("shared raw status = %d, body %q", rec.Code, rec.Body.String())
	}
	if got := strings.TrimSpace(rec.Body.String()); got != `{"log":{"entries":[]}}` {
		t.Fatalf("shared raw body = %q", got)
	}
}

func TestHandleHARMergesSameClientGameUploads(t *testing.T) {
	srv := &server{
		dataDir:      t.TempDir(),
		viewUsername: "admin",
		viewPassword: "secret",
		sessions:     map[string]*submission{},
	}

	postHAR := func(url string, startedAt string) {
		t.Helper()
		body := `{"log":{"entries":[{"startedDateTime":"` + startedAt + `","request":{"method":"GET","url":"` + url + `"},"response":{"status":200},"timings":{}},{"startedDateTime":"` + startedAt + `","request":{"method":"POST","url":"` + url + `"},"response":{"status":200},"timings":{}}]}}`
		req := httptest.NewRequest(http.MethodPost, "/api/har", strings.NewReader(body))
		req.Header.Set("X-Enkapp-Domain", "encounter.exe.xyz")
		req.Header.Set("X-Enkapp-Login", "skrashevi")
		req.Header.Set("X-Enkapp-Version", "0.2")
		req.Header.Set("X-Enkapp-Build", "46")
		req.Header.Set("X-Forwarded-For", "46.138.250.50")
		rec := httptest.NewRecorder()

		srv.handleHAR(rec, req)
		if rec.Code != http.StatusCreated {
			t.Fatalf("handleHAR status = %d, body %q", rec.Code, rec.Body.String())
		}
	}

	url := "https://encounter.exe.xyz/gameengines/encounter/play/424242?json=1"
	postHAR(url, "2026-07-05T19:50:00Z")
	postHAR(url, "2026-07-05T19:50:01Z")

	if got := len(srv.sessions); got != 1 {
		t.Fatalf("session count = %d, want 1", got)
	}
	for _, sub := range srv.sessions {
		if sub.EntryCount != 4 {
			t.Fatalf("EntryCount = %d, want 4", sub.EntryCount)
		}
		if got := len(sub.HAR.Log.Entries); got != 4 {
			t.Fatalf("HAR entries = %d, want 4", got)
		}
	}
}

func testServerWithSubmission(t *testing.T) (*server, *submission) {
	t.Helper()
	srv := &server{
		dataDir:      t.TempDir(),
		viewUsername: "admin",
		viewPassword: "secret",
		sessions:     map[string]*submission{},
	}
	sub := &submission{
		ID:         "20260705T193538.453535512Z-79d334e5",
		ReceivedAt: time.Date(2026, 7, 5, 19, 35, 38, 0, time.UTC),
		Domain:     "moscow.en.cx",
		Login:      "tester",
		RemoteAddr: "127.0.0.1",
		EntryCount: 1,
		HAR: harFile{Log: harLog{Entries: []harEntry{{
			Request: harRequest{Method: http.MethodGet, URL: "https://moscow.en.cx/gameengines/encounter/play/82420?json=1"},
			Response: harResponse{
				Status:     http.StatusOK,
				StatusText: "OK",
				Headers:    []nameValue{{Name: "Content-Type", Value: "application/json"}},
				Content:    harContent{MimeType: "application/json", Text: `{"ok":true}`},
			},
			Time: 42,
		}}}},
		Raw: json.RawMessage(`{"log":{"entries":[]}}`),
	}
	if err := srv.save(sub); err != nil {
		t.Fatalf("save submission: %v", err)
	}
	return srv, sub
}

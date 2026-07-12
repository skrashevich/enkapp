package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
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

func TestHandleSessionRawJSON(t *testing.T) {
	srv, sub := testServerWithSubmission(t)

	req := httptest.NewRequest(http.MethodGet, "/sessions/"+sub.ID+"?raw=1", nil)
	rec := httptest.NewRecorder()
	srv.handleSession(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("private raw status = %d, body %q", rec.Code, rec.Body.String())
	}
	if got := strings.TrimSpace(rec.Body.String()); got != `{"log":{"entries":[]}}` {
		t.Fatalf("private raw body = %q", got)
	}
}

func TestDetailShellDoesNotContainBodies(t *testing.T) {
	srv, sub := testServerWithSubmission(t)
	sub.HAR.Log.Entries[0].Request.PostData = &harPostData{Text: "SECRET_REQUEST_BODY"}
	sub.HAR.Log.Entries[0].Response.Content.Text = `{"secret":"SECRET_RESPONSE_BODY"}`

	req := httptest.NewRequest(http.MethodGet, "/sessions/"+sub.ID, nil)
	rec := httptest.NewRecorder()
	srv.handleSession(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, body %q", rec.Code, rec.Body.String())
	}
	body := rec.Body.String()
	if strings.Contains(body, "SECRET_REQUEST_BODY") || strings.Contains(body, "SECRET_RESPONSE_BODY") {
		t.Fatal("detail shell eagerly contains an entry body")
	}
	if !strings.Contains(body, `data-lazy-url="/sessions/`+sub.ID+`"`) {
		t.Fatal("detail shell does not expose its private lazy URL")
	}
	for _, marker := range []string{`data-entry-list`, `data-entry-sentinel`, `data-load-more`} {
		if !strings.Contains(body, marker) {
			t.Fatalf("detail shell does not contain %s", marker)
		}
	}
}

func TestLargeDetailShellSizeDoesNotScaleWithBodies(t *testing.T) {
	srv, sub := testServerWithSubmission(t)
	const bodyMarker = "LARGE_BODY_MARKER_"
	sub.HAR.Log.Entries = nil
	for i := 0; i < 250; i++ {
		sub.HAR.Log.Entries = append(sub.HAR.Log.Entries, harEntry{
			Request: harRequest{
				Method: http.MethodGet,
				URL:    fmt.Sprintf("https://example.test/%d", i),
			},
			Response: harResponse{
				Status: http.StatusOK,
				Content: harContent{
					MimeType: "application/json",
					Text:     fmt.Sprintf(`{"body":"%s%d"}`, bodyMarker, i),
				},
			},
		})
	}
	sub.EntryCount = len(sub.HAR.Log.Entries)

	rec := httptest.NewRecorder()
	srv.handleSession(rec, httptest.NewRequest(http.MethodGet, "/sessions/"+sub.ID, nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d", rec.Code)
	}
	if strings.Contains(rec.Body.String(), bodyMarker) {
		t.Fatal("large detail shell contains response bodies")
	}
	if rec.Body.Len() > 50_000 {
		t.Fatalf("large detail shell size = %d bytes, want <= 50000", rec.Body.Len())
	}
}

func TestDetailPageContainsLazyLoadingController(t *testing.T) {
	srv, sub := testServerWithSubmission(t)
	req := httptest.NewRequest(http.MethodGet, "/sessions/"+sub.ID, nil)
	rec := httptest.NewRecorder()
	srv.handleSession(rec, req)
	body := rec.Body.String()

	for _, marker := range []string{
		"IntersectionObserver",
		"loadNextBatch",
		"loadEntryDetail",
		"activateBodyView",
		"data-load-more",
	} {
		if !strings.Contains(body, marker) {
			t.Fatalf("detail page does not contain %q", marker)
		}
	}
	if strings.Contains(body, "srcdoc=") {
		t.Fatal("detail shell eagerly contains srcdoc")
	}
}

func TestDetailPageHidesEntrySentinelForEmptySession(t *testing.T) {
	srv, sub := testServerWithSubmission(t)
	sub.EntryCount = 0
	sub.HAR.Log.Entries = nil

	req := httptest.NewRequest(http.MethodGet, "/sessions/"+sub.ID, nil)
	rec := httptest.NewRecorder()
	srv.handleSession(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, body %q", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), `data-entry-sentinel hidden`) {
		t.Fatal("empty session does not hide the entry sentinel")
	}
}

func TestDetailFragmentsSeparateSummariesRequestAndResponse(t *testing.T) {
	srv, sub := testServerWithSubmission(t)
	sub.HAR.Log.Entries[0].Request.PostData = &harPostData{Text: "SECRET_REQUEST_BODY"}
	sub.HAR.Log.Entries[0].Response.Content.Text = `{"secret":"SECRET_RESPONSE_BODY"}`

	assertFragment := func(query string, contains []string, excludes []string) {
		t.Helper()
		req := httptest.NewRequest(http.MethodGet, "/sessions/"+sub.ID+"?"+query, nil)
		rec := httptest.NewRecorder()
		srv.handleSession(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("%s status = %d, body %q", query, rec.Code, rec.Body.String())
		}
		body := rec.Body.String()
		for _, value := range contains {
			if !strings.Contains(body, value) {
				t.Fatalf("%s body does not contain %q", query, value)
			}
		}
		for _, value := range excludes {
			if strings.Contains(body, value) {
				t.Fatalf("%s body unexpectedly contains %q", query, value)
			}
		}
	}

	assertFragment(
		"view=entries&offset=0",
		[]string{
			`class="entry"`,
			`data-entry="0"`,
			`data-detail-kind="request"`,
			`data-detail-kind="response"`,
		},
		[]string{"SECRET_REQUEST_BODY", "SECRET_RESPONSE_BODY"},
	)
	assertFragment("view=request&entry=0", []string{"SECRET_REQUEST_BODY"}, []string{"SECRET_RESPONSE_BODY"})
	assertFragment(
		"view=response&entry=0",
		[]string{
			`data-body-viewer`,
			`data-body-panel="raw"`,
			`data-body-panel="json"`,
			"SECRET_RESPONSE_BODY",
		},
		[]string{"SECRET_REQUEST_BODY", "srcdoc="},
	)
}

func TestDetailFragmentsRejectInvalidParameters(t *testing.T) {
	srv, sub := testServerWithSubmission(t)
	for _, query := range []string{
		"view=entries&offset=-1",
		"view=entries&offset=2",
		"view=unknown",
	} {
		req := httptest.NewRequest(http.MethodGet, "/sessions/"+sub.ID+"?"+query, nil)
		rec := httptest.NewRecorder()
		srv.handleSession(rec, req)
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("%s status = %d, want 400", query, rec.Code)
		}
	}
}

func TestDetailEntryStatusContractPrivate(t *testing.T) {
	srv, sub := testServerWithSubmission(t)
	tests := []struct {
		name  string
		query string
		want  int
	}{
		{name: "missing request entry", query: "view=request", want: http.StatusBadRequest},
		{name: "missing response entry", query: "view=response", want: http.StatusBadRequest},
		{name: "malformed request entry", query: "view=request&entry=abc", want: http.StatusBadRequest},
		{name: "malformed response entry", query: "view=response&entry=abc", want: http.StatusBadRequest},
		{name: "negative request entry", query: "view=request&entry=-1", want: http.StatusNotFound},
		{name: "negative response entry", query: "view=response&entry=-1", want: http.StatusNotFound},
		{name: "overflow request entry", query: "view=request&entry=1", want: http.StatusNotFound},
		{name: "overflow response entry", query: "view=response&entry=1", want: http.StatusNotFound},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			rec := httptest.NewRecorder()
			req := httptest.NewRequest(http.MethodGet, "/sessions/"+sub.ID+"?"+tt.query, nil)
			srv.handleSession(rec, req)
			if rec.Code != tt.want {
				t.Fatalf("%s status = %d, want %d", tt.query, rec.Code, tt.want)
			}
		})
	}
}

func TestDetailEntryStatusContractPublic(t *testing.T) {
	srv, sub := testServerWithSubmission(t)
	sub.ShareToken = "0123456789abcdef0123456789abcdef"
	if err := srv.save(sub); err != nil {
		t.Fatalf("save shared submission: %v", err)
	}

	tests := []struct {
		name  string
		query string
		want  int
	}{
		{name: "missing request entry", query: "view=request", want: http.StatusBadRequest},
		{name: "missing response entry", query: "view=response", want: http.StatusBadRequest},
		{name: "malformed request entry", query: "view=request&entry=abc", want: http.StatusBadRequest},
		{name: "malformed response entry", query: "view=response&entry=abc", want: http.StatusBadRequest},
		{name: "negative request entry", query: "view=request&entry=-1", want: http.StatusNotFound},
		{name: "negative response entry", query: "view=response&entry=-1", want: http.StatusNotFound},
		{name: "overflow request entry", query: "view=request&entry=1", want: http.StatusNotFound},
		{name: "overflow response entry", query: "view=response&entry=1", want: http.StatusNotFound},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			rec := httptest.NewRecorder()
			req := httptest.NewRequest(http.MethodGet, "/share/"+sub.ShareToken+"?"+tt.query, nil)
			srv.handleSharedSession(rec, req)
			if rec.Code != tt.want {
				t.Fatalf("%s status = %d, want %d", tt.query, rec.Code, tt.want)
			}
		})
	}
}

func TestPrivateFragmentsRemainBehindBasicAuth(t *testing.T) {
	srv, sub := testServerWithSubmission(t)
	handler := srv.requireViewerAuth(srv.handleSession)
	req := httptest.NewRequest(http.MethodGet, "/sessions/"+sub.ID+"?view=entries&offset=0", nil)
	rec := httptest.NewRecorder()

	handler(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", rec.Code)
	}
}

func TestPublicFragmentsRequireValidShareToken(t *testing.T) {
	srv, sub := testServerWithSubmission(t)
	sub.ShareToken = "0123456789abcdef0123456789abcdef"

	valid := httptest.NewRecorder()
	srv.handleSharedSession(valid, httptest.NewRequest(
		http.MethodGet,
		"/share/"+sub.ShareToken+"?view=entries&offset=0",
		nil,
	))
	if valid.Code != http.StatusOK {
		t.Fatalf("valid token status = %d", valid.Code)
	}

	invalid := httptest.NewRecorder()
	srv.handleSharedSession(invalid, httptest.NewRequest(
		http.MethodGet,
		"/share/not-a-token?view=entries&offset=0",
		nil,
	))
	if invalid.Code != http.StatusNotFound {
		t.Fatalf("invalid token status = %d, want 404", invalid.Code)
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

func TestEntryBatchCapsAtFiftyAndPreservesOrder(t *testing.T) {
	sub := &submission{}
	for i := 0; i < 55; i++ {
		sub.HAR.Log.Entries = append(sub.HAR.Log.Entries, harEntry{
			Request: harRequest{
				Method: http.MethodGet,
				URL:    fmt.Sprintf("https://example.test/request/%d", i),
			},
			Response: harResponse{Status: http.StatusOK},
		})
	}

	first := entryBatch(sub, 0)
	if got := len(first.Entries); got != 50 {
		t.Fatalf("first batch length = %d, want 50", got)
	}
	if first.Entries[0].Index != 1 || first.Entries[49].Index != 50 {
		t.Fatalf("first batch indexes = %d..%d, want 1..50", first.Entries[0].Index, first.Entries[49].Index)
	}
	if first.NextOffset != 50 || !first.HasMore {
		t.Fatalf("first batch continuation = (%d, %v), want (50, true)", first.NextOffset, first.HasMore)
	}

	second := entryBatch(sub, first.NextOffset)
	if got := len(second.Entries); got != 5 {
		t.Fatalf("second batch length = %d, want 5", got)
	}
	if second.Entries[0].Index != 51 || second.Entries[4].Index != 55 {
		t.Fatalf("second batch indexes = %d..%d, want 51..55", second.Entries[0].Index, second.Entries[4].Index)
	}
	if second.NextOffset != 55 || second.HasMore {
		t.Fatalf("second batch continuation = (%d, %v), want (55, false)", second.NextOffset, second.HasMore)
	}
}

func TestParseEntryOffset(t *testing.T) {
	tests := []struct {
		raw     string
		total   int
		want    int
		wantErr bool
	}{
		{raw: "", total: 10, want: 0},
		{raw: "0", total: 10, want: 0},
		{raw: "10", total: 10, want: 10},
		{raw: "-1", total: 10, wantErr: true},
		{raw: "11", total: 10, wantErr: true},
		{raw: "abc", total: 10, wantErr: true},
	}
	for _, tt := range tests {
		req := httptest.NewRequest(http.MethodGet, "/?offset="+url.QueryEscape(tt.raw), nil)
		got, err := parseEntryOffset(req, tt.total)
		if (err != nil) != tt.wantErr {
			t.Fatalf("offset %q error = %v, wantErr %v", tt.raw, err, tt.wantErr)
		}
		if err == nil && got != tt.want {
			t.Fatalf("offset %q = %d, want %d", tt.raw, got, tt.want)
		}
	}
}

func TestParseEntryIndex(t *testing.T) {
	tests := []struct {
		raw     string
		total   int
		want    int
		wantErr bool
	}{
		{raw: "0", total: 2, want: 0},
		{raw: "1", total: 2, want: 1},
		{raw: "", total: 2, wantErr: true},
		{raw: "-1", total: 2, wantErr: true},
		{raw: "2", total: 2, wantErr: true},
		{raw: "abc", total: 2, wantErr: true},
	}
	for _, tt := range tests {
		req := httptest.NewRequest(http.MethodGet, "/?entry="+url.QueryEscape(tt.raw), nil)
		got, err := parseEntryIndex(req, tt.total)
		if (err != nil) != tt.wantErr {
			t.Fatalf("entry %q error = %v, wantErr %v", tt.raw, err, tt.wantErr)
		}
		if err == nil && got != tt.want {
			t.Fatalf("entry %q = %d, want %d", tt.raw, got, tt.want)
		}
	}
}

func TestSnapshotSubmissionForDetailCopiesEntriesWithoutRaw(t *testing.T) {
	original := &submission{
		ID:         "snapshot-source",
		ReceivedAt: time.Date(2026, 7, 12, 5, 0, 0, 0, time.UTC),
		EntryCount: 1,
		HAR: harFile{Log: harLog{Entries: []harEntry{{
			Request: harRequest{
				Method: http.MethodGet,
				URL:    "https://example.test/original",
			},
			Response: harResponse{Status: http.StatusOK},
		}}}},
		Raw: json.RawMessage(`{"log":{"entries":[{"url":"https://example.test/original"}]}}`),
	}

	snapshot := snapshotSubmission(original, false)

	original.HAR.Log.Entries[0].Request.URL = "https://example.test/mutated"
	original.HAR.Log.Entries = append(original.HAR.Log.Entries, harEntry{
		Request:  harRequest{Method: http.MethodGet, URL: "https://example.test/added"},
		Response: harResponse{Status: http.StatusCreated},
	})

	if got := len(snapshot.HAR.Log.Entries); got != 1 {
		t.Fatalf("snapshot entry count = %d, want 1", got)
	}
	if got := snapshot.HAR.Log.Entries[0].Request.URL; got != "https://example.test/original" {
		t.Fatalf("snapshot first URL = %q, want original value", got)
	}
	if snapshot.Raw != nil {
		t.Fatalf("detail snapshot retained %d raw bytes, want none", len(snapshot.Raw))
	}
}

func TestSnapshotSubmissionForRawCopiesRawWithoutEntries(t *testing.T) {
	original := &submission{
		ID:         "snapshot-source",
		ReceivedAt: time.Date(2026, 7, 12, 5, 0, 0, 0, time.UTC),
		EntryCount: 1,
		HAR: harFile{Log: harLog{Entries: []harEntry{{
			Request:  harRequest{Method: http.MethodGet, URL: "https://example.test/original"},
			Response: harResponse{Status: http.StatusOK},
		}}}},
		Raw: json.RawMessage(`{"log":{"entries":[{"url":"https://example.test/original"}]}}`),
	}

	snapshot := snapshotSubmission(original, true)

	original.Raw[0] = 'X'
	original.Raw = append(original.Raw, []byte(`{"extra":true}`)...)

	if snapshot.HAR.Log.Entries != nil {
		t.Fatalf("raw snapshot retained %d entries, want none", len(snapshot.HAR.Log.Entries))
	}
	if got := string(snapshot.Raw); got != `{"log":{"entries":[{"url":"https://example.test/original"}]}}` {
		t.Fatalf("snapshot raw = %q, want original bytes", got)
	}
}

func TestHandlersConcurrentWithMerge(t *testing.T) {
	srv, sub := testServerWithSubmission(t)
	sub.ShareToken = "fedcba9876543210fedcba9876543210"
	sub.Version = "0.2"
	sub.Build = "46"
	if err := srv.save(sub); err != nil {
		t.Fatalf("save shared submission: %v", err)
	}

	baseReceivedAt := sub.ReceivedAt
	domain := sub.Domain
	login := sub.Login
	version := sub.Version
	build := sub.Build
	remoteAddr := sub.RemoteAddr
	shareToken := sub.ShareToken
	const rounds = 150
	start := make(chan struct{})
	errCh := make(chan error, 4)
	var wg sync.WaitGroup

	wg.Add(1)
	go func() {
		defer wg.Done()
		<-start
		for i := 0; i < rounds; i++ {
			incoming := &submission{
				ID:         fmt.Sprintf("merge-%03d", i),
				ReceivedAt: baseReceivedAt.Add(time.Duration(i+1) * time.Second),
				Domain:     domain,
				Login:      login,
				Version:    version,
				Build:      build,
				RemoteAddr: remoteAddr,
				EntryCount: 1,
				HAR: harFile{Log: harLog{Entries: []harEntry{{
					Request: harRequest{
						Method: http.MethodGet,
						URL:    "https://moscow.en.cx/gameengines/encounter/play/82420?json=1&merge=" + fmt.Sprintf("%d", i),
					},
					Response: harResponse{Status: http.StatusOK},
				}}}},
				Raw: json.RawMessage(`{"log":{"entries":[{"merge":true}]}}`),
			}
			if _, err := srv.saveWithMerge(incoming, sessionMergeWindow); err != nil {
				errCh <- fmt.Errorf("saveWithMerge: %w", err)
				return
			}
		}
	}()

	wg.Add(1)
	go func() {
		defer wg.Done()
		<-start
		for i := 0; i < rounds; i++ {
			rec := httptest.NewRecorder()
			req := httptest.NewRequest(http.MethodGet, "/sessions/"+sub.ID+"?view=request&entry=0", nil)
			srv.handleSession(rec, req)
			if rec.Code != http.StatusOK {
				errCh <- fmt.Errorf("private detail status = %d, body %q", rec.Code, rec.Body.String())
				return
			}
		}
	}()

	wg.Add(1)
	go func() {
		defer wg.Done()
		<-start
		for i := 0; i < rounds; i++ {
			rec := httptest.NewRecorder()
			req := httptest.NewRequest(http.MethodGet, "/share/"+shareToken+"?view=response&entry=0", nil)
			srv.handleSharedSession(rec, req)
			if rec.Code != http.StatusOK {
				errCh <- fmt.Errorf("public detail status = %d, body %q", rec.Code, rec.Body.String())
				return
			}
		}
	}()

	wg.Add(1)
	go func() {
		defer wg.Done()
		<-start
		for i := 0; i < rounds; i++ {
			rec := httptest.NewRecorder()
			req := httptest.NewRequest(http.MethodGet, "/share/"+shareToken+"?raw=1", nil)
			srv.handleSharedSession(rec, req)
			if rec.Code != http.StatusOK {
				errCh <- fmt.Errorf("public raw status = %d, body %q", rec.Code, rec.Body.String())
				return
			}
			if !json.Valid(rec.Body.Bytes()) {
				errCh <- fmt.Errorf("public raw response is invalid JSON: %q", rec.Body.String())
				return
			}
		}
	}()

	close(start)
	wg.Wait()
	close(errCh)
	for err := range errCh {
		if err != nil {
			t.Fatal(err)
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

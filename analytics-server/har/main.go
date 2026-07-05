package main

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"html/template"
	"io"
	"log"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

const maxHARBytes = 25 << 20

type server struct {
	mu       sync.RWMutex
	dataDir  string
	sessions map[string]*submission
}

type submission struct {
	ID         string          `json:"id"`
	ReceivedAt time.Time       `json:"received_at"`
	Domain     string          `json:"domain"`
	Version    string          `json:"version"`
	Build      string          `json:"build"`
	RemoteAddr string          `json:"remote_addr"`
	EntryCount int             `json:"entry_count"`
	HAR        harFile         `json:"har"`
	Raw        json.RawMessage `json:"raw"`
}

type harFile struct {
	Log harLog `json:"log"`
}

type harLog struct {
	Version string     `json:"version"`
	Creator harCreator `json:"creator"`
	Entries []harEntry `json:"entries"`
}

type harCreator struct {
	Name    string `json:"name"`
	Version string `json:"version"`
}

type harEntry struct {
	StartedDateTime string      `json:"startedDateTime"`
	Time            float64     `json:"time"`
	Request         harRequest  `json:"request"`
	Response        harResponse `json:"response"`
	Timings         harTimings  `json:"timings"`
	Cache           any         `json:"cache"`
	ServerIPAddress string      `json:"serverIPAddress"`
	Connection      string      `json:"connection"`
	Comment         string      `json:"comment"`
}

type harRequest struct {
	Method      string       `json:"method"`
	URL         string       `json:"url"`
	HTTPVersion string       `json:"httpVersion"`
	Cookies     []nameValue  `json:"cookies"`
	Headers     []nameValue  `json:"headers"`
	QueryString []nameValue  `json:"queryString"`
	PostData    *harPostData `json:"postData"`
	HeadersSize int          `json:"headersSize"`
	BodySize    int          `json:"bodySize"`
}

type harPostData struct {
	MimeType string      `json:"mimeType"`
	Text     string      `json:"text"`
	Params   []nameValue `json:"params"`
}

type harResponse struct {
	Status      int         `json:"status"`
	StatusText  string      `json:"statusText"`
	HTTPVersion string      `json:"httpVersion"`
	Cookies     []nameValue `json:"cookies"`
	Headers     []nameValue `json:"headers"`
	Content     harContent  `json:"content"`
	RedirectURL string      `json:"redirectURL"`
	HeadersSize int         `json:"headersSize"`
	BodySize    int         `json:"bodySize"`
}

type harContent struct {
	Size     int    `json:"size"`
	MimeType string `json:"mimeType"`
	Text     string `json:"text"`
	Encoding string `json:"encoding"`
}

type harTimings struct {
	Blocked float64 `json:"blocked"`
	DNS     float64 `json:"dns"`
	Connect float64 `json:"connect"`
	Send    float64 `json:"send"`
	Wait    float64 `json:"wait"`
	Receive float64 `json:"receive"`
	SSL     float64 `json:"ssl"`
}

type nameValue struct {
	Name  string `json:"name"`
	Value string `json:"value"`
}

type listItem struct {
	ID         string
	ReceivedAt string
	Domain     string
	Version    string
	RemoteAddr string
	EntryCount int
	FirstURL   string
}

type indexPage struct {
	Items []listItem
	State stateResponse
}

type detailPage struct {
	Session *submission
	Entries []entryView
	State   stateResponse
}

type stateResponse struct {
	Count            int    `json:"count"`
	LatestID         string `json:"latest_id"`
	LatestReceivedAt string `json:"latest_received_at"`
	LatestDomain     string `json:"latest_domain"`
	LatestFirstURL   string `json:"latest_first_url"`
}

type entryView struct {
	Index           int
	Method          string
	URL             string
	URLPath         string
	Status          int
	StatusText      string
	Time            string
	StartedAt       string
	RequestHeaders  []nameValue
	ResponseHeaders []nameValue
	QueryString     []nameValue
	RequestBody     string
	ResponseBody    string
}

func main() {
	addr := env("ADDR", ":8080")
	dataDir := env("DATA_DIR", "data")

	srv := &server{
		dataDir:  dataDir,
		sessions: map[string]*submission{},
	}
	if err := os.MkdirAll(dataDir, 0o755); err != nil {
		log.Fatal(err)
	}
	if err := srv.load(); err != nil {
		log.Fatal(err)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/", srv.handleIndex)
	mux.HandleFunc("/sessions/", srv.handleSession)
	mux.HandleFunc("/api/state", srv.handleState)
	mux.HandleFunc("/api/har", srv.handleHAR)

	log.Printf("har telemetry listening on %s, data_dir=%s", addr, dataDir)
	log.Fatal(http.ListenAndServe(addr, logRequest(mux)))
}

func (s *server) handleHAR(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, maxHARBytes))
	if err != nil {
		http.Error(w, "HAR body is too large", http.StatusRequestEntityTooLarge)
		return
	}
	defer r.Body.Close()

	var har harFile
	if err := json.Unmarshal(body, &har); err != nil {
		http.Error(w, "invalid HAR JSON", http.StatusBadRequest)
		return
	}
	if len(har.Log.Entries) == 0 {
		http.Error(w, "HAR has no entries", http.StatusBadRequest)
		return
	}

	now := time.Now().UTC()
	sub := &submission{
		ID:         newID(now),
		ReceivedAt: now,
		Domain:     r.Header.Get("X-Enkapp-Domain"),
		Version:    r.Header.Get("X-Enkapp-Version"),
		Build:      r.Header.Get("X-Enkapp-Build"),
		RemoteAddr: clientIP(r),
		EntryCount: len(har.Log.Entries),
		HAR:        har,
		Raw:        append(json.RawMessage(nil), body...),
	}
	if countHeader := r.Header.Get("X-Enkapp-HAR-Entry-Count"); countHeader != "" {
		if count, err := strconv.Atoi(countHeader); err == nil && count > 0 {
			sub.EntryCount = count
		}
	}

	if err := s.save(sub); err != nil {
		log.Printf("save HAR: %v", err)
		http.Error(w, "failed to save HAR", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	_ = json.NewEncoder(w).Encode(map[string]any{
		"id":      sub.ID,
		"entries": len(har.Log.Entries),
	})
}

func (s *server) handleIndex(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}
	s.mu.RLock()
	items := make([]listItem, 0, len(s.sessions))
	for _, sub := range s.sessions {
		firstURL := ""
		if len(sub.HAR.Log.Entries) > 0 {
			firstURL = compactURL(sub.HAR.Log.Entries[0].Request.URL)
		}
		items = append(items, listItem{
			ID:         sub.ID,
			ReceivedAt: sub.ReceivedAt.Local().Format("2006-01-02 15:04:05"),
			Domain:     emptyDash(sub.Domain),
			Version:    appVersion(sub),
			RemoteAddr: sub.RemoteAddr,
			EntryCount: sub.EntryCount,
			FirstURL:   firstURL,
		})
	}
	s.mu.RUnlock()
	sort.Slice(items, func(i, j int) bool { return items[i].ID > items[j].ID })

	render(w, indexTemplate, indexPage{
		Items: items,
		State: s.state(),
	})
}

func (s *server) handleSession(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimPrefix(r.URL.Path, "/sessions/")
	if id == "" || strings.Contains(id, "/") {
		http.NotFound(w, r)
		return
	}

	s.mu.RLock()
	sub := s.sessions[id]
	s.mu.RUnlock()
	if sub == nil {
		http.NotFound(w, r)
		return
	}

	if r.URL.Query().Get("raw") == "1" {
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		_, _ = w.Write(sub.Raw)
		return
	}

	page := detailPage{Session: sub, State: s.state()}
	for i, entry := range sub.HAR.Log.Entries {
		page.Entries = append(page.Entries, entryView{
			Index:           i + 1,
			Method:          entry.Request.Method,
			URL:             entry.Request.URL,
			URLPath:         compactURL(entry.Request.URL),
			Status:          entry.Response.Status,
			StatusText:      entry.Response.StatusText,
			Time:            fmt.Sprintf("%.0f ms", entry.Time),
			StartedAt:       entry.StartedDateTime,
			RequestHeaders:  entry.Request.Headers,
			ResponseHeaders: entry.Response.Headers,
			QueryString:     entry.Request.QueryString,
			RequestBody:     truncate(entry.requestBody(), 20_000),
			ResponseBody:    truncate(entry.Response.Content.Text, 40_000),
		})
	}
	render(w, detailTemplate, page)
}

func (s *server) handleState(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", http.MethodGet)
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	_ = json.NewEncoder(w).Encode(s.state())
}

func (s *server) state() stateResponse {
	s.mu.RLock()
	defer s.mu.RUnlock()

	var latest *submission
	for _, sub := range s.sessions {
		if latest == nil || sub.ID > latest.ID {
			latest = sub
		}
	}
	result := stateResponse{Count: len(s.sessions)}
	if latest == nil {
		return result
	}
	result.LatestID = latest.ID
	result.LatestReceivedAt = latest.ReceivedAt.Local().Format("2006-01-02 15:04:05")
	result.LatestDomain = emptyDash(latest.Domain)
	if len(latest.HAR.Log.Entries) > 0 {
		result.LatestFirstURL = compactURL(latest.HAR.Log.Entries[0].Request.URL)
	}
	return result
}

func (e harEntry) requestBody() string {
	if e.Request.PostData == nil {
		return ""
	}
	if e.Request.PostData.Text != "" {
		return e.Request.PostData.Text
	}
	if len(e.Request.PostData.Params) == 0 {
		return ""
	}
	values := url.Values{}
	for _, param := range e.Request.PostData.Params {
		values.Add(param.Name, param.Value)
	}
	return values.Encode()
}

func (s *server) load() error {
	entries, err := os.ReadDir(s.dataDir)
	if err != nil {
		return err
	}
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".json") {
			continue
		}
		data, err := os.ReadFile(filepath.Join(s.dataDir, entry.Name()))
		if err != nil {
			return err
		}
		var sub submission
		if err := json.Unmarshal(data, &sub); err != nil {
			return err
		}
		if sub.ID == "" {
			continue
		}
		s.sessions[sub.ID] = &sub
	}
	return nil
}

func (s *server) save(sub *submission) error {
	data, err := json.MarshalIndent(sub, "", "  ")
	if err != nil {
		return err
	}
	name := filepath.Join(s.dataDir, sub.ID+".json")
	tmp := name + ".tmp"
	if err := os.WriteFile(tmp, data, 0o600); err != nil {
		return err
	}
	if err := os.Rename(tmp, name); err != nil {
		return err
	}
	s.mu.Lock()
	s.sessions[sub.ID] = sub
	s.mu.Unlock()
	return nil
}

func render(w http.ResponseWriter, tmpl *template.Template, data any) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	if err := tmpl.Execute(w, data); err != nil {
		log.Printf("render: %v", err)
	}
}

func clientIP(r *http.Request) string {
	if forwarded := r.Header.Get("X-Forwarded-For"); forwarded != "" {
		return strings.TrimSpace(strings.Split(forwarded, ",")[0])
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err == nil {
		return host
	}
	return r.RemoteAddr
}

func compactURL(raw string) string {
	parsed, err := url.Parse(raw)
	if err != nil || parsed.Host == "" {
		return raw
	}
	result := parsed.Host + parsed.Path
	if parsed.RawQuery != "" {
		result += "?" + parsed.RawQuery
	}
	return result
}

func appVersion(sub *submission) string {
	if sub.Version == "" && sub.Build == "" {
		return "-"
	}
	if sub.Build == "" {
		return sub.Version
	}
	if sub.Version == "" {
		return sub.Build
	}
	return sub.Version + " (" + sub.Build + ")"
}

func emptyDash(value string) string {
	if strings.TrimSpace(value) == "" {
		return "-"
	}
	return value
}

func truncate(value string, limit int) string {
	if len(value) <= limit {
		return value
	}
	return value[:limit] + "\n... truncated ..."
}

func newID(now time.Time) string {
	var buf [4]byte
	if _, err := rand.Read(buf[:]); err != nil {
		panic(errors.Join(errors.New("random id"), err))
	}
	return now.Format("20060102T150405.000000000Z") + "-" + hex.EncodeToString(buf[:])
}

func env(name, fallback string) string {
	if value := os.Getenv(name); value != "" {
		return value
	}
	return fallback
}

func logRequest(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		log.Printf("%s %s from %s", r.Method, r.URL.RequestURI(), clientIP(r))
		next.ServeHTTP(w, r)
	})
}

var indexTemplate = template.Must(template.New("index").Parse(pagePrefix + `
<main data-page="index" data-latest-id="{{.State.LatestID}}">
  <header class="top">
    <div>
      <h1>enkapp HAR telemetry</h1>
      <p>Received HAR captures from mobile clients. <span id="live-status">Live updates enabled.</span></p>
    </div>
  </header>
  <table>
    <thead>
      <tr>
        <th>Received</th>
        <th>Domain</th>
        <th>Version</th>
        <th>Entries</th>
        <th>First request</th>
        <th>Client</th>
      </tr>
    </thead>
    <tbody>
      {{range .Items}}
      <tr>
        <td><a href="/sessions/{{.ID}}">{{.ReceivedAt}}</a></td>
        <td>{{.Domain}}</td>
        <td>{{.Version}}</td>
        <td>{{.EntryCount}}</td>
        <td class="url">{{.FirstURL}}</td>
        <td>{{.RemoteAddr}}</td>
      </tr>
      {{else}}
      <tr><td colspan="6" class="empty">No HAR captures yet.</td></tr>
      {{end}}
    </tbody>
  </table>
</main>
<script>
(() => {
  const root = document.querySelector("main[data-page='index']");
  const status = document.getElementById("live-status");
  let latestID = root?.dataset.latestId || "";

  async function poll() {
    try {
      const response = await fetch("/api/state", { cache: "no-store" });
      if (!response.ok) return;
      const state = await response.json();
      if (state.latest_id && latestID && state.latest_id !== latestID) {
        status.textContent = "New capture received. Refreshing...";
        window.location.reload();
        return;
      }
      if (!latestID && state.latest_id) {
        window.location.reload();
        return;
      }
      status.textContent = "Live updates enabled.";
    } catch {
      status.textContent = "Live updates temporarily unavailable.";
    }
  }

  setInterval(poll, 2000);
})();
</script>
` + pageSuffix))

var detailTemplate = template.Must(template.New("detail").Parse(pagePrefix + `
<main data-page="detail" data-latest-id="{{.State.LatestID}}" data-current-id="{{.Session.ID}}">
  <div id="new-capture-banner" class="banner" hidden>
    <span id="new-capture-text"></span>
    <a id="new-capture-link" href="/">Open</a>
  </div>
  <p><a href="/">Back to captures</a> · <a href="/sessions/{{.Session.ID}}?raw=1">Raw JSON</a></p>
  <header class="top">
    <div>
      <h1>{{.Session.Domain}}</h1>
      <p>{{.Session.ReceivedAt.Local.Format "2006-01-02 15:04:05"}} · {{.Session.RemoteAddr}} · {{.Session.EntryCount}} entries</p>
    </div>
  </header>
  {{range .Entries}}
  <section class="entry">
    <div class="summary">
      <span class="method">{{.Method}}</span>
      <span class="status status-{{.Status}}">{{.Status}} {{.StatusText}}</span>
      <span class="time">{{.Time}}</span>
    </div>
    <h2>{{.URLPath}}</h2>
    <p class="full-url">{{.URL}}</p>
    <details>
      <summary>Request</summary>
      {{if .QueryString}}
      <h3>Query</h3>
      <dl>{{range .QueryString}}<dt>{{.Name}}</dt><dd>{{.Value}}</dd>{{end}}</dl>
      {{end}}
      <h3>Headers</h3>
      <dl>{{range .RequestHeaders}}<dt>{{.Name}}</dt><dd>{{.Value}}</dd>{{else}}<dd>-</dd>{{end}}</dl>
      {{if .RequestBody}}<h3>Body</h3><pre>{{.RequestBody}}</pre>{{end}}
    </details>
    <details>
      <summary>Response</summary>
      <h3>Headers</h3>
      <dl>{{range .ResponseHeaders}}<dt>{{.Name}}</dt><dd>{{.Value}}</dd>{{else}}<dd>-</dd>{{end}}</dl>
      {{if .ResponseBody}}<h3>Body</h3><pre>{{.ResponseBody}}</pre>{{end}}
    </details>
  </section>
  {{end}}
</main>
<script>
(() => {
  const root = document.querySelector("main[data-page='detail']");
  const banner = document.getElementById("new-capture-banner");
  const bannerText = document.getElementById("new-capture-text");
  const bannerLink = document.getElementById("new-capture-link");
  let latestID = root?.dataset.latestId || "";
  const currentID = root?.dataset.currentId || "";

  async function poll() {
    try {
      const response = await fetch("/api/state", { cache: "no-store" });
      if (!response.ok) return;
      const state = await response.json();
      if (!state.latest_id || state.latest_id === latestID || state.latest_id === currentID) {
        return;
      }
      latestID = state.latest_id;
      bannerText.textContent = "New capture from " + (state.latest_domain || "unknown domain") + ": " + (state.latest_first_url || state.latest_id);
      bannerLink.href = "/sessions/" + state.latest_id;
      banner.hidden = false;
    } catch {
      // Keep the current capture readable if live updates fail.
    }
  }

  setInterval(poll, 2000);
})();
</script>
` + pageSuffix))

const pagePrefix = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>enkapp HAR telemetry</title>
<style>
:root { color-scheme: light dark; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
body { margin: 0; background: #0f1115; color: #e7e9ee; }
main { width: min(1180px, calc(100vw - 32px)); margin: 0 auto; padding: 28px 0 48px; }
a { color: #8ab4ff; text-decoration: none; }
a:hover { text-decoration: underline; }
.top { display: flex; justify-content: space-between; align-items: flex-end; gap: 16px; margin-bottom: 20px; }
h1 { margin: 0 0 6px; font-size: 28px; }
h2 { margin: 10px 0 4px; font-size: 18px; overflow-wrap: anywhere; }
h3 { margin: 16px 0 8px; font-size: 14px; color: #aeb6c8; }
p { margin: 0; color: #aeb6c8; }
table { width: 100%; border-collapse: collapse; background: #171a21; border: 1px solid #2a2f3a; }
th, td { padding: 10px 12px; border-bottom: 1px solid #2a2f3a; text-align: left; vertical-align: top; }
th { color: #aeb6c8; font-size: 13px; font-weight: 600; }
.url, .full-url { overflow-wrap: anywhere; }
.empty { color: #aeb6c8; text-align: center; padding: 28px; }
.banner { position: sticky; top: 0; z-index: 2; display: flex; justify-content: space-between; gap: 12px; align-items: center; margin-bottom: 14px; padding: 10px 12px; background: #203d2d; color: #d6f6dc; border: 1px solid #3f8152; border-radius: 8px; }
.banner[hidden] { display: none; }
.entry { background: #171a21; border: 1px solid #2a2f3a; border-radius: 8px; padding: 14px; margin: 14px 0; }
.summary { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; }
.method, .status, .time { border-radius: 6px; padding: 3px 8px; font: 600 13px ui-monospace, SFMono-Regular, Menlo, monospace; }
.method { background: #27364f; color: #b8d3ff; }
.status { background: #463123; color: #ffd1a8; }
.status-200, .status-201, .status-204, .status-302 { background: #203d2d; color: #a8e6b1; }
.time { background: #262b35; color: #d9deea; }
details { margin-top: 10px; border-top: 1px solid #2a2f3a; padding-top: 10px; }
summary { cursor: pointer; color: #d9deea; font-weight: 600; }
dl { display: grid; grid-template-columns: minmax(140px, 260px) 1fr; gap: 6px 12px; margin: 0; }
dt { color: #aeb6c8; overflow-wrap: anywhere; }
dd { margin: 0; overflow-wrap: anywhere; }
pre { margin: 0; padding: 12px; overflow: auto; max-height: 520px; background: #0b0d12; border: 1px solid #2a2f3a; border-radius: 6px; white-space: pre-wrap; }
@media (max-width: 760px) {
  table, thead, tbody, tr, th, td { display: block; }
  thead { display: none; }
  tr { border-bottom: 1px solid #2a2f3a; }
  dl { grid-template-columns: 1fr; }
}
</style>
</head>
<body>`

const pageSuffix = `</body></html>`

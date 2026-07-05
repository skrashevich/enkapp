package main

import (
	"archive/zip"
	"crypto/rand"
	"crypto/subtle"
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
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

const maxHARBytes = 25 << 20

type server struct {
	mu           sync.RWMutex
	dataDir      string
	viewUsername string
	viewPassword string
	sessions     map[string]*submission
}

type submission struct {
	ID         string          `json:"id"`
	ReceivedAt time.Time       `json:"received_at"`
	Domain     string          `json:"domain"`
	Login      string          `json:"login"`
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
	GameID     string
	Domain     string
	Login      string
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
	viewUsername := env("VIEW_USERNAME", "admin")
	viewPassword := os.Getenv("VIEW_PASSWORD")
	if viewPassword == "" {
		log.Print("VIEW_PASSWORD is not set; HAR viewer endpoints will refuse access")
	}

	srv := &server{
		dataDir:      dataDir,
		viewUsername: viewUsername,
		viewPassword: viewPassword,
		sessions:     map[string]*submission{},
	}
	if err := os.MkdirAll(dataDir, 0o755); err != nil {
		log.Fatal(err)
	}
	if err := srv.load(); err != nil {
		log.Fatal(err)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/", srv.requireViewerAuth(srv.handleIndex))
	mux.HandleFunc("/sessions/", srv.requireViewerAuth(srv.handleSession))
	mux.HandleFunc("/api/state", srv.requireViewerAuth(srv.handleState))
	mux.HandleFunc("/api/sessions/archive", srv.requireViewerAuth(srv.handleArchive))
	mux.HandleFunc("/api/har", srv.handleHAR)

	log.Printf("har telemetry listening on %s, data_dir=%s", addr, dataDir)
	log.Fatal(http.ListenAndServe(addr, logRequest(mux)))
}

func (s *server) requireViewerAuth(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if s.viewPassword == "" {
			http.Error(w, "HAR viewer authentication is not configured", http.StatusServiceUnavailable)
			return
		}

		username, password, ok := r.BasicAuth()
		if !ok || !constantTimeEqual(username, s.viewUsername) || !constantTimeEqual(password, s.viewPassword) {
			w.Header().Set("WWW-Authenticate", `Basic realm="enkapp HAR telemetry", charset="UTF-8"`)
			http.Error(w, "authentication required", http.StatusUnauthorized)
			return
		}

		next(w, r)
	}
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
		Login:      strings.TrimSpace(r.Header.Get("X-Enkapp-Login")),
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
			GameID:     emptyDash(gameID(sub)),
			Domain:     emptyDash(sub.Domain),
			Login:      emptyDash(sub.Login),
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

func (s *server) handleArchive(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if err := r.ParseForm(); err != nil {
		http.Error(w, "invalid form", http.StatusBadRequest)
		return
	}
	ids := r.Form["ids"]
	if len(ids) == 0 {
		http.Error(w, "no sessions selected", http.StatusBadRequest)
		return
	}

	s.mu.RLock()
	subs := make([]*submission, 0, len(ids))
	for _, id := range ids {
		sub := s.sessions[id]
		if sub == nil {
			s.mu.RUnlock()
			http.Error(w, "unknown session: "+id, http.StatusNotFound)
			return
		}
		subs = append(subs, sub)
	}
	s.mu.RUnlock()

	name := "enkapp-har-" + time.Now().UTC().Format("20060102T150405Z") + ".zip"
	w.Header().Set("Content-Type", "application/zip")
	w.Header().Set("Content-Disposition", `attachment; filename="`+name+`"`)
	w.Header().Set("Cache-Control", "no-store")

	zw := zip.NewWriter(w)
	defer func() {
		if err := zw.Close(); err != nil {
			log.Printf("close archive: %v", err)
		}
	}()
	usedNames := map[string]int{}
	for _, sub := range subs {
		data := sub.Raw
		if len(data) == 0 {
			fallback, err := json.MarshalIndent(sub.HAR, "", "  ")
			if err != nil {
				log.Printf("marshal HAR fallback %s: %v", sub.ID, err)
				continue
			}
			data = fallback
		}

		entryName := uniqueArchiveName(archiveEntryName(sub), usedNames)
		fw, err := zw.Create(entryName)
		if err != nil {
			log.Printf("archive entry %s: %v", sub.ID, err)
			continue
		}
		if _, err := fw.Write(data); err != nil {
			log.Printf("write archive entry %s: %v", sub.ID, err)
		}
	}
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

func gameID(sub *submission) string {
	for _, entry := range sub.HAR.Log.Entries {
		if id := gameIDFromURL(entry.Request.URL); id != "" {
			return id
		}
	}
	return ""
}

func gameIDFromURL(raw string) string {
	parsed, err := url.Parse(raw)
	if err != nil {
		return ""
	}
	parts := strings.Split(strings.Trim(parsed.Path, "/"), "/")
	for i := 0; i < len(parts)-1; i++ {
		if strings.EqualFold(parts[i], "play") && isDigits(parts[i+1]) {
			return parts[i+1]
		}
	}
	return ""
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

func archiveEntryName(sub *submission) string {
	parts := []string{
		sub.ReceivedAt.Local().Format("2006-01-02_15-04-05"),
		emptyDash(sub.Domain),
		"game-" + emptyDash(gameID(sub)),
		sub.ID,
	}
	return sanitizeFilename(strings.Join(parts, "_")) + ".har"
}

func uniqueArchiveName(name string, used map[string]int) string {
	count := used[name]
	used[name] = count + 1
	if count == 0 {
		return name
	}
	ext := filepath.Ext(name)
	base := strings.TrimSuffix(name, ext)
	return fmt.Sprintf("%s-%d%s", base, count+1, ext)
}

var unsafeFilenameChars = regexp.MustCompile(`[^A-Za-z0-9._-]+`)

func sanitizeFilename(value string) string {
	value = unsafeFilenameChars.ReplaceAllString(value, "-")
	value = strings.Trim(value, ".-")
	if value == "" {
		return "capture"
	}
	return value
}

func isDigits(value string) bool {
	if value == "" {
		return false
	}
	for _, ch := range value {
		if ch < '0' || ch > '9' {
			return false
		}
	}
	return true
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

func constantTimeEqual(a, b string) bool {
	if len(a) != len(b) {
		return false
	}
	return subtle.ConstantTimeCompare([]byte(a), []byte(b)) == 1
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
  <form id="captures-form" method="post" action="/api/sessions/archive">
    <div class="toolbar">
      <label class="select-all"><input id="select-all" type="checkbox"> Select visible</label>
      <button id="download-selected" type="submit" disabled>Download selected ZIP</button>
      <button id="clear-filters" type="button">Clear filters</button>
      <span id="selection-count">0 selected</span>
    </div>
    <table class="captures">
      <colgroup>
        <col class="select-col">
        <col class="received-col">
        <col class="game-col">
        <col class="domain-col">
        <col class="login-col">
        <col class="version-col">
        <col class="entries-col">
        <col class="first-url-col">
        <col class="client-col">
      </colgroup>
      <thead>
        <tr class="sort-row">
          <th></th>
          <th><button type="button" data-sort="received">Received</button></th>
          <th><button type="button" data-sort="game">Game ID</button></th>
          <th><button type="button" data-sort="domain">Domain</button></th>
          <th><button type="button" data-sort="login">Login</button></th>
          <th><button type="button" data-sort="version">Version</button></th>
          <th><button type="button" data-sort="entries">Entries</button></th>
          <th><button type="button" data-sort="url">First request</button></th>
          <th><button type="button" data-sort="client">Client</button></th>
        </tr>
        <tr class="filter-row">
          <th></th>
          <th><input data-filter="received" aria-label="Filter received"></th>
          <th><input data-filter="game" aria-label="Filter game ID"></th>
          <th><input data-filter="domain" aria-label="Filter domain"></th>
          <th><input data-filter="login" aria-label="Filter login"></th>
          <th><input data-filter="version" aria-label="Filter version"></th>
          <th><input data-filter="entries" aria-label="Filter entries"></th>
          <th><input data-filter="url" aria-label="Filter first request"></th>
          <th><input data-filter="client" aria-label="Filter client"></th>
        </tr>
      </thead>
      <tbody>
        {{range .Items}}
        <tr data-received="{{.ReceivedAt}}" data-game="{{.GameID}}" data-domain="{{.Domain}}" data-login="{{.Login}}" data-version="{{.Version}}" data-entries="{{.EntryCount}}" data-url="{{.FirstURL}}" data-client="{{.RemoteAddr}}">
          <td class="select"><input type="checkbox" name="ids" value="{{.ID}}" aria-label="Select capture {{.ReceivedAt}}"></td>
          <td class="received"><a href="/sessions/{{.ID}}">{{.ReceivedAt}}</a></td>
          <td class="game">{{.GameID}}</td>
          <td class="domain">{{.Domain}}</td>
          <td class="login">{{.Login}}</td>
          <td class="version">{{.Version}}</td>
          <td class="entries">{{.EntryCount}}</td>
          <td class="url" title="{{.FirstURL}}">{{.FirstURL}}</td>
          <td class="client">{{.RemoteAddr}}</td>
        </tr>
        {{else}}
        <tr><td colspan="9" class="empty">No HAR captures yet.</td></tr>
        {{end}}
      </tbody>
    </table>
  </form>
</main>
<script>
(() => {
  const root = document.querySelector("main[data-page='index']");
  const status = document.getElementById("live-status");
  const form = document.getElementById("captures-form");
  const table = document.querySelector(".captures");
  const tbody = table?.querySelector("tbody");
  const selectAll = document.getElementById("select-all");
  const downloadButton = document.getElementById("download-selected");
  const clearFiltersButton = document.getElementById("clear-filters");
  const selectionCount = document.getElementById("selection-count");
  const rows = tbody ? [...tbody.querySelectorAll("tr[data-received]")] : [];
  const filters = [...document.querySelectorAll("[data-filter]")];
  const sortButtons = [...document.querySelectorAll("[data-sort]")];
  let latestID = root?.dataset.latestId || "";
  let sortKey = "received";
  let sortDirection = "desc";

  function rowValue(row, key) {
    return row.dataset[key] || "";
  }

  function compareRows(a, b) {
    let left = rowValue(a, sortKey);
    let right = rowValue(b, sortKey);
    let result;
    if (sortKey === "entries" || sortKey === "game") {
      result = (Number(left) || 0) - (Number(right) || 0);
    } else {
      result = left.localeCompare(right, undefined, { numeric: true, sensitivity: "base" });
    }
    return sortDirection === "asc" ? result : -result;
  }

  function applyTableState() {
    const activeFilters = filters
      .map((input) => [input.dataset.filter, input.value.trim().toLowerCase()])
      .filter(([, value]) => value !== "");
    rows.sort(compareRows);
    for (const row of rows) {
      const matches = activeFilters.every(([key, value]) => rowValue(row, key).toLowerCase().includes(value));
      row.hidden = !matches;
      tbody.appendChild(row);
    }
    for (const button of sortButtons) {
      const active = button.dataset.sort === sortKey;
      button.dataset.direction = active ? sortDirection : "";
      button.setAttribute("aria-sort", active ? sortDirection : "none");
    }
    updateSelection();
  }

  function visibleRows() {
    return rows.filter((row) => !row.hidden);
  }

  function selectedRows() {
    return rows.filter((row) => row.querySelector("input[type='checkbox']")?.checked);
  }

  function updateSelection() {
    const visible = visibleRows();
    const selected = selectedRows();
    downloadButton.disabled = selected.length === 0;
    selectionCount.textContent = selected.length + " selected";
    if (visible.length === 0) {
      selectAll.checked = false;
      selectAll.indeterminate = false;
      return;
    }
    const visibleSelected = visible.filter((row) => row.querySelector("input[type='checkbox']")?.checked).length;
    selectAll.checked = visibleSelected === visible.length;
    selectAll.indeterminate = visibleSelected > 0 && visibleSelected < visible.length;
  }

  for (const button of sortButtons) {
    button.addEventListener("click", () => {
      const nextKey = button.dataset.sort;
      if (sortKey === nextKey) {
        sortDirection = sortDirection === "asc" ? "desc" : "asc";
      } else {
        sortKey = nextKey;
        sortDirection = nextKey === "received" ? "desc" : "asc";
      }
      applyTableState();
    });
  }

  for (const input of filters) {
    input.addEventListener("input", applyTableState);
  }

  for (const row of rows) {
    row.querySelector("input[type='checkbox']")?.addEventListener("change", updateSelection);
  }

  selectAll?.addEventListener("change", () => {
    for (const row of visibleRows()) {
      const checkbox = row.querySelector("input[type='checkbox']");
      if (checkbox) checkbox.checked = selectAll.checked;
    }
    updateSelection();
  });

  clearFiltersButton?.addEventListener("click", () => {
    for (const input of filters) input.value = "";
    applyTableState();
  });

  form?.addEventListener("submit", (event) => {
    if (selectedRows().length === 0) {
      event.preventDefault();
    }
  });

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

  applyTableState();
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
      <p>{{.Session.ReceivedAt.Local.Format "2006-01-02 15:04:05"}} · {{if .Session.Login}}{{.Session.Login}}{{else}}-{{end}} · {{.Session.RemoteAddr}} · {{.Session.EntryCount}} entries</p>
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
main { width: min(1320px, calc(100vw - 32px)); margin: 0 auto; padding: 28px 0 48px; }
a { color: #8ab4ff; text-decoration: none; }
a:hover { text-decoration: underline; }
button, input { font: inherit; }
button { cursor: pointer; }
.top { display: flex; justify-content: space-between; align-items: flex-end; gap: 16px; margin-bottom: 20px; }
h1 { margin: 0 0 6px; font-size: 28px; }
h2 { margin: 10px 0 4px; font-size: 18px; overflow-wrap: anywhere; }
h3 { margin: 16px 0 8px; font-size: 14px; color: #aeb6c8; }
p { margin: 0; color: #aeb6c8; }
.toolbar { display: flex; flex-wrap: wrap; gap: 10px 14px; align-items: center; margin-bottom: 12px; color: #aeb6c8; }
.toolbar button { border: 1px solid #394150; border-radius: 6px; padding: 6px 10px; background: #202632; color: #e7e9ee; }
.toolbar button:disabled { cursor: default; opacity: 0.55; }
.select-all { display: inline-flex; gap: 6px; align-items: center; color: #e7e9ee; }
table { width: 100%; border-collapse: collapse; background: #171a21; border: 1px solid #2a2f3a; }
th, td { padding: 10px 12px; border-bottom: 1px solid #2a2f3a; text-align: left; vertical-align: top; }
th { color: #aeb6c8; font-size: 13px; font-weight: 600; }
.captures { table-layout: fixed; }
.captures th, .captures td { overflow: hidden; }
.captures .select-col { width: 42px; }
.captures .received-col { width: 172px; }
.captures .game-col { width: 82px; }
.captures .domain-col { width: 120px; }
.captures .login-col { width: 108px; }
.captures .version-col { width: 78px; }
.captures .entries-col { width: 70px; }
.captures .client-col { width: 132px; }
.captures .select { text-align: center; }
.captures .sort-row th { padding-bottom: 6px; }
.captures .sort-row button {
  display: inline-flex;
  max-width: 100%;
  padding: 0;
  border: 0;
  background: transparent;
  color: inherit;
  font-weight: 600;
  text-align: left;
}
.captures .sort-row button[data-direction="asc"]::after { content: " ↑"; }
.captures .sort-row button[data-direction="desc"]::after { content: " ↓"; }
.captures .filter-row th { padding-top: 0; }
.captures .filter-row input {
  box-sizing: border-box;
  width: 100%;
  min-width: 0;
  border: 1px solid #2f3643;
  border-radius: 5px;
  padding: 5px 6px;
  background: #10131a;
  color: #e7e9ee;
}
.captures .received, .captures .game, .captures .domain, .captures .login, .captures .version, .captures .entries, .captures .client {
  white-space: nowrap;
  text-overflow: ellipsis;
}
.captures .game, .captures .entries { text-align: right; }
.captures .url {
  white-space: nowrap;
  text-overflow: ellipsis;
}
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
  colgroup { display: none; }
  thead { display: none; }
  tr { border-bottom: 1px solid #2a2f3a; }
  .captures .select { text-align: left; }
  .captures .received, .captures .game, .captures .domain, .captures .login, .captures .version, .captures .entries, .captures .client, .captures .url {
    white-space: normal;
    text-overflow: clip;
  }
  .captures .game, .captures .entries { text-align: left; }
  dl { grid-template-columns: 1fr; }
}
</style>
</head>
<body>`

const pageSuffix = `</body></html>`

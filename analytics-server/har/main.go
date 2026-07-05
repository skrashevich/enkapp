package main

import (
	"archive/zip"
	"bytes"
	"crypto/rand"
	"crypto/subtle"
	"embed"
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
const sessionMergeWindow = 30 * time.Minute

//go:embed templates/*.html templates/*.css
var templateFiles embed.FS

type pageTemplate struct {
	*template.Template
	name string
}

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
	ShareToken string          `json:"share_token,omitempty"`
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
	Session    *submission
	Entries    []entryView
	State      stateResponse
	IsPublic   bool
	RawURL     string
	ShareURL   string
	PublicPath string
}

type shareResponse struct {
	URL string `json:"url"`
}

type stateResponse struct {
	Count            int    `json:"count"`
	LatestID         string `json:"latest_id"`
	LatestRevision   string `json:"latest_revision"`
	LatestReceivedAt string `json:"latest_received_at"`
	LatestDomain     string `json:"latest_domain"`
	LatestFirstURL   string `json:"latest_first_url"`
}

func (s *submission) revision() string {
	return s.ID + ":" + strconv.Itoa(s.EntryCount) + ":" + s.ReceivedAt.UTC().Format(time.RFC3339Nano)
}

type entryView struct {
	Index            int
	Method           string
	URL              string
	URLPath          string
	Status           int
	StatusText       string
	Time             string
	StartedAt        string
	RequestHeaders   []nameValue
	ResponseHeaders  []nameValue
	QueryString      []nameValue
	RequestBody      string
	ResponseBody     string
	ResponseBodyJSON string
	HasResponseBody  bool
	HasResponseJSON  bool
	ResponseView     string
	IsRawView        bool
	IsHTMLView       bool
	IsJSONView       bool
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
	mux.HandleFunc("/share/", srv.handleSharedSession)
	mux.HandleFunc("/favicon.ico", srv.handleFavicon)
	mux.HandleFunc("/", srv.requireViewerAuth(srv.handleIndex))
	mux.HandleFunc("/sessions/", srv.requireViewerAuth(srv.handleSession))
	mux.HandleFunc("/api/state", srv.requireViewerAuth(srv.handleState))
	mux.HandleFunc("/api/sessions/archive", srv.requireViewerAuth(srv.handleArchive))
	mux.HandleFunc("/api/sessions/share", srv.requireViewerAuth(srv.handleShare))
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

func (s *server) handleFavicon(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "public, max-age=86400, immutable")
	w.Header().Set("Content-Type", "image/x-icon")
	w.WriteHeader(http.StatusNoContent)
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

	if saved, err := s.saveWithMerge(sub, sessionMergeWindow); err != nil {
		log.Printf("save HAR: %v", err)
		http.Error(w, "failed to save HAR", http.StatusInternalServerError)
		return
	} else {
		sub = saved
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	_ = json.NewEncoder(w).Encode(map[string]any{
		"id":      sub.ID,
		"entries": sub.EntryCount,
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

	page := s.detailPage(sub, false)
	page.RawURL = "/sessions/" + sub.ID + "?raw=1"
	if sub.ShareToken != "" {
		page.PublicPath = "/share/" + sub.ShareToken
		page.ShareURL = absoluteURL(r, page.PublicPath)
	}
	render(w, detailTemplate, page)
}

func (s *server) handleSharedSession(w http.ResponseWriter, r *http.Request) {
	token := strings.TrimPrefix(r.URL.Path, "/share/")
	if token == "" || strings.Contains(token, "/") {
		http.NotFound(w, r)
		return
	}

	sub := s.findByShareToken(token)
	if sub == nil {
		http.NotFound(w, r)
		return
	}

	if r.URL.Query().Get("raw") == "1" {
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		w.Header().Set("Cache-Control", "no-store")
		_, _ = w.Write(sub.Raw)
		return
	}

	page := s.detailPage(sub, true)
	page.RawURL = "/share/" + token + "?raw=1"
	page.PublicPath = "/share/" + token
	page.ShareURL = absoluteURL(r, page.PublicPath)
	render(w, detailTemplate, page)
}

func (s *server) handleShare(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if err := r.ParseForm(); err != nil {
		http.Error(w, "invalid form", http.StatusBadRequest)
		return
	}
	id := strings.TrimSpace(r.Form.Get("id"))
	if id == "" || strings.Contains(id, "/") {
		http.Error(w, "invalid session id", http.StatusBadRequest)
		return
	}

	s.mu.RLock()
	sub := s.sessions[id]
	s.mu.RUnlock()
	if sub == nil {
		http.NotFound(w, r)
		return
	}

	if sub.ShareToken == "" {
		sub.ShareToken = newShareToken()
		if err := s.save(sub); err != nil {
			log.Printf("save share token %s: %v", id, err)
			http.Error(w, "failed to save share link", http.StatusInternalServerError)
			return
		}
	}

	path := "/share/" + sub.ShareToken
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	_ = json.NewEncoder(w).Encode(shareResponse{URL: absoluteURL(r, path)})
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

func (s *server) findByShareToken(token string) *submission {
	s.mu.RLock()
	defer s.mu.RUnlock()
	for _, sub := range s.sessions {
		if sub.ShareToken != "" && constantTimeEqual(sub.ShareToken, token) {
			return sub
		}
	}
	return nil
}

func (s *server) detailPage(sub *submission, isPublic bool) detailPage {
	page := detailPage{Session: sub, State: s.state(), IsPublic: isPublic}
	for i, entry := range sub.HAR.Log.Entries {
		responseBody := entry.Response.Content.Text
		responseBodyJSON := prettyJSON(responseBody)
		responseView := defaultResponseView(responseContentType(entry), responseBodyJSON != "")
		page.Entries = append(page.Entries, entryView{
			Index:            i + 1,
			Method:           entry.Request.Method,
			URL:              entry.Request.URL,
			URLPath:          compactURL(entry.Request.URL),
			Status:           entry.Response.Status,
			StatusText:       entry.Response.StatusText,
			Time:             fmt.Sprintf("%.0f ms", entry.Time),
			StartedAt:        entry.StartedDateTime,
			RequestHeaders:   entry.Request.Headers,
			ResponseHeaders:  entry.Response.Headers,
			QueryString:      entry.Request.QueryString,
			RequestBody:      entry.requestBody(),
			ResponseBody:     responseBody,
			ResponseBodyJSON: responseBodyJSON,
			HasResponseBody:  responseBody != "",
			HasResponseJSON:  responseBodyJSON != "",
			ResponseView:     responseView,
			IsRawView:        responseView == "raw",
			IsHTMLView:       responseView == "html",
			IsJSONView:       responseView == "json",
		})
	}
	return page
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
	result.LatestRevision = latest.revision()
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
	if err := writeSubmission(s.dataDir, sub); err != nil {
		return err
	}
	s.mu.Lock()
	s.sessions[sub.ID] = sub
	s.mu.Unlock()
	return nil
}

func (s *server) saveWithMerge(sub *submission, window time.Duration) (*submission, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if target := s.mergeTargetLocked(sub, window); target != nil {
		target.ReceivedAt = sub.ReceivedAt
		target.EntryCount += len(sub.HAR.Log.Entries)
		target.HAR.Log.Entries = append(target.HAR.Log.Entries, sub.HAR.Log.Entries...)
		raw, err := json.Marshal(target.HAR)
		if err != nil {
			return nil, err
		}
		target.Raw = append(target.Raw[:0], raw...)
		if err := writeSubmission(s.dataDir, target); err != nil {
			return nil, err
		}
		return target, nil
	}

	if err := writeSubmission(s.dataDir, sub); err != nil {
		return nil, err
	}
	s.sessions[sub.ID] = sub
	return sub, nil
}

func (s *server) mergeTargetLocked(sub *submission, window time.Duration) *submission {
	subGameID := gameID(sub)
	if subGameID == "" {
		return nil
	}

	var latest *submission
	for _, candidate := range s.sessions {
		if !sameSessionKey(candidate, sub, subGameID) {
			continue
		}
		if sub.ReceivedAt.Sub(candidate.ReceivedAt) < 0 || sub.ReceivedAt.Sub(candidate.ReceivedAt) > window {
			continue
		}
		if latest == nil || candidate.ReceivedAt.After(latest.ReceivedAt) {
			latest = candidate
		}
	}
	return latest
}

func sameSessionKey(a, b *submission, bGameID string) bool {
	return strings.EqualFold(strings.TrimSpace(a.Domain), strings.TrimSpace(b.Domain)) &&
		strings.EqualFold(strings.TrimSpace(a.Login), strings.TrimSpace(b.Login)) &&
		a.Version == b.Version &&
		a.Build == b.Build &&
		a.RemoteAddr == b.RemoteAddr &&
		gameID(a) == bGameID
}

func writeSubmission(dataDir string, sub *submission) error {
	data, err := json.MarshalIndent(sub, "", "  ")
	if err != nil {
		return err
	}
	name := filepath.Join(dataDir, sub.ID+".json")
	tmp := name + ".tmp"
	if err := os.WriteFile(tmp, data, 0o600); err != nil {
		return err
	}
	if err := os.Rename(tmp, name); err != nil {
		return err
	}
	return nil
}

func render(w http.ResponseWriter, tmpl pageTemplate, data any) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	if err := tmpl.ExecuteTemplate(w, tmpl.name, data); err != nil {
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

func prettyJSON(value string) string {
	value = strings.TrimSpace(value)
	if value == "" {
		return ""
	}
	var buf bytes.Buffer
	if err := json.Indent(&buf, []byte(value), "", "  "); err != nil {
		return ""
	}
	return buf.String()
}

func responseContentType(entry harEntry) string {
	for _, header := range entry.Response.Headers {
		if strings.EqualFold(header.Name, "content-type") {
			if value := strings.TrimSpace(header.Value); value != "" {
				return value
			}
		}
	}
	return entry.Response.Content.MimeType
}

func defaultResponseView(contentType string, hasJSON bool) string {
	mimeType := strings.ToLower(strings.TrimSpace(strings.Split(contentType, ";")[0]))
	switch {
	case hasJSON && (mimeType == "application/json" || strings.HasSuffix(mimeType, "+json")):
		return "json"
	case mimeType == "text/html":
		return "html"
	default:
		return "raw"
	}
}

func newID(now time.Time) string {
	var buf [4]byte
	if _, err := rand.Read(buf[:]); err != nil {
		panic(errors.Join(errors.New("random id"), err))
	}
	return now.Format("20060102T150405.000000000Z") + "-" + hex.EncodeToString(buf[:])
}

func newShareToken() string {
	var buf [16]byte
	if _, err := rand.Read(buf[:]); err != nil {
		panic(errors.Join(errors.New("random share token"), err))
	}
	return hex.EncodeToString(buf[:])
}

func absoluteURL(r *http.Request, path string) string {
	proto := r.Header.Get("X-Forwarded-Proto")
	if proto == "" {
		if r.TLS != nil {
			proto = "https"
		} else {
			proto = "http"
		}
	}
	host := r.Header.Get("X-Forwarded-Host")
	if host == "" {
		host = r.Host
	}
	return proto + "://" + host + path
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

var indexTemplate = loadPageTemplate("index.html")
var detailTemplate = loadPageTemplate("detail.html")

func loadPageTemplate(name string) pageTemplate {
	files := []string{
		"templates/layout.html",
		"templates/styles.css",
		"templates/" + name,
	}
	return pageTemplate{
		Template: template.Must(template.ParseFS(templateFiles, files...)),
		name:     name,
	}
}

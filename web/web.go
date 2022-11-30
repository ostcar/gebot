package web

import (
	"context"
	"crypto/subtle"
	"embed"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"log"
	"net"
	"net/http"
	"strings"
	"time"

	"github.com/gorilla/mux"
	"github.com/ostcar/gebot/config"
	"github.com/ostcar/gebot/model"
)

//go:embed client/index.html
var defaultIndex []byte

//go:embed static
var defaultStatic embed.FS

const (
	pathPrefixAPI    = "/api"
	pathPrefixStatic = "/static"
	cookieName       = "gebot"
	cookieAge        = 265 * 24 * time.Hour
)

// Files to use in the handlers.
type Files struct {
	Index  []byte
	Static fs.FS
}

// Run starts the webserver on the given port
func Run(ctx context.Context, model *model.Model, config config.Config) error {
	static, err := fs.Sub(defaultStatic, "static")
	if err != nil {
		return fmt.Errorf("open static folder: %w", err)
	}

	defaultFiles := Files{
		Index:  defaultIndex,
		Static: static,
	}

	srv := &http.Server{
		Addr:        config.WebListenAddr,
		Handler:     newServer(model, defaultFiles, config.Password, config.Secred),
		BaseContext: func(net.Listener) context.Context { return ctx },
	}

	// Shutdown logic in separate goroutine.
	wait := make(chan error)
	go func() {
		// Wait for the context to be closed.
		<-ctx.Done()

		if err := srv.Shutdown(context.Background()); err != nil {
			wait <- fmt.Errorf("HTTP server shutdown: %w", err)
			return
		}
		wait <- nil
	}()

	log.Printf("Listen webserver on: %s", config.WebListenAddr)
	if err := srv.ListenAndServe(); err != http.ErrServerClosed {
		return fmt.Errorf("HTTP Server failed: %v", err)
	}

	return <-wait
}

type server struct {
	router http.Handler

	mdl *model.Model

	files    Files
	password string
	secret   string
}

func newServer(mdl *model.Model, files Files, password string, secret string) server {
	s := server{
		mdl:      mdl,
		files:    files,
		password: password,
		secret:   secret,
	}

	s.router = s.initRouter()

	return s
}

func (s server) initRouter() http.Handler {
	router := mux.NewRouter()
	router.Use(loggingMiddleware)

	// index
	router.MatcherFunc(func(r *http.Request, m *mux.RouteMatch) bool {
		// Match every path expect /api and /static
		return !strings.HasPrefix(r.URL.Path, pathPrefixAPI) && !strings.HasPrefix(r.URL.Path, pathPrefixStatic)
	}).HandlerFunc(s.index)

	router.PathPrefix(pathPrefixStatic).Handler(s.staticHandler())

	router.Path(pathPrefixAPI + "/login").Methods("POST").HandlerFunc(s.login)
	router.Path(pathPrefixAPI + "/gebot").Methods("GET").HandlerFunc(s.list)
	router.Path(pathPrefixAPI + "/gebot").Methods("POST").HandlerFunc(s.gebot)
	router.Path(pathPrefixAPI + "/gebot").Methods("DELETE").HandlerFunc(s.delete)
	router.Path(pathPrefixAPI + "/reset").Methods("DELETE").HandlerFunc(s.reset)

	return router
}

func (s server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	s.router.ServeHTTP(w, r)
}

// index returns the index.html.
func (s server) index(w http.ResponseWriter, r *http.Request) {
	w.Write(s.files.Index)
}

// static returns static files.
func (s server) staticHandler() http.Handler {
	return http.StripPrefix(pathPrefixStatic, http.FileServer(http.FS(s.files.Static)))
}

func (s server) login(w http.ResponseWriter, r *http.Request) {
	var content struct {
		Password string `json:"password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&content); err != nil {
		handleError(w, fmt.Errorf("decoding body: %w", err))
		return
	}

	if subtle.ConstantTimeCompare([]byte(content.Password), []byte(s.password)) == 0 {
		w.WriteHeader(401)
		fmt.Fprintln(w, "Invalid password")
		return
	}

	tokenString, err := createToken(true, []byte(s.secret))
	if err != nil {
		handleError(w, err)
		return
	}

	http.SetCookie(w, &http.Cookie{Name: cookieName, Value: tokenString, Path: "/", MaxAge: int(cookieAge.Seconds()), Secure: true})
	fmt.Fprintln(w, "Hello admin")
}

func (s server) list(w http.ResponseWriter, r *http.Request) {
	if !isAdmin(r, s.secret) {
		w.WriteHeader(403)
		return
	}

	data := s.mdl.List()

	if err := json.NewEncoder(w).Encode(data); err != nil {
		handleError(w, err)
		return
	}
}

func (s server) gebot(w http.ResponseWriter, r *http.Request) {
	var content struct {
		Cent int `json:"cent"`
	}

	if err := json.NewDecoder(r.Body).Decode(&content); err != nil {
		handleError(w, fmt.Errorf("decoding body: %w", err))
		return
	}

	id, err := s.mdl.Gebot(content.Cent)

	if err != nil {
		handleError(w, err)
		return
	}

	response := struct {
		ID int `json:"id"`
	}{
		ID: id,
	}
	if err := json.NewEncoder(w).Encode(response); err != nil {
		handleError(w, err)
		return
	}
}

func (s server) delete(w http.ResponseWriter, r *http.Request) {
	if !isAdmin(r, s.secret) {
		w.WriteHeader(403)
		return
	}

	var content struct {
		ID int `json:"id"`
	}

	if err := json.NewDecoder(r.Body).Decode(&content); err != nil {
		handleError(w, fmt.Errorf("decoding body: %w", err))
		return
	}

	if err := s.mdl.Delete(content.ID); err != nil {
		handleError(w, err)
		return
	}
}

func (s server) reset(w http.ResponseWriter, r *http.Request) {
	if !isAdmin(r, s.secret) {
		w.WriteHeader(403)
		return
	}

	if err := s.mdl.Reset(); err != nil {
		handleError(w, fmt.Errorf("reset: %w", err))
		return
	}
}

func handleError(w http.ResponseWriter, err error) {
	msg := "Interner Fehler"
	status := 500
	var skipLog bool

	var forClient interface {
		forClient() string
	}
	if errors.As(err, &forClient) {
		msg = forClient.forClient()
		status = 400
		//skipLog = true
	}

	var httpStatus interface {
		httpStatus() int
	}
	if errors.As(err, &httpStatus) {
		status = httpStatus.httpStatus()
	}

	if !skipLog {
		log.Printf("Error: %v", err)
	}

	http.Error(w, msg, status)
	return
}

type responselogger struct {
	http.ResponseWriter
	code int
}

func (r *responselogger) WriteHeader(code int) {
	r.code = code
	r.ResponseWriter.WriteHeader(code)
}

func loggingMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		writer := &responselogger{w, 200}
		next.ServeHTTP(writer, r)
		log.Printf("%s %d %s", r.Method, writer.code, r.RequestURI)
	})
}

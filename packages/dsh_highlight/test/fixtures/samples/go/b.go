package server

import (
	"context"
	"net/http"
	str "strings"
	_ "embed"
)

//go:embed index.html
var page string

type (
	ID   int64
	Mux  map[string]http.HandlerFunc
	Opt  func(*Server) error
)

type Server struct {
	mu    sync.RWMutex `json:"-"`
	Addr  string       `json:"addr,omitempty"`
	hooks []func(ctx context.Context) error
}

func (s *Server) Handle(w http.ResponseWriter, r *http.Request) {
	defer func() {
		if rec := recover(); rec != nil {
			http.Error(w, "boom: "+str.ToUpper(fmt.Sprint(rec)), 500)
		}
	}()
	switch v := r.Context().Value(key).(type) {
	case string:
		fmt.Fprintf(w, "%s %d %v %q\n", v, 0x1F, 1e3, 'a')
	case nil, int:
	}
	var x, y = 0b1010, 0o17
	z := [...]int{1, 2, 3}[1:]
	m := map[string][]int{"a": {1}, "b": nil}
	for i := range 3 { _ = i }
	if err := s.run(); err != nil && !errors.Is(err, io.EOF) { return }
	ch := make(<-chan struct{})
	goto end
end:
	_ = ch; _, _, _, _ = x, y, z, m
}

func Map[T, U any](xs []T, f func(T) U) []U { return nil }

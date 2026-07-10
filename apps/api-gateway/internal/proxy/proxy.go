// Package proxy provides a reverse proxy for routing requests to upstream services.
package proxy

import (
	"net/http"
	"net/http/httputil"
	"net/url"
	"strings"
)

// Router routes incoming requests to upstream services based on path prefix.
type Router struct {
	routes []Route
}

// Route defines a path prefix → upstream URL mapping.
type Route struct {
	Prefix    string
	TargetURL *url.URL
}

// NewRouter creates a router from a map of prefix → URL string.
func NewRouter(routes map[string]string) (*Router, error) {
	var r []Route
	for prefix, target := range routes {
		u, err := url.Parse(target)
		if err != nil {
			return nil, err
		}
		r = append(r, Route{Prefix: prefix, TargetURL: u})
	}
	return &Router{routes: r}, nil
}

// Handler returns an http.Handler that proxies to the matched upstream.
func (rt *Router) Handler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		for _, route := range rt.routes {
			if strings.HasPrefix(r.URL.Path, route.Prefix) {
				proxy := httputil.NewSingleHostReverseProxy(route.TargetURL)
				// Preserve original Host (some upstreams care)
				r.Host = route.TargetURL.Host
				proxy.ServeHTTP(w, r)
				return
			}
		}
		http.NotFound(w, r)
	})
}

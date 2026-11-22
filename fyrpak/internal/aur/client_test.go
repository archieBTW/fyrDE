package aur

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestClientSearchAndInfo(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		switch r.URL.Path {
		case "/search/fyr":
			_, _ = w.Write([]byte(`{"version":5,"type":"search","resultcount":2,"results":[
				{"Name":"fyr-theme-git","Version":"1.0-1","Description":"Fyr theme","NumVotes":12,"Popularity":1.5},
				{"Name":"fyr-bar","Version":"2.0-1","Description":"Fyr top bar","NumVotes":50,"Popularity":4.2}
			]}`))
		case "/info":
			_, _ = w.Write([]byte(`{"version":5,"type":"multiinfo","resultcount":1,"results":[
				{"Name":"fyr-bar","PackageBase":"fyr-bar","Version":"2.0-1","Depends":["gtk3"]}
			]}`))
		default:
			http.NotFound(w, r)
		}
	}))
	defer srv.Close()

	c := &Client{BaseURL: srv.URL, HTTPClient: srv.Client()}

	res, err := c.Search([]string{"fyr"})
	if err != nil {
		t.Fatalf("Search failed: %v", err)
	}
	if len(res) != 2 || res[0].Name != "fyr-bar" {
		t.Fatalf("expected popularity-sorted results with fyr-bar first, got %+v", res)
	}

	info, err := c.InfoMap([]string{"fyr-bar"})
	if err != nil {
		t.Fatalf("InfoMap failed: %v", err)
	}
	if p, ok := info["fyr-bar"]; !ok || len(p.Depends) != 1 || p.Depends[0] != "gtk3" {
		t.Fatalf("unexpected info result: %+v", info)
	}
}

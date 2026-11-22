package aur

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"sort"
	"strings"
	"time"
)

const DefaultBaseURL = "https://aur.archlinux.org/rpc/v5"

type Package struct {
	ID             int      `json:"ID"`
	Name           string   `json:"Name"`
	PackageBaseID  int      `json:"PackageBaseID"`
	PackageBase    string   `json:"PackageBase"`
	Version        string   `json:"Version"`
	Description    string   `json:"Description"`
	URL            string   `json:"URL"`
	NumVotes       int      `json:"NumVotes"`
	Popularity     float64  `json:"Popularity"`
	OutOfDate      *int64   `json:"OutOfDate"`
	Maintainer     string   `json:"Maintainer"`
	FirstSubmitted int64    `json:"FirstSubmitted"`
	LastModified   int64    `json:"LastModified"`
	URLPath        string   `json:"URLPath"`
	Depends        []string `json:"Depends"`
	MakeDepends    []string `json:"MakeDepends"`
	OptDepends     []string `json:"OptDepends"`
	CheckDepends   []string `json:"CheckDepends"`
	Conflicts      []string `json:"Conflicts"`
	Provides       []string `json:"Provides"`
	Replaces       []string `json:"Replaces"`
	License        []string `json:"License"`
	Keywords       []string `json:"Keywords"`
}

type rpcResponse struct {
	Version     int       `json:"version"`
	Type        string    `json:"type"`
	ResultCount int       `json:"resultcount"`
	Results     []Package `json:"results"`
	Error       string    `json:"error"`
}

type Client struct {
	BaseURL    string
	HTTPClient *http.Client
}

func NewClient() *Client {
	return &Client{
		BaseURL: DefaultBaseURL,
		HTTPClient: &http.Client{
			Timeout: 20 * time.Second,
		},
	}
}

func (c *Client) get(endpoint string) ([]Package, error) {
	req, err := http.NewRequest(http.MethodGet, endpoint, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "fyrpak/1.0 (+https://github.com/archieBTW/fyrDE)")

	resp, err := c.HTTPClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("AUR request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("AUR returned HTTP %d", resp.StatusCode)
	}

	var parsed rpcResponse
	if err := json.NewDecoder(resp.Body).Decode(&parsed); err != nil {
		return nil, fmt.Errorf("failed to decode AUR response: %w", err)
	}
	if parsed.Error != "" {
		return nil, fmt.Errorf("AUR RPC error: %s", parsed.Error)
	}
	return parsed.Results, nil
}

// Search queries the AUR RPC v5 using the first term, then narrows by all terms.
func (c *Client) Search(terms []string) ([]Package, error) {
	if len(terms) == 0 {
		return nil, nil
	}
	// Pick longest term for primary RPC query to avoid 5000-result AUR truncation.
	primary := terms[0]
	for _, t := range terms[1:] {
		if len(t) > len(primary) {
			primary = t
		}
	}

	endpoint := fmt.Sprintf("%s/search/%s", strings.TrimRight(c.BaseURL, "/"), url.PathEscape(primary))
	results, err := c.get(endpoint)
	if err != nil {
		return nil, err
	}

	var filtered []Package
	for _, pkg := range results {
		hay := strings.ToLower(pkg.Name + " " + pkg.Description)
		ok := true
		for _, t := range terms {
			if !strings.Contains(hay, strings.ToLower(t)) {
				ok = false
				break
			}
		}
		if ok {
			filtered = append(filtered, pkg)
		}
	}

	sort.SliceStable(filtered, func(i, j int) bool {
		if filtered[i].Popularity != filtered[j].Popularity {
			return filtered[i].Popularity > filtered[j].Popularity
		}
		return filtered[i].NumVotes > filtered[j].NumVotes
	})
	return filtered, nil
}

// Info retrieves detailed metadata for one or more AUR packages in batches.
func (c *Client) Info(names []string) ([]Package, error) {
	if len(names) == 0 {
		return nil, nil
	}
	const batchSize = 150
	var all []Package
	for start := 0; start < len(names); start += batchSize {
		end := start + batchSize
		if end > len(names) {
			end = len(names)
		}
		vals := url.Values{}
		for _, name := range names[start:end] {
			vals.Add("arg[]", name)
		}
		endpoint := fmt.Sprintf("%s/info?%s", strings.TrimRight(c.BaseURL, "/"), vals.Encode())
		batch, err := c.get(endpoint)
		if err != nil {
			return nil, err
		}
		all = append(all, batch...)
	}
	return all, nil
}

// InfoMap returns a map keyed by exact package name.
func (c *Client) InfoMap(names []string) (map[string]Package, error) {
	list, err := c.Info(names)
	if err != nil {
		return nil, err
	}
	m := make(map[string]Package, len(list))
	for _, p := range list {
		m[p.Name] = p
	}
	return m, nil
}

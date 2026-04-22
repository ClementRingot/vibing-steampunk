package adt

import (
	"context"
	"encoding/json"
	"fmt"
	"sync"
	"time"
)

// DebugWebSocketClient manages ABAP debugging and RFC calls via WebSocket (ZADT_VSP).
// This replaces the REST-based debugger which has CSRF issues for breakpoints.
// Supports domains: debug, rfc
type DebugWebSocketClient struct {
	*BaseWebSocketClient

	// Debug-specific state
	mu         sync.RWMutex
	isAttached bool
	debuggeeID string
	terminalID string // SAP GUI terminal ID for cross-tool breakpoint sharing
	ideID      string // IDE ID for debug session isolation

	// Event channel for async events (debuggee caught, etc.)
	Events chan *DebugEvent
}

// DebugEvent represents an async event from the debugger.
type DebugEvent struct {
	Kind       string         `json:"kind"`
	DebuggeeID string         `json:"debuggee_id,omitempty"`
	Program    string         `json:"program,omitempty"`
	Include    string         `json:"include,omitempty"`
	Line       int            `json:"line,omitempty"`
	Data       map[string]any `json:"data,omitempty"`
}

// DebugDebuggee represents a debuggee that hit a breakpoint.
type DebugDebuggee struct {
	ID         string `json:"id"`
	Host       string `json:"host"`
	User       string `json:"user"`
	Program    string `json:"program"`
	SameServer bool   `json:"sameServer"`
}

// DebugStackFrame represents a stack frame.
type DebugStackFrame struct {
	Index     int    `json:"index"`
	Program   string `json:"program"`
	Include   string `json:"include"`
	Line      int    `json:"line"`
	Procedure string `json:"procedure"`
	Active    bool   `json:"active"`
	System    bool   `json:"system"`
}

// WSDebugVariable represents a variable value from WebSocket debug service.
type WSDebugVariable struct {
	Name  string `json:"name"`
	Value string `json:"value"`
	Scope string `json:"scope"`
}

// NewDebugWebSocketClient creates a new WebSocket-based debug client.
func NewDebugWebSocketClient(baseURL, client, user, password string, insecure bool, cookies map[string]string) *DebugWebSocketClient {
	c := &DebugWebSocketClient{
		BaseWebSocketClient: NewBaseWebSocketClient(baseURL, client, user, password, insecure, cookies),
		Events:              make(chan *DebugEvent, 10),
	}

	// Set disconnect callback to clean up debug state
	c.BaseWebSocketClient.onDisconnect = func() {
		c.mu.Lock()
		c.isAttached = false
		c.debuggeeID = ""
		c.mu.Unlock()
	}

	return c
}

// SetTerminalID sets the SAP GUI terminal ID for cross-tool debugging.
// When set, all debug domain messages will include this terminal ID so that
// ZCL_VSP_DEBUG_SERVICE uses it instead of generating a random UUID.
func (c *DebugWebSocketClient) SetTerminalID(id string) {
	c.terminalID = id
}

// SetIdeID sets the IDE ID for debug session isolation.
// When set, all debug domain messages will include this IDE ID.
func (c *DebugWebSocketClient) SetIdeID(id string) {
	c.ideID = id
}

// sendRequest sends a request to the debug domain and waits for response.
// Automatically injects terminalId into params if configured.
func (c *DebugWebSocketClient) sendRequest(ctx context.Context, action string, params map[string]any) (*WSResponse, error) {
	// Inject terminal ID and IDE ID for cross-tool debugging
	if c.terminalID != "" || c.ideID != "" {
		if params == nil {
			params = make(map[string]any)
		}
		if c.terminalID != "" {
			if _, exists := params["terminalId"]; !exists {
				params["terminalId"] = c.terminalID
			}
		}
		if c.ideID != "" {
			if _, exists := params["ideId"]; !exists {
				params["ideId"] = c.ideID
			}
		}
	}
	return c.SendDomainRequest(ctx, "debug", action, params, 65*time.Second)
}

// IsAttached returns whether the client is attached to a debuggee.
func (c *DebugWebSocketClient) IsAttached() bool {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.isAttached
}

// GetDebuggeeID returns the current debuggee ID.
func (c *DebugWebSocketClient) GetDebuggeeID() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.debuggeeID
}

// AbapHelpResponse represents the response from get_abap_help WebSocket call.
type AbapHelpResponse struct {
	Keyword string `json:"keyword"`
	HTML    string `json:"html"`
	Found   bool   `json:"found"`
}

// GetAbapDocumentation retrieves ABAP keyword documentation via WebSocket (ZADT_VSP).
// Uses CL_ABAP_DOCU on the SAP system to get the real documentation.
func (c *DebugWebSocketClient) GetAbapDocumentation(ctx context.Context, keyword string) (*AbapHelpResponse, error) {
	params := map[string]any{
		"keyword": keyword,
	}

	resp, err := c.SendDomainRequest(ctx, "system", "get_abap_help", params, 30*time.Second)
	if err != nil {
		return nil, err
	}

	if !resp.Success {
		if resp.Error != nil {
			return nil, fmt.Errorf("get_abap_help failed: %s - %s", resp.Error.Code, resp.Error.Message)
		}
		return nil, fmt.Errorf("get_abap_help failed")
	}

	// Parse the response data
	result := &AbapHelpResponse{}
	if len(resp.Data) > 0 {
		if err := json.Unmarshal(resp.Data, result); err != nil {
			return nil, fmt.Errorf("failed to parse response: %w", err)
		}
	}

	return result, nil
}

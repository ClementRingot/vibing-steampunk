package mcp

import (
	"context"
	"strings"
	"testing"

	"github.com/mark3labs/mcp-go/mcp"
)

// --- Tool Registration Tests ---
// Verify all 5 XCO i18n tools are registered with correct parameters.

func getRegisteredTools(t *testing.T) []mcp.Tool {
	t.Helper()
	cfg := &Config{
		BaseURL:  "https://sap.example.com:44300",
		Username: "testuser",
		Password: "testpass",
		Client:   "001",
		Language: "EN",
	}

	server := NewServer(cfg)
	if server == nil || server.mcpServer == nil {
		t.Fatal("server or MCP server is nil")
	}

	rawResponse := server.mcpServer.HandleMessage(context.Background(), []byte(`{
		"jsonrpc": "2.0",
		"id": 1,
		"method": "tools/list",
		"params": {}
	}`))

	response, ok := rawResponse.(mcp.JSONRPCResponse)
	if !ok {
		t.Fatalf("expected JSONRPCResponse, got %T", rawResponse)
	}

	switch result := response.Result.(type) {
	case mcp.ListToolsResult:
		return result.Tools
	case *mcp.ListToolsResult:
		return result.Tools
	default:
		t.Fatalf("expected ListToolsResult, got %T", response.Result)
		return nil
	}
}

func findTool(tools []mcp.Tool, name string) *mcp.Tool {
	for i := range tools {
		if tools[i].Name == name {
			return &tools[i]
		}
	}
	return nil
}

func assertToolExists(t *testing.T, tools []mcp.Tool, name string) *mcp.Tool {
	t.Helper()
	tool := findTool(tools, name)
	if tool == nil {
		t.Fatalf("Tool %q not found in registered tools", name)
	}
	return tool
}

func assertToolHasParam(t *testing.T, tool *mcp.Tool, paramName string) {
	t.Helper()
	if _, ok := tool.InputSchema.Properties[paramName]; !ok {
		t.Errorf("Tool %q is missing parameter %q", tool.Name, paramName)
	}
}

func assertToolHasRequired(t *testing.T, tool *mcp.Tool, requiredParam string) {
	t.Helper()
	for _, r := range tool.InputSchema.Required {
		if r == requiredParam {
			return
		}
	}
	t.Errorf("Tool %q does not list %q as required", tool.Name, requiredParam)
}

func TestGetTranslationXCORegistration(t *testing.T) {
	tools := getRegisteredTools(t)
	tool := assertToolExists(t, tools, "GetTranslationXCO")

	requiredParams := []string{"target_type", "object_name", "language"}
	for _, p := range requiredParams {
		assertToolHasParam(t, tool, p)
		assertToolHasRequired(t, tool, p)
	}

	optionalParams := []string{"field_name", "fixed_value", "message_number",
		"text_symbol_id", "text_pool_owner_type", "subobject_name", "position"}
	for _, p := range optionalParams {
		assertToolHasParam(t, tool, p)
	}
}

func TestSetTranslationXCORegistration(t *testing.T) {
	tools := getRegisteredTools(t)
	tool := assertToolExists(t, tools, "SetTranslationXCO")

	requiredParams := []string{"target_type", "object_name", "language", "transport", "texts"}
	for _, p := range requiredParams {
		assertToolHasParam(t, tool, p)
		assertToolHasRequired(t, tool, p)
	}

	optionalParams := []string{"field_name", "fixed_value", "message_number",
		"text_symbol_id", "text_pool_owner_type", "subobject_name", "position"}
	for _, p := range optionalParams {
		assertToolHasParam(t, tool, p)
	}
}

func TestCompareTranslationsXCORegistration(t *testing.T) {
	tools := getRegisteredTools(t)
	tool := assertToolExists(t, tools, "CompareTranslationsXCO")

	requiredParams := []string{"target_type", "object_name", "source_language", "target_language"}
	for _, p := range requiredParams {
		assertToolHasParam(t, tool, p)
		assertToolHasRequired(t, tool, p)
	}

	optionalParams := []string{"fields", "position"}
	for _, p := range optionalParams {
		assertToolHasParam(t, tool, p)
	}
}

func TestListTranslatableTextsXCORegistration(t *testing.T) {
	tools := getRegisteredTools(t)
	tool := assertToolExists(t, tools, "ListTranslatableTextsXCO")

	requiredParams := []string{"target_type", "object_name"}
	for _, p := range requiredParams {
		assertToolHasParam(t, tool, p)
		assertToolHasRequired(t, tool, p)
	}

	optionalParams := []string{"language", "text_pool_owner_type"}
	for _, p := range optionalParams {
		assertToolHasParam(t, tool, p)
	}
}

func TestListLanguagesRegistration(t *testing.T) {
	tools := getRegisteredTools(t)
	assertToolExists(t, tools, "ListLanguages")
}

// --- Focused Mode Tests ---

func TestI18NToolsInFocusedMode(t *testing.T) {
	focused := focusedToolSet()

	expected := []string{
		"GetTranslationXCO",
		"ListLanguages",
		"ListTranslatableTextsXCO",
	}

	for _, name := range expected {
		if !focused[name] {
			t.Errorf("Tool %q should be in focused tool set", name)
		}
	}
}

// --- Tool Group Tests ---

func TestI18NToolsInGroupN(t *testing.T) {
	groups := toolGroups()

	groupN, ok := groups["N"]
	if !ok {
		t.Fatal("Tool group 'N' not found")
	}

	expected := []string{
		"GetTranslationXCO",
		"SetTranslationXCO",
		"ListLanguages",
		"CompareTranslationsXCO",
		"ListTranslatableTextsXCO",
	}

	groupSet := make(map[string]bool)
	for _, name := range groupN {
		groupSet[name] = true
	}

	for _, name := range expected {
		if !groupSet[name] {
			t.Errorf("Tool %q should be in group N", name)
		}
	}
}

// --- Handler Param Extraction Tests ---
// These test the argument parsing logic without calling WebSocket.

func TestGetTranslationXCO_RequiredParamValidation(t *testing.T) {
	cfg := &Config{
		BaseURL:  "https://sap.example.com:44300",
		Username: "testuser",
		Password: "testpass",
		Client:   "001",
		Language: "EN",
	}
	server := NewServer(cfg)

	tests := []struct {
		name string
		args map[string]any
		want string
	}{
		{
			name: "missing target_type",
			args: map[string]any{"object_name": "ZTEST", "language": "D"},
			want: "target_type is required",
		},
		{
			name: "missing object_name",
			args: map[string]any{"target_type": "data_element", "language": "D"},
			want: "object_name is required",
		},
		{
			name: "missing language",
			args: map[string]any{"target_type": "data_element", "object_name": "ZTEST"},
			want: "language is required",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			request := mcp.CallToolRequest{}
			request.Params.Arguments = tt.args

			result, err := server.handleGetTranslationXCO(context.Background(), request)
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if !result.IsError {
				t.Fatal("expected error result")
			}
			textContent, ok := result.Content[0].(mcp.TextContent)
			if !ok {
				t.Fatalf("expected TextContent, got %T", result.Content[0])
			}
			if textContent.Text != tt.want {
				t.Errorf("got %q, want %q", textContent.Text, tt.want)
			}
		})
	}
}

func TestSetTranslationXCO_RequiredParamValidation(t *testing.T) {
	cfg := &Config{
		BaseURL:  "https://sap.example.com:44300",
		Username: "testuser",
		Password: "testpass",
		Client:   "001",
		Language: "EN",
	}
	server := NewServer(cfg)

	tests := []struct {
		name string
		args map[string]any
		want string
	}{
		{
			name: "missing target_type",
			args: map[string]any{"object_name": "ZTEST", "language": "D", "transport": "A4HK900001",
				"texts": `[{"attribute":"short_field_label","value":"Test"}]`},
			want: "target_type is required",
		},
		{
			name: "missing transport",
			args: map[string]any{"target_type": "data_element", "object_name": "ZTEST", "language": "D",
				"texts": `[{"attribute":"short_field_label","value":"Test"}]`},
			want: "transport is required",
		},
		{
			name: "missing texts",
			args: map[string]any{"target_type": "data_element", "object_name": "ZTEST", "language": "D",
				"transport": "A4HK900001"},
			want: "texts is required (JSON array, e.g. [{\"attribute\":\"short_field_label\",\"value\":\"Vorname\"}])",
		},
		{
			name: "invalid texts JSON",
			args: map[string]any{"target_type": "data_element", "object_name": "ZTEST", "language": "D",
				"transport": "A4HK900001", "texts": "not-json"},
			want: "", // will contain "Failed to parse texts array"
		},
		{
			name: "empty texts array",
			args: map[string]any{"target_type": "data_element", "object_name": "ZTEST", "language": "D",
				"transport": "A4HK900001", "texts": "[]"},
			want: "texts array must not be empty",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			request := mcp.CallToolRequest{}
			request.Params.Arguments = tt.args

			result, err := server.handleSetTranslationXCO(context.Background(), request)
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if !result.IsError {
				t.Fatal("expected error result")
			}
			textContent, ok := result.Content[0].(mcp.TextContent)
			if !ok {
				t.Fatalf("expected TextContent, got %T", result.Content[0])
			}
			if tt.want != "" && textContent.Text != tt.want {
				t.Errorf("got %q, want %q", textContent.Text, tt.want)
			}
			if tt.want == "" && textContent.Text == "" {
				t.Error("expected non-empty error message")
			}
		})
	}
}

func TestCompareTranslationsXCO_RequiredParamValidation(t *testing.T) {
	cfg := &Config{
		BaseURL:  "https://sap.example.com:44300",
		Username: "testuser",
		Password: "testpass",
		Client:   "001",
		Language: "EN",
	}
	server := NewServer(cfg)

	tests := []struct {
		name string
		args map[string]any
		want string
	}{
		{
			name: "missing target_type",
			args: map[string]any{"object_name": "ZTEST", "source_language": "E", "target_language": "D"},
			want: "target_type is required",
		},
		{
			name: "missing source_language",
			args: map[string]any{"target_type": "data_element", "object_name": "ZTEST", "target_language": "D"},
			want: "source_language is required",
		},
		{
			name: "missing target_language",
			args: map[string]any{"target_type": "data_element", "object_name": "ZTEST", "source_language": "E"},
			want: "target_language is required",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			request := mcp.CallToolRequest{}
			request.Params.Arguments = tt.args

			result, err := server.handleCompareTranslationsXCO(context.Background(), request)
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if !result.IsError {
				t.Fatal("expected error result")
			}
			textContent, ok := result.Content[0].(mcp.TextContent)
			if !ok {
				t.Fatalf("expected TextContent, got %T", result.Content[0])
			}
			if textContent.Text != tt.want {
				t.Errorf("got %q, want %q", textContent.Text, tt.want)
			}
		})
	}
}

func TestListTranslatableTextsXCO_RequiredParamValidation(t *testing.T) {
	cfg := &Config{
		BaseURL:  "https://sap.example.com:44300",
		Username: "testuser",
		Password: "testpass",
		Client:   "001",
		Language: "EN",
	}
	server := NewServer(cfg)

	tests := []struct {
		name string
		args map[string]any
		want string
	}{
		{
			name: "missing target_type",
			args: map[string]any{"object_name": "ZTEST"},
			want: "target_type is required",
		},
		{
			name: "missing object_name",
			args: map[string]any{"target_type": "data_element"},
			want: "object_name is required",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			request := mcp.CallToolRequest{}
			request.Params.Arguments = tt.args

			result, err := server.handleListTranslatableTextsXCO(context.Background(), request)
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if !result.IsError {
				t.Fatal("expected error result")
			}
			textContent, ok := result.Content[0].(mcp.TextContent)
			if !ok {
				t.Fatalf("expected TextContent, got %T", result.Content[0])
			}
			if textContent.Text != tt.want {
				t.Errorf("got %q, want %q", textContent.Text, tt.want)
			}
		})
	}
}

// --- Fields Parsing Tests ---

func TestCompareTranslationsXCO_FieldsParsing(t *testing.T) {
	tests := []struct {
		name       string
		fieldsVal  string
		wantFields []string
	}{
		{
			name:       "comma-separated",
			fieldsVal:  "startDate,endDate,status",
			wantFields: []string{"startDate", "endDate", "status"},
		},
		{
			name:       "JSON array format",
			fieldsVal:  `["startDate","endDate"]`,
			wantFields: []string{"startDate", "endDate"},
		},
		{
			name:       "with spaces",
			fieldsVal:  " startDate , endDate ",
			wantFields: []string{"startDate", "endDate"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Replicate the fields parsing logic from the handler
			val := tt.fieldsVal
			val = strings.TrimSpace(val)
			val = strings.TrimPrefix(val, "[")
			val = strings.TrimSuffix(val, "]")
			val = strings.ReplaceAll(val, `"`, "")
			var fields []string
			for _, f := range strings.Split(val, ",") {
				if f = strings.TrimSpace(f); f != "" {
					fields = append(fields, f)
				}
			}

			if len(fields) != len(tt.wantFields) {
				t.Fatalf("got %d fields, want %d: %v", len(fields), len(tt.wantFields), fields)
			}
			for i, f := range fields {
				if f != tt.wantFields[i] {
					t.Errorf("field[%d] = %q, want %q", i, f, tt.wantFields[i])
				}
			}
		})
	}
}

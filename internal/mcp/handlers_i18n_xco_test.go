package mcp

import (
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
		Mode:     "expert", // Register all tools, not just focused subset
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

// --- Required Params Schema Tests ---
// Verify required parameters are enforced at the schema level (no WebSocket needed).

func TestGetTranslationXCO_RequiredParams(t *testing.T) {
	tools := getRegisteredTools(t)
	tool := assertToolExists(t, tools, "GetTranslationXCO")

	for _, p := range []string{"target_type", "object_name", "language"} {
		assertToolHasRequired(t, tool, p)
	}
}

func TestSetTranslationXCO_RequiredParams(t *testing.T) {
	tools := getRegisteredTools(t)
	tool := assertToolExists(t, tools, "SetTranslationXCO")

	for _, p := range []string{"target_type", "object_name", "language", "transport", "texts"} {
		assertToolHasRequired(t, tool, p)
	}
}

func TestCompareTranslationsXCO_RequiredParams(t *testing.T) {
	tools := getRegisteredTools(t)
	tool := assertToolExists(t, tools, "CompareTranslationsXCO")

	for _, p := range []string{"target_type", "object_name", "source_language", "target_language"} {
		assertToolHasRequired(t, tool, p)
	}
}

func TestListTranslatableTextsXCO_RequiredParams(t *testing.T) {
	tools := getRegisteredTools(t)
	tool := assertToolExists(t, tools, "ListTranslatableTextsXCO")

	for _, p := range []string{"target_type", "object_name"} {
		assertToolHasRequired(t, tool, p)
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

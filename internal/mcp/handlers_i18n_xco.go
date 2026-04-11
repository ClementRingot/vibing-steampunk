// Package mcp provides the MCP server implementation for ABAP ADT tools.
// handlers_i18n_xco.go contains handlers for XCO-based i18n operations via ZADT_VSP WebSocket.
// These tools complement the existing ADT REST-based i18n tools (handlers_i18n.go) and
// cover object types not reachable via ADT REST: CDS/DDLS fields, DDLX annotations, domains.
package mcp

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"

	"github.com/mark3labs/mcp-go/mcp"
	"github.com/oisee/vibing-steampunk/pkg/adt"
)

// handleGetTranslationXCO reads translated texts for any ABAP object via XCO_CP_I18N.
func (s *Server) handleGetTranslationXCO(ctx context.Context, request mcp.CallToolRequest) (*mcp.CallToolResult, error) {
	if errResult := s.ensureWSConnected(ctx, "GetTranslationXCO"); errResult != nil {
		return errResult, nil
	}

	targetType, ok := request.GetArguments()["target_type"].(string)
	if !ok || targetType == "" {
		return newToolResultError("target_type is required"), nil
	}

	objectName, ok := request.GetArguments()["object_name"].(string)
	if !ok || objectName == "" {
		return newToolResultError("object_name is required"), nil
	}

	language, ok := request.GetArguments()["language"].(string)
	if !ok || language == "" {
		return newToolResultError("language is required"), nil
	}

	params := adt.I18NGetParams{
		TargetType: targetType,
		ObjectName: strings.ToUpper(objectName),
		Language:   strings.ToUpper(language),
	}

	if v, ok := request.GetArguments()["field_name"].(string); ok && v != "" {
		params.FieldName = v
	}
	if v, ok := request.GetArguments()["fixed_value"].(string); ok && v != "" {
		params.FixedValue = v
	}
	if v, ok := request.GetArguments()["message_number"].(string); ok && v != "" {
		params.MessageNumber = v
	}
	if v, ok := request.GetArguments()["text_symbol_id"].(string); ok && v != "" {
		params.TextSymbolID = v
	}
	if v, ok := request.GetArguments()["text_pool_owner_type"].(string); ok && v != "" {
		params.TextPoolOwnerType = v
	}

	result, err := s.amdpWSClient.GetTranslationViaXCO(ctx, params)
	if err != nil {
		return newToolResultError(fmt.Sprintf("GetTranslationXCO failed: %v", err)), nil
	}

	jsonBytes, err := json.MarshalIndent(result, "", "  ")
	if err != nil {
		return newToolResultError(fmt.Sprintf("Failed to format result: %v", err)), nil
	}
	return mcp.NewToolResultText(string(jsonBytes)), nil
}

// handleSetTranslationXCO writes translated texts for an ABAP object via XCO_CP_I18N.
func (s *Server) handleSetTranslationXCO(ctx context.Context, request mcp.CallToolRequest) (*mcp.CallToolResult, error) {
	if errResult := s.ensureWSConnected(ctx, "SetTranslationXCO"); errResult != nil {
		return errResult, nil
	}

	targetType, ok := request.GetArguments()["target_type"].(string)
	if !ok || targetType == "" {
		return newToolResultError("target_type is required"), nil
	}

	objectName, ok := request.GetArguments()["object_name"].(string)
	if !ok || objectName == "" {
		return newToolResultError("object_name is required"), nil
	}

	language, ok := request.GetArguments()["language"].(string)
	if !ok || language == "" {
		return newToolResultError("language is required"), nil
	}

	transport, ok := request.GetArguments()["transport"].(string)
	if !ok || transport == "" {
		return newToolResultError("transport is required"), nil
	}

	textsStr, ok := request.GetArguments()["texts"].(string)
	if !ok || textsStr == "" {
		return newToolResultError("texts is required (JSON array, e.g. [{\"attribute\":\"short_field_label\",\"value\":\"Vorname\"}])"), nil
	}

	var texts []adt.I18NText
	if err := json.Unmarshal([]byte(textsStr), &texts); err != nil {
		return newToolResultError(fmt.Sprintf("Failed to parse texts array: %v", err)), nil
	}

	if len(texts) == 0 {
		return newToolResultError("texts array must not be empty"), nil
	}

	params := adt.I18NSetParams{
		TargetType: targetType,
		ObjectName: strings.ToUpper(objectName),
		Language:   strings.ToUpper(language),
		Transport:  strings.ToUpper(transport),
		Texts:      texts,
	}

	if v, ok := request.GetArguments()["field_name"].(string); ok && v != "" {
		params.FieldName = v
	}
	if v, ok := request.GetArguments()["fixed_value"].(string); ok && v != "" {
		params.FixedValue = v
	}
	if v, ok := request.GetArguments()["message_number"].(string); ok && v != "" {
		params.MessageNumber = v
	}
	if v, ok := request.GetArguments()["text_symbol_id"].(string); ok && v != "" {
		params.TextSymbolID = v
	}
	if v, ok := request.GetArguments()["text_pool_owner_type"].(string); ok && v != "" {
		params.TextPoolOwnerType = v
	}

	if err := s.amdpWSClient.SetTranslationViaXCO(ctx, params); err != nil {
		return newToolResultError(fmt.Sprintf("SetTranslationXCO failed: %v", err)), nil
	}

	return mcp.NewToolResultText(fmt.Sprintf(
		"Translation updated: %s/%s language=%s transport=%s (%d text(s))",
		targetType, strings.ToUpper(objectName), strings.ToUpper(language),
		strings.ToUpper(transport), len(texts),
	)), nil
}

// handleListLanguages returns the list of SAP languages installed in the system.
func (s *Server) handleListLanguages(ctx context.Context, request mcp.CallToolRequest) (*mcp.CallToolResult, error) {
	if errResult := s.ensureWSConnected(ctx, "ListLanguages"); errResult != nil {
		return errResult, nil
	}

	langs, err := s.amdpWSClient.ListInstalledLanguages(ctx)
	if err != nil {
		return newToolResultError(fmt.Sprintf("ListLanguages failed: %v", err)), nil
	}

	if len(langs) == 0 {
		return mcp.NewToolResultText("No installed languages found."), nil
	}

	jsonBytes, err := json.MarshalIndent(langs, "", "  ")
	if err != nil {
		return newToolResultError(fmt.Sprintf("Failed to format result: %v", err)), nil
	}
	return mcp.NewToolResultText(string(jsonBytes)), nil
}

// handleCompareTranslationsXCO compares translations between two languages for an ABAP object.
func (s *Server) handleCompareTranslationsXCO(ctx context.Context, request mcp.CallToolRequest) (*mcp.CallToolResult, error) {
	if errResult := s.ensureWSConnected(ctx, "CompareTranslationsXCO"); errResult != nil {
		return errResult, nil
	}

	targetType, ok := request.GetArguments()["target_type"].(string)
	if !ok || targetType == "" {
		return newToolResultError("target_type is required"), nil
	}

	objectName, ok := request.GetArguments()["object_name"].(string)
	if !ok || objectName == "" {
		return newToolResultError("object_name is required"), nil
	}

	sourceLang, ok := request.GetArguments()["source_language"].(string)
	if !ok || sourceLang == "" {
		return newToolResultError("source_language is required"), nil
	}

	targetLang, ok := request.GetArguments()["target_language"].(string)
	if !ok || targetLang == "" {
		return newToolResultError("target_language is required"), nil
	}

	params := adt.I18NCompareParams{
		TargetType:     targetType,
		ObjectName:     strings.ToUpper(objectName),
		SourceLanguage: strings.ToUpper(sourceLang),
		TargetLanguage: strings.ToUpper(targetLang),
	}

	// Accept fields as comma-separated string or JSON array string
	if fieldsVal, ok := request.GetArguments()["fields"].(string); ok && fieldsVal != "" {
		fieldsVal = strings.TrimSpace(fieldsVal)
		// Handle both "field1,field2" and ["field1","field2"] formats
		fieldsVal = strings.TrimPrefix(fieldsVal, "[")
		fieldsVal = strings.TrimSuffix(fieldsVal, "]")
		fieldsVal = strings.ReplaceAll(fieldsVal, `"`, "")
		for _, f := range strings.Split(fieldsVal, ",") {
			if f = strings.TrimSpace(f); f != "" {
				params.Fields = append(params.Fields, f)
			}
		}
	}

	result, err := s.amdpWSClient.CompareTranslationsViaXCO(ctx, params)
	if err != nil {
		return newToolResultError(fmt.Sprintf("CompareTranslationsXCO failed: %v", err)), nil
	}

	jsonBytes, err := json.MarshalIndent(result, "", "  ")
	if err != nil {
		return newToolResultError(fmt.Sprintf("Failed to format result: %v", err)), nil
	}
	return mcp.NewToolResultText(string(jsonBytes)), nil
}

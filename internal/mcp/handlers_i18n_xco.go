// Package mcp provides the MCP server implementation for ABAP ADT tools.
// handlers_i18n_xco.go contains handlers for XCO-based i18n operations via ZADT_VSP WebSocket.
// These tools complement the existing ADT REST-based i18n tools (handlers_i18n.go) and
// cover object types not reachable via ADT REST: CDS/DDLS fields, DDLX annotations, domains.
package mcp

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"strings"

	"github.com/mark3labs/mcp-go/mcp"
	"github.com/oisee/vibing-steampunk/pkg/adt"
)

// isoToSAPLanguage maps ISO 639-1 two-letter codes to SAP 1-char SPRAS codes.
// If the input is already 1 character, it is returned as-is (assumed to be SAP code).
var isoToSAPLanguage = map[string]string{
	"EN": "E", "DE": "D", "FR": "F", "ES": "S", "IT": "I",
	"PT": "P", "NL": "N", "JA": "J", "ZH": "1", "KO": "3",
	"RU": "R", "PL": "L", "TR": "T", "SV": "V", "DA": "K",
	"FI": "U", "NO": "O", "CS": "C", "HU": "H", "AR": "A",
	"HE": "B", "TH": "2", "BG": "W", "HR": "6", "SK": "Q",
	"SL": "5", "UK": "8", "RO": "4", "SR": "0", "EL": "G",
}

// toSAPLanguage converts an ISO 2-char or SAP 1-char language code to SAP SPRAS format.
func toSAPLanguage(code string) string {
	code = strings.ToUpper(strings.TrimSpace(code))
	if len(code) <= 1 {
		return code
	}
	if sap, ok := isoToSAPLanguage[code]; ok {
		return sap
	}
	// Unknown 2-char code: return first char as fallback (matches CONV spras() behavior)
	return code[:1]
}

// jsonMarshalNoEscape marshals v to indented JSON without HTML-escaping
// characters like &, <, > (which json.Marshal escapes by default).
func jsonMarshalNoEscape(v any) ([]byte, error) {
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	enc.SetIndent("", "  ")
	if err := enc.Encode(v); err != nil {
		return nil, err
	}
	// Encode appends a trailing newline; trim it for consistency with MarshalIndent
	return bytes.TrimRight(buf.Bytes(), "\n"), nil
}

// routeI18nAction routes "i18n" sub-actions for XCO-based translation operations.
func (s *Server) routeI18nAction(ctx context.Context, action, objectType, objectName string, params map[string]any) (*mcp.CallToolResult, bool, error) {
	if action != "i18n" {
		return nil, false, nil
	}
	switch objectType {
	case "GET_TRANSLATION":
		return s.callHandler(ctx, s.handleGetTranslationXCO, params)
	case "SET_TRANSLATION":
		return s.callHandler(ctx, s.handleSetTranslationXCO, params)
	case "LIST_LANGUAGES":
		return s.callHandler(ctx, s.handleListLanguages, params)
	case "COMPARE_TRANSLATIONS":
		return s.callHandler(ctx, s.handleCompareTranslationsXCO, params)
	case "LIST_TEXTS":
		return s.callHandler(ctx, s.handleListTranslatableTextsXCO, params)
	}
	return nil, false, nil
}

// handleGetTranslationXCO reads translated texts for any ABAP object via XCO I18N.
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
		Language:   toSAPLanguage(language),
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
	if v, ok := request.GetArguments()["subobject_name"].(string); ok && v != "" {
		params.SubobjectName = v
	}
	if v, ok := request.GetArguments()["position"].(string); ok && v != "" {
		params.Position = v
	}

	result, err := s.amdpWSClient.GetTranslationViaXCO(ctx, params)
	if err != nil {
		return newToolResultError(fmt.Sprintf("GetTranslationXCO failed: %v", err)), nil
	}

	jsonBytes, err := jsonMarshalNoEscape(result)
	if err != nil {
		return newToolResultError(fmt.Sprintf("Failed to format result: %v", err)), nil
	}
	return mcp.NewToolResultText(string(jsonBytes)), nil
}

// handleSetTranslationXCO writes translated texts for an ABAP object via XCO I18N.
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
		Language:   toSAPLanguage(language),
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
	if v, ok := request.GetArguments()["subobject_name"].(string); ok && v != "" {
		params.SubobjectName = v
	}
	if v, ok := request.GetArguments()["position"].(string); ok && v != "" {
		params.Position = v
	}

	if err := s.amdpWSClient.SetTranslationViaXCO(ctx, params); err != nil {
		return newToolResultError(fmt.Sprintf("SetTranslationXCO failed: %v", err)), nil
	}

	return mcp.NewToolResultText(fmt.Sprintf(
		"Translation updated: %s/%s language=%s transport=%s (%d text(s))",
		targetType, strings.ToUpper(objectName), toSAPLanguage(language),
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

	jsonBytes, err := jsonMarshalNoEscape(langs)
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
		SourceLanguage: toSAPLanguage(sourceLang),
		TargetLanguage: toSAPLanguage(targetLang),
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
	if v, ok := request.GetArguments()["position"].(string); ok && v != "" {
		params.Position = v
	}

	result, err := s.amdpWSClient.CompareTranslationsViaXCO(ctx, params)
	if err != nil {
		return newToolResultError(fmt.Sprintf("CompareTranslationsXCO failed: %v", err)), nil
	}

	jsonBytes, err := jsonMarshalNoEscape(result)
	if err != nil {
		return newToolResultError(fmt.Sprintf("Failed to format result: %v", err)), nil
	}
	return mcp.NewToolResultText(string(jsonBytes)), nil
}

// handleListTranslatableTextsXCO lists all translatable texts for an ABAP object.
func (s *Server) handleListTranslatableTextsXCO(ctx context.Context, request mcp.CallToolRequest) (*mcp.CallToolResult, error) {
if errResult := s.ensureWSConnected(ctx, "ListTranslatableTextsXCO"); errResult != nil {
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

params := adt.I18NListTextsParams{
TargetType: targetType,
ObjectName: strings.ToUpper(objectName),
}

if v, ok := request.GetArguments()["language"].(string); ok && v != "" {
params.Language = toSAPLanguage(v)
}
if v, ok := request.GetArguments()["text_pool_owner_type"].(string); ok && v != "" {
params.TextPoolOwnerType = v
}

result, err := s.amdpWSClient.ListTranslatableTextsViaXCO(ctx, params)
if err != nil {
return newToolResultError(fmt.Sprintf("ListTranslatableTextsXCO failed: %v", err)), nil
}

jsonBytes, err := jsonMarshalNoEscape(result)
if err != nil {
return newToolResultError(fmt.Sprintf("Failed to format result: %v", err)), nil
}
return mcp.NewToolResultText(string(jsonBytes)), nil
}
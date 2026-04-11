package adt

import (
	"context"
	"encoding/json"
	"fmt"
	"time"
)

// --- XCO I18N Types ---

// I18NGetParams contains parameters for reading translations via XCO_CP_I18N.
type I18NGetParams struct {
	TargetType        string   `json:"target_type"`
	ObjectName        string   `json:"object_name"`
	Language          string   `json:"language"`
	FieldName         string   `json:"field_name,omitempty"`
	FixedValue        string   `json:"fixed_value,omitempty"`
	MessageNumber     string   `json:"message_number,omitempty"`
	TextSymbolID      string   `json:"text_symbol_id,omitempty"`
	TextPoolOwnerType string   `json:"text_pool_owner_type,omitempty"`
	TextAttributes    []string `json:"text_attributes,omitempty"`
}

// I18NSetParams contains parameters for writing translations via XCO_CP_I18N.
type I18NSetParams struct {
	TargetType        string     `json:"target_type"`
	ObjectName        string     `json:"object_name"`
	Language          string     `json:"language"`
	Transport         string     `json:"transport"`
	FieldName         string     `json:"field_name,omitempty"`
	FixedValue        string     `json:"fixed_value,omitempty"`
	MessageNumber     string     `json:"message_number,omitempty"`
	TextSymbolID      string     `json:"text_symbol_id,omitempty"`
	TextPoolOwnerType string     `json:"text_pool_owner_type,omitempty"`
	Texts             []I18NText `json:"texts"`
}

// I18NText represents a single text attribute/value pair.
type I18NText struct {
	Attribute string `json:"attribute"`
	Value     string `json:"value"`
}

// I18NTranslationResult contains the result of a get_translation request.
type I18NTranslationResult struct {
	TargetType string     `json:"target_type"`
	ObjectName string     `json:"object_name"`
	Language   string     `json:"language"`
	Texts      []I18NText `json:"texts"`
}

// LanguageInfo describes a language installed in the SAP system.
type LanguageInfo struct {
	SAPCode string `json:"sap_code"`
	ISOCode string `json:"iso_code"`
	Name    string `json:"name"`
}

// I18NCompareParams contains parameters for comparing translations between two languages.
type I18NCompareParams struct {
	TargetType     string   `json:"target_type"`
	ObjectName     string   `json:"object_name"`
	SourceLanguage string   `json:"source_language"`
	TargetLanguage string   `json:"target_language"`
	Fields         []string `json:"fields,omitempty"`
}

// I18NComparisonResult contains the comparison result between two languages.
type I18NComparisonResult struct {
	TargetType     string             `json:"target_type"`
	ObjectName     string             `json:"object_name"`
	SourceLanguage string             `json:"source_language"`
	TargetLanguage string             `json:"target_language"`
	Items          []I18NComparedItem `json:"items"`
}

// I18NComparedItem represents one translated element compared between two languages.
type I18NComparedItem struct {
	FieldOrKey    string     `json:"field_or_key"`
	SourceTexts   []I18NText `json:"source_texts"`
	TargetTexts   []I18NText `json:"target_texts"`
	HasDifference bool       `json:"has_difference"`
}

// --- XCO I18N WebSocket Methods ---

// GetTranslationViaXCO retrieves translated texts for an ABAP object via XCO_CP_I18N.
// Requires ZADT_VSP WebSocket connection with i18n service deployed.
// Supports target types: data_element, domain, data_definition, metadata_extension,
// message_class, text_pool.
func (c *AMDPWebSocketClient) GetTranslationViaXCO(ctx context.Context, params I18NGetParams) (*I18NTranslationResult, error) {
	p := map[string]any{
		"target_type": params.TargetType,
		"object_name": params.ObjectName,
		"language":    params.Language,
	}
	if params.FieldName != "" {
		p["field_name"] = params.FieldName
	}
	if params.FixedValue != "" {
		p["fixed_value"] = params.FixedValue
	}
	if params.MessageNumber != "" {
		p["message_number"] = params.MessageNumber
	}
	if params.TextSymbolID != "" {
		p["text_symbol_id"] = params.TextSymbolID
	}
	if params.TextPoolOwnerType != "" {
		p["text_pool_owner_type"] = params.TextPoolOwnerType
	}
	if len(params.TextAttributes) > 0 {
		p["text_attributes"] = params.TextAttributes
	}

	resp, err := c.SendDomainRequest(ctx, "i18n", "get_translation", p, 30*time.Second)
	if err != nil {
		return nil, fmt.Errorf("GetTranslationViaXCO: %w", err)
	}
	if !resp.Success {
		if resp.Error != nil {
			return nil, fmt.Errorf("%s: %s", resp.Error.Code, resp.Error.Message)
		}
		return nil, fmt.Errorf("get_translation failed")
	}

	var result I18NTranslationResult
	if err := json.Unmarshal(resp.Data, &result); err != nil {
		return nil, fmt.Errorf("parse get_translation response: %w", err)
	}
	return &result, nil
}

// SetTranslationViaXCO writes translated texts for an ABAP object via XCO_CP_I18N.
// Requires a valid transport request (except for local/test objects, use $TMP or similar).
// Requires ZADT_VSP WebSocket connection with i18n service deployed.
func (c *AMDPWebSocketClient) SetTranslationViaXCO(ctx context.Context, params I18NSetParams) error {
	p := map[string]any{
		"target_type": params.TargetType,
		"object_name": params.ObjectName,
		"language":    params.Language,
		"transport":   params.Transport,
		"texts":       params.Texts,
	}
	if params.FieldName != "" {
		p["field_name"] = params.FieldName
	}
	if params.FixedValue != "" {
		p["fixed_value"] = params.FixedValue
	}
	if params.MessageNumber != "" {
		p["message_number"] = params.MessageNumber
	}
	if params.TextSymbolID != "" {
		p["text_symbol_id"] = params.TextSymbolID
	}
	if params.TextPoolOwnerType != "" {
		p["text_pool_owner_type"] = params.TextPoolOwnerType
	}

	resp, err := c.SendDomainRequest(ctx, "i18n", "set_translation", p, 60*time.Second)
	if err != nil {
		return fmt.Errorf("SetTranslationViaXCO: %w", err)
	}
	if !resp.Success {
		if resp.Error != nil {
			return fmt.Errorf("%s: %s", resp.Error.Code, resp.Error.Message)
		}
		return fmt.Errorf("set_translation failed")
	}
	return nil
}

// ListInstalledLanguages returns the list of languages installed in the SAP system.
// Requires ZADT_VSP WebSocket connection with i18n service deployed.
func (c *AMDPWebSocketClient) ListInstalledLanguages(ctx context.Context) ([]LanguageInfo, error) {
	resp, err := c.SendDomainRequest(ctx, "i18n", "list_languages", map[string]any{}, 30*time.Second)
	if err != nil {
		return nil, fmt.Errorf("ListInstalledLanguages: %w", err)
	}
	if !resp.Success {
		if resp.Error != nil {
			return nil, fmt.Errorf("%s: %s", resp.Error.Code, resp.Error.Message)
		}
		return nil, fmt.Errorf("list_languages failed")
	}

	var result struct {
		Languages []LanguageInfo `json:"languages"`
	}
	if err := json.Unmarshal(resp.Data, &result); err != nil {
		return nil, fmt.Errorf("parse list_languages response: %w", err)
	}
	return result.Languages, nil
}

// CompareTranslationsViaXCO compares translations between two languages for an ABAP object.
// Requires ZADT_VSP WebSocket connection with i18n service deployed.
// For data_definition, provide a list of field names to compare.
// For data_element, all text attributes (short/medium/long label, heading) are compared.
func (c *AMDPWebSocketClient) CompareTranslationsViaXCO(ctx context.Context, params I18NCompareParams) (*I18NComparisonResult, error) {
	p := map[string]any{
		"target_type":     params.TargetType,
		"object_name":     params.ObjectName,
		"source_language": params.SourceLanguage,
		"target_language": params.TargetLanguage,
	}
	if len(params.Fields) > 0 {
		p["fields"] = params.Fields
	}

	resp, err := c.SendDomainRequest(ctx, "i18n", "compare_translations", p, 30*time.Second)
	if err != nil {
		return nil, fmt.Errorf("CompareTranslationsViaXCO: %w", err)
	}
	if !resp.Success {
		if resp.Error != nil {
			return nil, fmt.Errorf("%s: %s", resp.Error.Code, resp.Error.Message)
		}
		return nil, fmt.Errorf("compare_translations failed")
	}

	var result I18NComparisonResult
	if err := json.Unmarshal(resp.Data, &result); err != nil {
		return nil, fmt.Errorf("parse compare_translations response: %w", err)
	}
	return &result, nil
}

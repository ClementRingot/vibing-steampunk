package adt

import (
	"encoding/json"
	"testing"
)

// --- I18NGetParams JSON serialization tests ---

func TestI18NGetParamsJSON_AllFields(t *testing.T) {
	params := I18NGetParams{
		TargetType:        "metadata_extension",
		ObjectName:        "ZVACATION_REQUEST",
		Language:          "D",
		FieldName:         "startDate",
		FixedValue:        "DE",
		MessageNumber:     "005",
		TextSymbolID:      "001",
		TextPoolOwnerType: "class",
		SubobjectName:     "ZSUBOBJ",
		Position:          "2",
		TextAttributes:    []string{"endusertext_label"},
	}

	data, err := json.Marshal(params)
	if err != nil {
		t.Fatalf("Marshal failed: %v", err)
	}

	var m map[string]any
	if err := json.Unmarshal(data, &m); err != nil {
		t.Fatalf("Unmarshal failed: %v", err)
	}

	checks := map[string]string{
		"target_type":          "metadata_extension",
		"object_name":         "ZVACATION_REQUEST",
		"language":            "D",
		"field_name":          "startDate",
		"fixed_value":         "DE",
		"message_number":      "005",
		"text_symbol_id":      "001",
		"text_pool_owner_type": "class",
		"subobject_name":      "ZSUBOBJ",
		"position":            "2",
	}
	for key, want := range checks {
		got, ok := m[key].(string)
		if !ok {
			t.Errorf("key %q missing or not string in JSON", key)
			continue
		}
		if got != want {
			t.Errorf("%s = %q, want %q", key, got, want)
		}
	}
}

func TestI18NGetParamsJSON_OmitEmpty(t *testing.T) {
	params := I18NGetParams{
		TargetType: "data_element",
		ObjectName: "ZFIRST_NAME",
		Language:   "E",
	}

	data, err := json.Marshal(params)
	if err != nil {
		t.Fatalf("Marshal failed: %v", err)
	}

	var m map[string]any
	if err := json.Unmarshal(data, &m); err != nil {
		t.Fatalf("Unmarshal failed: %v", err)
	}

	// These optional fields should be omitted
	omitted := []string{"field_name", "fixed_value", "message_number", "text_symbol_id",
		"text_pool_owner_type", "subobject_name", "position", "text_attributes"}
	for _, key := range omitted {
		if _, ok := m[key]; ok {
			t.Errorf("key %q should be omitted when empty", key)
		}
	}

	// Required fields must be present
	for _, key := range []string{"target_type", "object_name", "language"} {
		if _, ok := m[key]; !ok {
			t.Errorf("key %q should be present", key)
		}
	}
}

// --- I18NSetParams JSON serialization tests ---

func TestI18NSetParamsJSON_AllFields(t *testing.T) {
	params := I18NSetParams{
		TargetType:        "application_log_object",
		ObjectName:        "ZLOG_OBJ",
		Language:          "D",
		Transport:         "A4HK900123",
		FieldName:         "field1",
		SubobjectName:     "ZSUBOBJ",
		Position:          "3",
		TextPoolOwnerType: "function_group",
		Texts: []I18NText{
			{Attribute: "short_description", Value: "Kurzbeschreibung"},
		},
	}

	data, err := json.Marshal(params)
	if err != nil {
		t.Fatalf("Marshal failed: %v", err)
	}

	var m map[string]any
	if err := json.Unmarshal(data, &m); err != nil {
		t.Fatalf("Unmarshal failed: %v", err)
	}

	if m["subobject_name"] != "ZSUBOBJ" {
		t.Errorf("subobject_name = %v, want ZSUBOBJ", m["subobject_name"])
	}
	if m["position"] != "3" {
		t.Errorf("position = %v, want 3", m["position"])
	}
	if m["transport"] != "A4HK900123" {
		t.Errorf("transport = %v, want A4HK900123", m["transport"])
	}

	texts, ok := m["texts"].([]any)
	if !ok || len(texts) != 1 {
		t.Fatalf("texts should have 1 entry, got %v", m["texts"])
	}
	entry := texts[0].(map[string]any)
	if entry["attribute"] != "short_description" {
		t.Errorf("texts[0].attribute = %v, want short_description", entry["attribute"])
	}
}

func TestI18NSetParamsJSON_OmitEmpty(t *testing.T) {
	params := I18NSetParams{
		TargetType: "data_element",
		ObjectName: "ZTEST",
		Language:   "E",
		Transport:  "A4HK900001",
		Texts:      []I18NText{{Attribute: "short_field_label", Value: "Test"}},
	}

	data, err := json.Marshal(params)
	if err != nil {
		t.Fatalf("Marshal failed: %v", err)
	}

	var m map[string]any
	if err := json.Unmarshal(data, &m); err != nil {
		t.Fatalf("Unmarshal failed: %v", err)
	}

	omitted := []string{"field_name", "fixed_value", "message_number", "text_symbol_id",
		"text_pool_owner_type", "subobject_name", "position"}
	for _, key := range omitted {
		if _, ok := m[key]; ok {
			t.Errorf("key %q should be omitted when empty", key)
		}
	}
}

// --- I18NCompareParams JSON serialization tests ---

func TestI18NCompareParamsJSON_WithPosition(t *testing.T) {
	params := I18NCompareParams{
		TargetType:     "metadata_extension",
		ObjectName:     "ZVACATION_REQUEST",
		SourceLanguage: "E",
		TargetLanguage: "D",
		Fields:         []string{"startDate", "endDate"},
		Position:       "1",
	}

	data, err := json.Marshal(params)
	if err != nil {
		t.Fatalf("Marshal failed: %v", err)
	}

	var m map[string]any
	if err := json.Unmarshal(data, &m); err != nil {
		t.Fatalf("Unmarshal failed: %v", err)
	}

	if m["position"] != "1" {
		t.Errorf("position = %v, want 1", m["position"])
	}
	if m["source_language"] != "E" {
		t.Errorf("source_language = %v, want E", m["source_language"])
	}

	fields, ok := m["fields"].([]any)
	if !ok || len(fields) != 2 {
		t.Fatalf("fields should have 2 entries, got %v", m["fields"])
	}
}

func TestI18NCompareParamsJSON_OmitEmpty(t *testing.T) {
	params := I18NCompareParams{
		TargetType:     "data_element",
		ObjectName:     "ZTEST_DTEL",
		SourceLanguage: "E",
		TargetLanguage: "D",
	}

	data, err := json.Marshal(params)
	if err != nil {
		t.Fatalf("Marshal failed: %v", err)
	}

	var m map[string]any
	if err := json.Unmarshal(data, &m); err != nil {
		t.Fatalf("Unmarshal failed: %v", err)
	}

	if _, ok := m["position"]; ok {
		t.Error("position should be omitted when empty")
	}
	if _, ok := m["fields"]; ok {
		t.Error("fields should be omitted when empty")
	}
}

// --- I18NListTextsParams JSON serialization tests ---

func TestI18NListTextsParamsJSON(t *testing.T) {
	params := I18NListTextsParams{
		TargetType:        "text_pool",
		ObjectName:        "ZCL_MY_CLASS",
		Language:          "D",
		TextPoolOwnerType: "class",
	}

	data, err := json.Marshal(params)
	if err != nil {
		t.Fatalf("Marshal failed: %v", err)
	}

	var m map[string]any
	if err := json.Unmarshal(data, &m); err != nil {
		t.Fatalf("Unmarshal failed: %v", err)
	}

	if m["target_type"] != "text_pool" {
		t.Errorf("target_type = %v, want text_pool", m["target_type"])
	}
	if m["text_pool_owner_type"] != "class" {
		t.Errorf("text_pool_owner_type = %v, want class", m["text_pool_owner_type"])
	}
}

func TestI18NListTextsParamsJSON_OmitEmpty(t *testing.T) {
	params := I18NListTextsParams{
		TargetType: "domain",
		ObjectName: "ZSTATUS",
	}

	data, err := json.Marshal(params)
	if err != nil {
		t.Fatalf("Marshal failed: %v", err)
	}

	var m map[string]any
	if err := json.Unmarshal(data, &m); err != nil {
		t.Fatalf("Unmarshal failed: %v", err)
	}

	if _, ok := m["language"]; ok {
		t.Error("language should be omitted when empty")
	}
	if _, ok := m["text_pool_owner_type"]; ok {
		t.Error("text_pool_owner_type should be omitted when empty")
	}
}

// --- I18NText roundtrip ---

func TestI18NTextRoundtrip(t *testing.T) {
	texts := []I18NText{
		{Attribute: "short_field_label", Value: "Vorname"},
		{Attribute: "long_field_label", Value: "Vorname des Mitarbeiters"},
	}

	data, err := json.Marshal(texts)
	if err != nil {
		t.Fatalf("Marshal failed: %v", err)
	}

	var parsed []I18NText
	if err := json.Unmarshal(data, &parsed); err != nil {
		t.Fatalf("Unmarshal failed: %v", err)
	}

	if len(parsed) != 2 {
		t.Fatalf("Expected 2 texts, got %d", len(parsed))
	}
	if parsed[0].Attribute != "short_field_label" || parsed[0].Value != "Vorname" {
		t.Errorf("texts[0] = %+v, want {short_field_label, Vorname}", parsed[0])
	}
	if parsed[1].Attribute != "long_field_label" || parsed[1].Value != "Vorname des Mitarbeiters" {
		t.Errorf("texts[1] = %+v, want {long_field_label, Vorname des Mitarbeiters}", parsed[1])
	}
}

// --- I18NListTextEntry ---

func TestI18NListTextEntryJSON(t *testing.T) {
	entry := I18NListTextEntry{
		Level:     "field",
		FieldName: "startDate",
		Attribute: "endusertext_label",
		Value:     "Start Date",
	}

	data, err := json.Marshal(entry)
	if err != nil {
		t.Fatalf("Marshal failed: %v", err)
	}

	var m map[string]any
	if err := json.Unmarshal(data, &m); err != nil {
		t.Fatalf("Unmarshal failed: %v", err)
	}

	if m["level"] != "field" {
		t.Errorf("level = %v, want field", m["level"])
	}
	if m["field_name"] != "startDate" {
		t.Errorf("field_name = %v, want startDate", m["field_name"])
	}
	if m["attribute"] != "endusertext_label" {
		t.Errorf("attribute = %v, want endusertext_label", m["attribute"])
	}
	if m["value"] != "Start Date" {
		t.Errorf("value = %v, want Start Date", m["value"])
	}
}

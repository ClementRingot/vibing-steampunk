"! <p class="shorttext synchronized">VSP I18N Service - XCO Translation API</p>
"! Provides translation read/write for ABAP objects via XCO_CP_I18N.
"! Supports: data_element, domain, data_definition (DDLS), metadata_extension (DDLX),
"! message_class, text_pool.
"! Requires: SAP_BASIS >= 7.57 — XCO_CP_I18N released C1 on-premise and BTP.
CLASS zcl_vsp_i18n_service DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_vsp_service.

  PRIVATE SECTION.
    "! Generic text contribution structure compatible with XCO set_translation.
    "! NOTE: if the compiler rejects the table type in set_translation calls,
    "!       replace ty_text_contribution / tt_text_contributions with the exact
    "!       XCO-released type found via F2 on the method signature in ADT.
    TYPES:
      BEGIN OF ty_text_contribution,
        io_attribute TYPE REF TO if_xco_i18n_text_attribute,
        iv_text      TYPE string,
      END OF ty_text_contribution,
      tt_text_contributions TYPE STANDARD TABLE OF ty_text_contribution
                            WITH DEFAULT KEY.

    METHODS handle_get_translation
      IMPORTING is_message         TYPE zif_vsp_service=>ty_message
      RETURNING VALUE(rs_response) TYPE zif_vsp_service=>ty_response.

    METHODS handle_set_translation
      IMPORTING is_message         TYPE zif_vsp_service=>ty_message
      RETURNING VALUE(rs_response) TYPE zif_vsp_service=>ty_response.

    METHODS handle_list_languages
      IMPORTING is_message         TYPE zif_vsp_service=>ty_message
      RETURNING VALUE(rs_response) TYPE zif_vsp_service=>ty_response.

    METHODS handle_compare_translations
      IMPORTING is_message         TYPE zif_vsp_service=>ty_message
      RETURNING VALUE(rs_response) TYPE zif_vsp_service=>ty_response.

    "! Parse a JSON string array (content between [ ]) into a string table.
    METHODS parse_string_array
      IMPORTING iv_content        TYPE string
      RETURNING VALUE(rt_values)  TYPE string_table.

    "! Append {"attribute":"...","value":"..."} to an existing JSON array fragment.
    METHODS append_text_entry
      IMPORTING iv_json           TYPE string
                iv_attribute      TYPE string
                iv_value          TYPE string
      RETURNING VALUE(rv_json)    TYPE string.

    "! Map a text attribute name to the XCO data_element text attribute object.
    METHODS get_de_text_attr
      IMPORTING iv_name              TYPE string
      RETURNING VALUE(ro_attr)       TYPE REF TO if_xco_i18n_text_attribute.

    "! Map a text attribute name to the XCO data_definition->field text attribute.
    METHODS get_ddls_field_attr
      IMPORTING iv_name              TYPE string
      RETURNING VALUE(ro_attr)       TYPE REF TO if_xco_i18n_text_attribute.

ENDCLASS.


CLASS zcl_vsp_i18n_service IMPLEMENTATION.

  METHOD zif_vsp_service~get_domain.
    rv_domain = 'i18n'.
  ENDMETHOD.

  METHOD zif_vsp_service~handle_message.
    CASE is_message-action.
      WHEN 'get_translation'.
        rs_response = handle_get_translation( is_message ).
      WHEN 'set_translation'.
        rs_response = handle_set_translation( is_message ).
      WHEN 'list_languages'.
        rs_response = handle_list_languages( is_message ).
      WHEN 'compare_translations'.
        rs_response = handle_compare_translations( is_message ).
      WHEN OTHERS.
        rs_response = zcl_vsp_utils=>build_error(
          iv_id      = is_message-id
          iv_code    = 'UNKNOWN_ACTION'
          iv_message = |Action '{ is_message-action }' not supported by i18n domain|
        ).
    ENDCASE.
  ENDMETHOD.

  METHOD zif_vsp_service~on_disconnect.
    " No session state for i18n domain
  ENDMETHOD.

  METHOD handle_get_translation.
    DATA(lv_target_type) = zcl_vsp_utils=>extract_param( iv_params = is_message-params iv_name = 'target_type' ).
    DATA(lv_object_name) = zcl_vsp_utils=>extract_param( iv_params = is_message-params iv_name = 'object_name' ).
    DATA(lv_language)    = zcl_vsp_utils=>extract_param( iv_params = is_message-params iv_name = 'language' ).
    DATA(lv_field_name)  = zcl_vsp_utils=>extract_param( iv_params = is_message-params iv_name = 'field_name' ).
    DATA(lv_fixed_value) = zcl_vsp_utils=>extract_param( iv_params = is_message-params iv_name = 'fixed_value' ).
    DATA(lv_msg_number)  = zcl_vsp_utils=>extract_param( iv_params = is_message-params iv_name = 'message_number' ).
    DATA(lv_text_sym_id) = zcl_vsp_utils=>extract_param( iv_params = is_message-params iv_name = 'text_symbol_id' ).
    DATA(lv_pool_type)   = zcl_vsp_utils=>extract_param( iv_params = is_message-params iv_name = 'text_pool_owner_type' ).
    DATA lt_attributes   TYPE string_table.
    DATA lv_texts_json   TYPE string.

    IF lv_target_type IS INITIAL OR lv_object_name IS INITIAL OR lv_language IS INITIAL.
      rs_response = zcl_vsp_utils=>build_error(
        iv_id      = is_message-id
        iv_code    = 'MISSING_PARAM'
        iv_message = 'target_type, object_name, and language are required'
      ).
      RETURN.
    ENDIF.

    TRANSLATE lv_object_name TO UPPER CASE.
    TRANSLATE lv_language TO UPPER CASE.

    " Parse optional text_attributes JSON array, e.g. ["short_field_label","heading"]
    FIND PCRE '"text_attributes"\s*:\s*\[([^\]]*)\]' IN is_message-params SUBMATCHES DATA(lv_attrs_str).
    IF sy-subrc = 0 AND lv_attrs_str IS NOT INITIAL.
      lt_attributes = parse_string_array( lv_attrs_str ).
    ENDIF.

    TRY.
        DATA(lo_language) = xco_cp=>language( CONV sxco_langu( lv_language ) ).

        CASE lv_target_type.

          WHEN 'data_element'.
            DATA(lo_de_target) = xco_cp_i18n=>target->data_element->object( CONV sxco_ar_object_name( lv_object_name ) ).
            DATA(lo_de_trans)  = lo_de_target->get_translation( io_language = lo_language ).
            DATA lt_de_attrs   TYPE string_table.
            IF lt_attributes IS INITIAL.
              APPEND 'short_field_label'  TO lt_de_attrs.
              APPEND 'medium_field_label' TO lt_de_attrs.
              APPEND 'long_field_label'   TO lt_de_attrs.
              APPEND 'heading'            TO lt_de_attrs.
            ELSE.
              lt_de_attrs = lt_attributes.
            ENDIF.
            LOOP AT lt_de_attrs INTO DATA(lv_de_attr).
              DATA(lo_de_attr) = get_de_text_attr( lv_de_attr ).
              CHECK lo_de_attr IS BOUND.
              DATA(lv_de_val)  = lo_de_trans->get_text( io_attribute = lo_de_attr ).
              lv_texts_json = append_text_entry( iv_json = lv_texts_json iv_attribute = lv_de_attr iv_value = lv_de_val ).
            ENDLOOP.

          WHEN 'domain'.
            DATA(lo_dom_target) = xco_cp_i18n=>target->domain->fixed_value(
              iv_domain_name = CONV sxco_ar_object_name( lv_object_name )
              iv_lower_limit = CONV #( lv_fixed_value )
            ).
            DATA(lo_dom_trans) = lo_dom_target->get_translation( io_language = lo_language ).
            DATA(lv_dom_val)   = lo_dom_trans->get_text( io_attribute = xco_cp_domain=>text_attribute->fixed_value_description ).
            lv_texts_json = append_text_entry( iv_json = lv_texts_json iv_attribute = 'fixed_value_description' iv_value = lv_dom_val ).

          WHEN 'data_definition'.
            IF lv_field_name IS INITIAL.
              " Entity-level (whole CDS view label)
              DATA(lo_ddls_entity) = xco_cp_i18n=>target->data_definition->entity( CONV sxco_ar_object_name( lv_object_name ) ).
              DATA(lo_ddls_e_trans) = lo_ddls_entity->get_translation( io_language = lo_language ).
              DATA(lv_entity_val) = lo_ddls_e_trans->get_text( io_attribute = xco_cp_data_definition=>text_attribute->field->endusertext_label ).
              lv_texts_json = append_text_entry( iv_json = lv_texts_json iv_attribute = 'endusertext_label' iv_value = lv_entity_val ).
            ELSE.
              TRANSLATE lv_field_name TO LOWER CASE.
              DATA(lo_ddls_field) = xco_cp_i18n=>target->data_definition->field(
                iv_entity_name = CONV sxco_ar_object_name( lv_object_name )
                iv_field_name  = CONV #( lv_field_name )
              ).
              DATA(lo_ddls_f_trans) = lo_ddls_field->get_translation( io_language = lo_language ).
              DATA lt_ddls_attrs TYPE string_table.
              IF lt_attributes IS INITIAL.
                APPEND 'endusertext_label'     TO lt_ddls_attrs.
                APPEND 'endusertext_heading'   TO lt_ddls_attrs.
                APPEND 'endusertext_quickinfo' TO lt_ddls_attrs.
              ELSE.
                lt_ddls_attrs = lt_attributes.
              ENDIF.
              LOOP AT lt_ddls_attrs INTO DATA(lv_ddls_attr).
                DATA(lo_ddls_attr) = get_ddls_field_attr( lv_ddls_attr ).
                CHECK lo_ddls_attr IS BOUND.
                DATA(lv_ddls_val) = lo_ddls_f_trans->get_text( io_attribute = lo_ddls_attr ).
                lv_texts_json = append_text_entry( iv_json = lv_texts_json iv_attribute = lv_ddls_attr iv_value = lv_ddls_val ).
              ENDLOOP.
            ENDIF.

          WHEN 'metadata_extension'.
            IF lv_field_name IS INITIAL.
              rs_response = zcl_vsp_utils=>build_error(
                iv_id = is_message-id iv_code = 'MISSING_PARAM'
                iv_message = 'field_name is required for metadata_extension target' ).
              RETURN.
            ENDIF.
            TRANSLATE lv_field_name TO LOWER CASE.
            DATA(lo_ddlx_target) = xco_cp_i18n=>target->metadata_extension->field(
              iv_metadata_extension_name = CONV sxco_ar_object_name( lv_object_name )
              iv_field_name              = CONV #( lv_field_name )
            ).
            DATA(lo_ddlx_trans) = lo_ddlx_target->get_translation( io_language = lo_language ).
            DATA(lv_ddlx_val) = lo_ddlx_trans->get_text( io_attribute = xco_cp_metadata_extension=>text_attribute->field->ui_lineitem_label( 1 ) ).
            lv_texts_json = append_text_entry( iv_json = lv_texts_json iv_attribute = 'ui_lineitem_label' iv_value = lv_ddlx_val ).

          WHEN 'message_class'.
            IF lv_msg_number IS INITIAL.
              rs_response = zcl_vsp_utils=>build_error(
                iv_id = is_message-id iv_code = 'MISSING_PARAM'
                iv_message = 'message_number is required for message_class target' ).
              RETURN.
            ENDIF.
            DATA(lo_mc_target) = xco_cp_i18n=>target->message_class->message(
              iv_message_class_name = CONV sxco_ar_object_name( lv_object_name )
              iv_message_number     = CONV #( lv_msg_number )
            ).
            DATA(lo_mc_trans) = lo_mc_target->get_translation( io_language = lo_language ).
            DATA(lv_mc_val) = lo_mc_trans->get_text( io_attribute = xco_cp_message_class=>text_attribute->message_short_text ).
            lv_texts_json = append_text_entry( iv_json = lv_texts_json iv_attribute = 'message_short_text' iv_value = lv_mc_val ).

          WHEN 'text_pool'.
            DATA lv_tp_text TYPE string.
            IF lv_pool_type = 'class' OR lv_pool_type IS INITIAL.
              DATA(lo_cls_tp) = xco_cp_i18n=>target->text_pool->class_text_symbol(
                iv_class_name     = CONV sxco_ar_object_name( lv_object_name )
                iv_text_symbol_id = CONV #( lv_text_sym_id )
              ).
              DATA(lo_cls_trans) = lo_cls_tp->get_translation( io_language = lo_language ).
              lv_tp_text = lo_cls_trans->get_text( io_attribute = xco_cp_text_pool=>text_attribute->text_element_text ).
            ELSE.
              DATA(lo_fg_tp) = xco_cp_i18n=>target->text_pool->function_group_text_symbol(
                iv_function_group_name = CONV sxco_ar_object_name( lv_object_name )
                iv_text_symbol_id      = CONV #( lv_text_sym_id )
              ).
              DATA(lo_fg_trans) = lo_fg_tp->get_translation( io_language = lo_language ).
              lv_tp_text = lo_fg_trans->get_text( io_attribute = xco_cp_text_pool=>text_attribute->text_element_text ).
            ENDIF.
            lv_texts_json = append_text_entry( iv_json = lv_texts_json iv_attribute = 'text_element_text' iv_value = lv_tp_text ).

          WHEN OTHERS.
            rs_response = zcl_vsp_utils=>build_error(
              iv_id      = is_message-id
              iv_code    = 'UNSUPPORTED_TARGET'
              iv_message = |Target type '{ lv_target_type }' is not supported. Valid: data_element, domain, data_definition, metadata_extension, message_class, text_pool|
            ).
            RETURN.
        ENDCASE.

        DATA(lv_data) = zcl_vsp_utils=>json_obj( zcl_vsp_utils=>json_join( VALUE #(
          ( zcl_vsp_utils=>json_str( iv_key = 'target_type' iv_value = lv_target_type ) )
          ( zcl_vsp_utils=>json_str( iv_key = 'object_name' iv_value = lv_object_name ) )
          ( zcl_vsp_utils=>json_str( iv_key = 'language'    iv_value = lv_language    ) )
          ( |"texts":[{ lv_texts_json }]| )
        ) ) ).
        rs_response = zcl_vsp_utils=>build_success( iv_id = is_message-id iv_data = lv_data ).

      CATCH cx_root INTO DATA(lx_error).
        rs_response = zcl_vsp_utils=>build_error(
          iv_id = is_message-id iv_code = 'I18N_ERROR' iv_message = lx_error->get_text( ) ).
    ENDTRY.
  ENDMETHOD.

  METHOD handle_set_translation.
    DATA(lv_target_type) = zcl_vsp_utils=>extract_param( iv_params = is_message-params iv_name = 'target_type' ).
    DATA(lv_object_name) = zcl_vsp_utils=>extract_param( iv_params = is_message-params iv_name = 'object_name' ).
    DATA(lv_language)    = zcl_vsp_utils=>extract_param( iv_params = is_message-params iv_name = 'language' ).
    DATA(lv_transport)   = zcl_vsp_utils=>extract_param( iv_params = is_message-params iv_name = 'transport' ).
    DATA(lv_field_name)  = zcl_vsp_utils=>extract_param( iv_params = is_message-params iv_name = 'field_name' ).
    DATA(lv_fixed_value) = zcl_vsp_utils=>extract_param( iv_params = is_message-params iv_name = 'fixed_value' ).
    DATA(lv_msg_number)  = zcl_vsp_utils=>extract_param( iv_params = is_message-params iv_name = 'message_number' ).
    DATA(lv_text_sym_id) = zcl_vsp_utils=>extract_param( iv_params = is_message-params iv_name = 'text_symbol_id' ).
    DATA(lv_pool_type)   = zcl_vsp_utils=>extract_param( iv_params = is_message-params iv_name = 'text_pool_owner_type' ).

    IF lv_target_type IS INITIAL OR lv_object_name IS INITIAL OR lv_language IS INITIAL OR lv_transport IS INITIAL.
      rs_response = zcl_vsp_utils=>build_error(
        iv_id = is_message-id iv_code = 'MISSING_PARAM'
        iv_message = 'target_type, object_name, language, and transport are required' ).
      RETURN.
    ENDIF.

    TRANSLATE lv_object_name TO UPPER CASE.
    TRANSLATE lv_language TO UPPER CASE.
    TRANSLATE lv_transport TO UPPER CASE.

    " Extract texts array: [{"attribute":"...","value":"..."},...]
    FIND PCRE '"texts"\s*:\s*(\[[^\]]*\])' IN is_message-params SUBMATCHES DATA(lv_texts_str).
    IF sy-subrc <> 0 OR lv_texts_str IS INITIAL.
      rs_response = zcl_vsp_utils=>build_error(
        iv_id = is_message-id iv_code = 'MISSING_PARAM'
        iv_message = 'texts array is required' ).
      RETURN.
    ENDIF.

    " Parse {"attribute":"...","value":"..."} entries from the array
    DATA lt_attrs TYPE string_table.
    DATA lt_vals  TYPE string_table.
    FIND ALL OCCURRENCES OF PCRE '\{[^}]+\}' IN lv_texts_str RESULTS DATA(lt_obj_matches).
    LOOP AT lt_obj_matches INTO DATA(ls_obj_match).
      DATA(lv_obj_json) = lv_texts_str+ls_obj_match-offset(ls_obj_match-length).
      APPEND zcl_vsp_utils=>extract_param( iv_params = lv_obj_json iv_name = 'attribute' ) TO lt_attrs.
      APPEND zcl_vsp_utils=>extract_param( iv_params = lv_obj_json iv_name = 'value' )     TO lt_vals.
    ENDLOOP.

    IF lt_attrs IS INITIAL.
      rs_response = zcl_vsp_utils=>build_error(
        iv_id = is_message-id iv_code = 'MISSING_PARAM'
        iv_message = 'texts array is empty or could not be parsed' ).
      RETURN.
    ENDIF.

    " Build typed texts table from parsed pairs
    DATA lt_texts TYPE tt_text_contributions.
    DATA lv_attr  TYPE string.
    DATA lv_val   TYPE string.
    DATA lo_attr  TYPE REF TO if_xco_i18n_text_attribute.

    TRY.
        DATA(lo_language)        = xco_cp=>language( CONV sxco_langu( lv_language ) ).
        DATA(lo_change_scenario) = xco_cp_cts=>transport->for( CONV #( lv_transport ) ).

        " Build texts table — attribute mapping depends on target_type
        DO lines( lt_attrs ) TIMES.
          DATA(lv_idx) = sy-index.
          READ TABLE lt_attrs INDEX lv_idx INTO lv_attr.
          READ TABLE lt_vals  INDEX lv_idx INTO lv_val.
          CLEAR lo_attr.

          CASE lv_target_type.
            WHEN 'data_element'.
              lo_attr = get_de_text_attr( lv_attr ).
            WHEN 'data_definition'.
              lo_attr = get_ddls_field_attr( lv_attr ).
            WHEN 'domain'.
              lo_attr = xco_cp_domain=>text_attribute->fixed_value_description.
            WHEN 'message_class'.
              lo_attr = xco_cp_message_class=>text_attribute->message_short_text.
            WHEN 'text_pool'.
              lo_attr = xco_cp_text_pool=>text_attribute->text_element_text.
          ENDCASE.

          IF lo_attr IS BOUND.
            APPEND VALUE #( io_attribute = lo_attr iv_text = lv_val ) TO lt_texts.
          ENDIF.
        ENDDO.

        IF lt_texts IS INITIAL.
          rs_response = zcl_vsp_utils=>build_error(
            iv_id = is_message-id iv_code = 'INVALID_ATTRS'
            iv_message = |No valid text attributes found for target_type '{ lv_target_type }'| ).
          RETURN.
        ENDIF.

        " Route to the correct XCO target and call set_translation
        CASE lv_target_type.

          WHEN 'data_element'.
            DATA(lo_de_set) = xco_cp_i18n=>target->data_element->object( CONV sxco_ar_object_name( lv_object_name ) ).
            lo_de_set->set_translation( it_texts = lt_texts io_language = lo_language io_change_scenario = lo_change_scenario ).

          WHEN 'domain'.
            DATA(lo_dom_set) = xco_cp_i18n=>target->domain->fixed_value(
              iv_domain_name = CONV sxco_ar_object_name( lv_object_name )
              iv_lower_limit = CONV #( lv_fixed_value )
            ).
            lo_dom_set->set_translation( it_texts = lt_texts io_language = lo_language io_change_scenario = lo_change_scenario ).

          WHEN 'data_definition'.
            IF lv_field_name IS INITIAL.
              rs_response = zcl_vsp_utils=>build_error(
                iv_id = is_message-id iv_code = 'MISSING_PARAM'
                iv_message = 'field_name is required for data_definition set_translation' ).
              RETURN.
            ENDIF.
            TRANSLATE lv_field_name TO LOWER CASE.
            DATA(lo_ddls_set) = xco_cp_i18n=>target->data_definition->field(
              iv_entity_name = CONV sxco_ar_object_name( lv_object_name )
              iv_field_name  = CONV #( lv_field_name )
            ).
            lo_ddls_set->set_translation( it_texts = lt_texts io_language = lo_language io_change_scenario = lo_change_scenario ).

          WHEN 'message_class'.
            DATA(lo_mc_set) = xco_cp_i18n=>target->message_class->message(
              iv_message_class_name = CONV sxco_ar_object_name( lv_object_name )
              iv_message_number     = CONV #( lv_msg_number )
            ).
            lo_mc_set->set_translation( it_texts = lt_texts io_language = lo_language io_change_scenario = lo_change_scenario ).

          WHEN 'text_pool'.
            IF lv_pool_type = 'class' OR lv_pool_type IS INITIAL.
              DATA(lo_cls_set) = xco_cp_i18n=>target->text_pool->class_text_symbol(
                iv_class_name     = CONV sxco_ar_object_name( lv_object_name )
                iv_text_symbol_id = CONV #( lv_text_sym_id )
              ).
              lo_cls_set->set_translation( it_texts = lt_texts io_language = lo_language io_change_scenario = lo_change_scenario ).
            ELSE.
              DATA(lo_fg_set) = xco_cp_i18n=>target->text_pool->function_group_text_symbol(
                iv_function_group_name = CONV sxco_ar_object_name( lv_object_name )
                iv_text_symbol_id      = CONV #( lv_text_sym_id )
              ).
              lo_fg_set->set_translation( it_texts = lt_texts io_language = lo_language io_change_scenario = lo_change_scenario ).
            ENDIF.

          WHEN OTHERS.
            rs_response = zcl_vsp_utils=>build_error(
              iv_id = is_message-id iv_code = 'UNSUPPORTED_TARGET'
              iv_message = |set_translation: target_type '{ lv_target_type }' is not supported| ).
            RETURN.
        ENDCASE.

        DATA(lv_data) = zcl_vsp_utils=>json_obj( zcl_vsp_utils=>json_join( VALUE #(
          ( zcl_vsp_utils=>json_str(  iv_key = 'target_type' iv_value = lv_target_type ) )
          ( zcl_vsp_utils=>json_str(  iv_key = 'object_name' iv_value = lv_object_name ) )
          ( zcl_vsp_utils=>json_str(  iv_key = 'language'    iv_value = lv_language    ) )
          ( zcl_vsp_utils=>json_str(  iv_key = 'transport'   iv_value = lv_transport   ) )
          ( zcl_vsp_utils=>json_bool( iv_key = 'success'     iv_value = abap_true      ) )
        ) ) ).
        rs_response = zcl_vsp_utils=>build_success( iv_id = is_message-id iv_data = lv_data ).

      CATCH cx_root INTO DATA(lx_error).
        rs_response = zcl_vsp_utils=>build_error(
          iv_id = is_message-id iv_code = 'I18N_SET_ERROR' iv_message = lx_error->get_text( ) ).
    ENDTRY.
  ENDMETHOD.

  METHOD handle_list_languages.
    TRY.
        " Query installed SAP languages with ISO codes and localized names
        SELECT a~sprsl AS sap_code,
               a~laiso AS iso_code,
               b~sptxt AS name
          FROM t002 AS a
          LEFT JOIN t002t AS b
            ON  b~sprsl = a~sprsl
            AND b~spras = @sy-langu
          INTO TABLE @DATA(lt_langs)
          ORDER BY a~sprsl.

        DATA lv_langs_json TYPE string.
        LOOP AT lt_langs INTO DATA(ls_lang).
          IF lv_langs_json IS NOT INITIAL.
            lv_langs_json = lv_langs_json && |,|.
          ENDIF.
          lv_langs_json = lv_langs_json && zcl_vsp_utils=>json_obj( zcl_vsp_utils=>json_join( VALUE #(
            ( zcl_vsp_utils=>json_str( iv_key = 'sap_code' iv_value = ls_lang-sap_code ) )
            ( zcl_vsp_utils=>json_str( iv_key = 'iso_code' iv_value = ls_lang-iso_code ) )
            ( zcl_vsp_utils=>json_str( iv_key = 'name'     iv_value = ls_lang-name     ) )
          ) ) ).
        ENDLOOP.

        DATA(lv_data) = zcl_vsp_utils=>json_obj( |"languages":[{ lv_langs_json }]| ).
        rs_response = zcl_vsp_utils=>build_success( iv_id = is_message-id iv_data = lv_data ).

      CATCH cx_root INTO DATA(lx_error).
        rs_response = zcl_vsp_utils=>build_error(
          iv_id = is_message-id iv_code = 'LANG_ERROR' iv_message = lx_error->get_text( ) ).
    ENDTRY.
  ENDMETHOD.

  METHOD handle_compare_translations.
    DATA(lv_target_type) = zcl_vsp_utils=>extract_param( iv_params = is_message-params iv_name = 'target_type' ).
    DATA(lv_object_name) = zcl_vsp_utils=>extract_param( iv_params = is_message-params iv_name = 'object_name' ).
    DATA(lv_source_lang) = zcl_vsp_utils=>extract_param( iv_params = is_message-params iv_name = 'source_language' ).
    DATA(lv_target_lang) = zcl_vsp_utils=>extract_param( iv_params = is_message-params iv_name = 'target_language' ).
    DATA lt_fields       TYPE string_table.
    DATA lv_items_json   TYPE string.

    IF lv_target_type IS INITIAL OR lv_object_name IS INITIAL OR lv_source_lang IS INITIAL OR lv_target_lang IS INITIAL.
      rs_response = zcl_vsp_utils=>build_error(
        iv_id = is_message-id iv_code = 'MISSING_PARAM'
        iv_message = 'target_type, object_name, source_language, and target_language are required' ).
      RETURN.
    ENDIF.

    TRANSLATE lv_object_name TO UPPER CASE.
    TRANSLATE lv_source_lang TO UPPER CASE.
    TRANSLATE lv_target_lang TO UPPER CASE.

    " Parse optional fields array
    FIND PCRE '"fields"\s*:\s*\[([^\]]*)\]' IN is_message-params SUBMATCHES DATA(lv_fields_str).
    IF sy-subrc = 0 AND lv_fields_str IS NOT INITIAL.
      lt_fields = parse_string_array( lv_fields_str ).
    ENDIF.

    TRY.
        DATA(lo_src_lang) = xco_cp=>language( CONV sxco_langu( lv_source_lang ) ).
        DATA(lo_tgt_lang) = xco_cp=>language( CONV sxco_langu( lv_target_lang ) ).

        CASE lv_target_type.

          WHEN 'data_definition'.
            IF lt_fields IS INITIAL.
              rs_response = zcl_vsp_utils=>build_error(
                iv_id = is_message-id iv_code = 'MISSING_PARAM'
                iv_message = 'fields array required for data_definition compare_translations' ).
              RETURN.
            ENDIF.

            LOOP AT lt_fields INTO DATA(lv_field).
              DATA(lv_fld_lower) = lv_field.
              TRANSLATE lv_fld_lower TO LOWER CASE.

              DATA(lo_fld) = xco_cp_i18n=>target->data_definition->field(
                iv_entity_name = CONV sxco_ar_object_name( lv_object_name )
                iv_field_name  = CONV #( lv_fld_lower )
              ).
              DATA(lo_fld_src_t) = lo_fld->get_translation( io_language = lo_src_lang ).
              DATA(lo_fld_tgt_t) = lo_fld->get_translation( io_language = lo_tgt_lang ).

              DATA(lv_src_lbl) = lo_fld_src_t->get_text( io_attribute = xco_cp_data_definition=>text_attribute->field->endusertext_label ).
              DATA(lv_tgt_lbl) = lo_fld_tgt_t->get_text( io_attribute = xco_cp_data_definition=>text_attribute->field->endusertext_label ).
              DATA(lv_has_diff) = xsdbool( lv_src_lbl <> lv_tgt_lbl OR lv_tgt_lbl IS INITIAL ).

              DATA(lv_src_json) = append_text_entry( iv_json = '' iv_attribute = 'endusertext_label' iv_value = lv_src_lbl ).
              DATA(lv_tgt_json) = append_text_entry( iv_json = '' iv_attribute = 'endusertext_label' iv_value = lv_tgt_lbl ).

              IF lv_items_json IS NOT INITIAL. lv_items_json = lv_items_json && |,|. ENDIF.
              lv_items_json = lv_items_json && zcl_vsp_utils=>json_obj( zcl_vsp_utils=>json_join( VALUE #(
                ( zcl_vsp_utils=>json_str(  iv_key = 'field_or_key'    iv_value = lv_field    ) )
                ( |"source_texts":[{ lv_src_json }]| )
                ( |"target_texts":[{ lv_tgt_json }]| )
                ( zcl_vsp_utils=>json_bool( iv_key = 'has_difference'  iv_value = lv_has_diff ) )
              ) ) ).
            ENDLOOP.

          WHEN 'data_element'.
            DATA(lo_cmp_de) = xco_cp_i18n=>target->data_element->object( CONV sxco_ar_object_name( lv_object_name ) ).
            DATA(lo_cmp_de_src_t) = lo_cmp_de->get_translation( io_language = lo_src_lang ).
            DATA(lo_cmp_de_tgt_t) = lo_cmp_de->get_translation( io_language = lo_tgt_lang ).

            DATA lt_cmp_de_attrs TYPE string_table.
            APPEND 'short_field_label'  TO lt_cmp_de_attrs.
            APPEND 'medium_field_label' TO lt_cmp_de_attrs.
            APPEND 'long_field_label'   TO lt_cmp_de_attrs.
            APPEND 'heading'            TO lt_cmp_de_attrs.

            DATA lv_src_texts_json TYPE string.
            DATA lv_tgt_texts_json TYPE string.
            DATA lv_any_diff       TYPE abap_bool VALUE abap_false.

            LOOP AT lt_cmp_de_attrs INTO DATA(lv_cmp_attr).
              DATA(lo_cmp_attr) = get_de_text_attr( lv_cmp_attr ).
              CHECK lo_cmp_attr IS BOUND.
              DATA(lv_src_t) = lo_cmp_de_src_t->get_text( io_attribute = lo_cmp_attr ).
              DATA(lv_tgt_t) = lo_cmp_de_tgt_t->get_text( io_attribute = lo_cmp_attr ).
              IF lv_src_t <> lv_tgt_t OR lv_tgt_t IS INITIAL.
                lv_any_diff = abap_true.
              ENDIF.
              lv_src_texts_json = append_text_entry( iv_json = lv_src_texts_json iv_attribute = lv_cmp_attr iv_value = lv_src_t ).
              lv_tgt_texts_json = append_text_entry( iv_json = lv_tgt_texts_json iv_attribute = lv_cmp_attr iv_value = lv_tgt_t ).
            ENDLOOP.

            lv_items_json = zcl_vsp_utils=>json_obj( zcl_vsp_utils=>json_join( VALUE #(
              ( zcl_vsp_utils=>json_str(  iv_key = 'field_or_key'   iv_value = lv_object_name ) )
              ( |"source_texts":[{ lv_src_texts_json }]| )
              ( |"target_texts":[{ lv_tgt_texts_json }]| )
              ( zcl_vsp_utils=>json_bool( iv_key = 'has_difference' iv_value = lv_any_diff    ) )
            ) ) ).

          WHEN OTHERS.
            rs_response = zcl_vsp_utils=>build_error(
              iv_id = is_message-id iv_code = 'UNSUPPORTED_TARGET'
              iv_message = |compare_translations: target_type '{ lv_target_type }' not supported. Use: data_element, data_definition (with fields[])| ).
            RETURN.
        ENDCASE.

        DATA(lv_data) = zcl_vsp_utils=>json_obj( zcl_vsp_utils=>json_join( VALUE #(
          ( zcl_vsp_utils=>json_str( iv_key = 'target_type'     iv_value = lv_target_type ) )
          ( zcl_vsp_utils=>json_str( iv_key = 'object_name'     iv_value = lv_object_name ) )
          ( zcl_vsp_utils=>json_str( iv_key = 'source_language' iv_value = lv_source_lang ) )
          ( zcl_vsp_utils=>json_str( iv_key = 'target_language' iv_value = lv_target_lang ) )
          ( |"items":[{ lv_items_json }]| )
        ) ) ).
        rs_response = zcl_vsp_utils=>build_success( iv_id = is_message-id iv_data = lv_data ).

      CATCH cx_root INTO DATA(lx_error).
        rs_response = zcl_vsp_utils=>build_error(
          iv_id = is_message-id iv_code = 'COMPARE_ERROR' iv_message = lx_error->get_text( ) ).
    ENDTRY.
  ENDMETHOD.

  METHOD parse_string_array.
    " Extract quoted string values from a JSON array content fragment
    " Input: '"short_field_label","heading"'  →  [ "short_field_label", "heading" ]
    FIND ALL OCCURRENCES OF PCRE '"([^"]*)"' IN iv_content RESULTS DATA(lt_matches).
    LOOP AT lt_matches INTO DATA(ls_match).
      DATA(lv_off) = ls_match-submatches[ 1 ]-offset.
      DATA(lv_len) = ls_match-submatches[ 1 ]-length.
      APPEND iv_content+lv_off(lv_len) TO rt_values.
    ENDLOOP.
  ENDMETHOD.

  METHOD append_text_entry.
    DATA(lv_entry) = zcl_vsp_utils=>json_obj( zcl_vsp_utils=>json_join( VALUE #(
      ( zcl_vsp_utils=>json_str( iv_key = 'attribute' iv_value = iv_attribute ) )
      ( zcl_vsp_utils=>json_str( iv_key = 'value'     iv_value = iv_value     ) )
    ) ) ).
    rv_json = COND #( WHEN iv_json IS INITIAL THEN lv_entry ELSE |{ iv_json },{ lv_entry }| ).
  ENDMETHOD.

  METHOD get_de_text_attr.
    CASE iv_name.
      WHEN 'short_field_label'.  ro_attr = xco_cp_data_element=>text_attribute->short_field_label.
      WHEN 'medium_field_label'. ro_attr = xco_cp_data_element=>text_attribute->medium_field_label.
      WHEN 'long_field_label'.   ro_attr = xco_cp_data_element=>text_attribute->long_field_label.
      WHEN 'heading'.            ro_attr = xco_cp_data_element=>text_attribute->heading.
    ENDCASE.
  ENDMETHOD.

  METHOD get_ddls_field_attr.
    CASE iv_name.
      WHEN 'endusertext_label'.     ro_attr = xco_cp_data_definition=>text_attribute->field->endusertext_label.
      WHEN 'endusertext_heading'.   ro_attr = xco_cp_data_definition=>text_attribute->field->endusertext_heading.
      WHEN 'endusertext_quickinfo'. ro_attr = xco_cp_data_definition=>text_attribute->field->endusertext_quickinfo.
    ENDCASE.
  ENDMETHOD.

ENDCLASS.

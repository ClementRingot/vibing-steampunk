"! <p class="shorttext synchronized">VSP I18N Service - XCO Translation API</p>
CLASS zcl_vsp_i18n_service DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_vsp_service.

  PRIVATE SECTION.
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

    METHODS handle_list_texts
      IMPORTING is_message         TYPE zif_vsp_service=>ty_message
      RETURNING VALUE(rs_response) TYPE zif_vsp_service=>ty_response.

    METHODS parse_string_array
      IMPORTING iv_content        TYPE string
      RETURNING VALUE(rt_values)  TYPE string_table.

    METHODS append_text_entry
      IMPORTING iv_json           TYPE string
                iv_attribute      TYPE string
                iv_value          TYPE string
      RETURNING VALUE(rv_json)    TYPE string.

    METHODS get_de_text_attr
      IMPORTING iv_name              TYPE string
      RETURNING VALUE(ro_attr)       TYPE REF TO cl_xco_dtel_text_attribute.

    METHODS get_ddls_field_attr
      IMPORTING iv_name              TYPE string
      RETURNING VALUE(ro_attr)       TYPE REF TO cl_xco_ddef_fld_text_attribute.

    METHODS get_me_field_attr
      IMPORTING iv_name              TYPE string
                iv_position          TYPE i DEFAULT 1
      RETURNING VALUE(ro_attr)       TYPE REF TO cl_xco_me_fld_text_attribute.

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
      WHEN 'list_texts'.
        rs_response = handle_list_texts( is_message ).
      WHEN OTHERS.
        rs_response = zcl_vsp_utils=>build_error(
          iv_id      = is_message-id
          iv_code    = 'UNKNOWN_ACTION'
          iv_message = |Action '{ is_message-action }' not supported by i18n domain|
        ).
    ENDCASE.
  ENDMETHOD.

  METHOD zif_vsp_service~on_disconnect.
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
    DATA(lv_subobj_name) = zcl_vsp_utils=>extract_param( iv_params = is_message-params iv_name = 'subobject_name' ).
    DATA(lv_position_s)  = zcl_vsp_utils=>extract_param( iv_params = is_message-params iv_name = 'position' ).

    IF lv_target_type IS INITIAL OR lv_object_name IS INITIAL OR lv_language IS INITIAL.
      rs_response = zcl_vsp_utils=>build_error(
        iv_id = is_message-id iv_code = 'MISSING_PARAM'
        iv_message = 'target_type, object_name, and language are required' ).
      RETURN.
    ENDIF.

    TRANSLATE lv_object_name TO UPPER CASE.
    TRANSLATE lv_language TO UPPER CASE.

    DATA(lv_position) = 1.
    IF lv_position_s IS NOT INITIAL.
      lv_position = CONV i( lv_position_s ).
    ENDIF.

    TRY.
        DATA(lo_language) = xco_cp=>language( CONV spras( lv_language ) ).
        DATA lv_json TYPE string.

        CASE lv_target_type.

          WHEN 'data_element'.
            DATA(lo_de) = xco_i18n=>target->data_element->object( CONV sxco_ad_object_name( lv_object_name ) ).
            DATA lt_dtel_attrs TYPE sxco_t_dtel_text_attributes.
            DATA lo_de_ta TYPE REF TO cl_xco_dtel_text_attribute.
            DATA lt_de_names TYPE string_table.
            APPEND 'short_field_label'   TO lt_de_names.
            APPEND 'medium_field_label'  TO lt_de_names.
            APPEND 'long_field_label'    TO lt_de_names.
            APPEND 'heading_field_label' TO lt_de_names.
            LOOP AT lt_de_names INTO DATA(lv_de_name).
              lo_de_ta = get_de_text_attr( lv_de_name ).
              IF lo_de_ta IS BOUND. APPEND lo_de_ta TO lt_dtel_attrs. ENDIF.
            ENDLOOP.
            DATA(lo_de_result) = lo_de->get_translation( io_language = lo_language it_text_attributes = lt_dtel_attrs ).
            DATA(lv_de_idx) = 0.
            LOOP AT lo_de_result->texts INTO DATA(lo_de_text).
              lv_de_idx = lv_de_idx + 1.
              READ TABLE lt_de_names INDEX lv_de_idx INTO DATA(lv_de_attr_name).
              lv_json = append_text_entry( iv_json = lv_json iv_attribute = lv_de_attr_name iv_value = lo_de_text->get_string_value( ) ).
            ENDLOOP.

          WHEN 'domain'.
            IF lv_fixed_value IS INITIAL.
              rs_response = zcl_vsp_utils=>build_error(
                iv_id = is_message-id iv_code = 'MISSING_PARAM'
                iv_message = 'fixed_value is required for domain get_translation' ).
              RETURN.
            ENDIF.
            DATA(lo_dom) = xco_i18n=>target->domain->fixed_value(
              iv_domain_name = CONV sxco_ad_object_name( lv_object_name )
              iv_lower_limit = CONV if_xco_domain_fixed_value=>tv_lower_limit( lv_fixed_value )
            ).
            DATA lt_dom_attrs TYPE sxco_t_domain_text_attributes.
            APPEND xco_cp_domain=>text_attribute->fixed_value_description TO lt_dom_attrs.
            DATA(lo_dom_result) = lo_dom->get_translation( io_language = lo_language it_text_attributes = lt_dom_attrs ).
            IF lo_dom_result->texts IS NOT INITIAL.
              lv_json = append_text_entry( iv_json = lv_json iv_attribute = 'fixed_value_description'
                iv_value = lo_dom_result->texts[ 1 ]->get_string_value( ) ).
            ENDIF.

          WHEN 'data_definition'.
            IF lv_field_name IS INITIAL.
              rs_response = zcl_vsp_utils=>build_error(
                iv_id = is_message-id iv_code = 'MISSING_PARAM'
                iv_message = 'field_name is required for data_definition get_translation' ).
              RETURN.
            ENDIF.
            TRANSLATE lv_field_name TO LOWER CASE.
            DATA(lo_fld) = xco_i18n=>target->data_definition->field(
              iv_entity_name = CONV sxco_cds_object_name( lv_object_name )
              iv_field_name  = CONV sxco_cds_field_name( lv_field_name )
            ).
            DATA lt_fld_attrs TYPE sxco_t_ddef_fld_text_attributs.
            DATA lt_fld_names TYPE string_table.
            APPEND 'endusertext_label'     TO lt_fld_names.
            APPEND 'endusertext_quickinfo' TO lt_fld_names.
            DATA lo_fld_ta TYPE REF TO cl_xco_ddef_fld_text_attribute.
            LOOP AT lt_fld_names INTO DATA(lv_fld_name).
              lo_fld_ta = get_ddls_field_attr( lv_fld_name ).
              IF lo_fld_ta IS BOUND. APPEND lo_fld_ta TO lt_fld_attrs. ENDIF.
            ENDLOOP.
            DATA(lo_fld_result) = lo_fld->get_translation( io_language = lo_language it_text_attributes = lt_fld_attrs ).
            DATA(lv_fld_idx) = 0.
            LOOP AT lo_fld_result->texts INTO DATA(lo_fld_text).
              lv_fld_idx = lv_fld_idx + 1.
              READ TABLE lt_fld_names INDEX lv_fld_idx INTO DATA(lv_fld_attr_name).
              lv_json = append_text_entry( iv_json = lv_json iv_attribute = lv_fld_attr_name iv_value = lo_fld_text->get_string_value( ) ).
            ENDLOOP.

          WHEN 'message_class'.
            IF lv_msg_number IS INITIAL.
              rs_response = zcl_vsp_utils=>build_error(
                iv_id = is_message-id iv_code = 'MISSING_PARAM'
                iv_message = 'message_number is required for message_class get_translation' ).
              RETURN.
            ENDIF.
            DATA(lo_mc) = xco_i18n=>target->message_class->message(
              iv_message_class_name = CONV sxco_mc_object_name( lv_object_name )
              iv_message_number     = CONV if_xco_mc_message=>tv_number( lv_msg_number )
            ).
            DATA lt_mc_attrs TYPE sxco_t_mc_text_attributes.
            APPEND xco_cp_message_class=>text_attribute->message_short_text TO lt_mc_attrs.
            DATA(lo_mc_result) = lo_mc->get_translation( io_language = lo_language it_text_attributes = lt_mc_attrs ).
            IF lo_mc_result->texts IS NOT INITIAL.
              lv_json = append_text_entry( iv_json = lv_json iv_attribute = 'message_short_text'
                iv_value = lo_mc_result->texts[ 1 ]->get_string_value( ) ).
            ENDIF.

          WHEN 'text_pool'.
            IF lv_text_sym_id IS INITIAL.
              rs_response = zcl_vsp_utils=>build_error(
                iv_id = is_message-id iv_code = 'MISSING_PARAM'
                iv_message = 'text_symbol_id is required for text_pool get_translation' ).
              RETURN.
            ENDIF.
            DATA lt_tp_attrs TYPE sxco_t_tp_text_attributes.
            APPEND xco_cp_text_pool=>text_attribute->text_element_text TO lt_tp_attrs.
            IF lv_pool_type = 'function_group'.
              DATA(lo_fg) = xco_i18n=>target->text_pool->function_group_text_symbol(
                iv_function_group_name = CONV sxco_fg_object_name( lv_object_name )
                iv_text_symbol_id      = CONV if_xco_i18n_tp_target_factory=>tv_text_symbol_id( lv_text_sym_id )
              ).
              DATA(lo_fg_result) = lo_fg->get_translation( io_language = lo_language it_text_attributes = lt_tp_attrs ).
              IF lo_fg_result->texts IS NOT INITIAL.
                lv_json = append_text_entry( iv_json = lv_json iv_attribute = 'text_element_text'
                  iv_value = lo_fg_result->texts[ 1 ]->get_string_value( ) ).
              ENDIF.
            ELSE.
              DATA(lo_cls) = xco_i18n=>target->text_pool->class_text_symbol(
                iv_class_name     = CONV sxco_ao_object_name( lv_object_name )
                iv_text_symbol_id = CONV if_xco_i18n_tp_target_factory=>tv_text_symbol_id( lv_text_sym_id )
              ).
              DATA(lo_cls_result) = lo_cls->get_translation( io_language = lo_language it_text_attributes = lt_tp_attrs ).
              IF lo_cls_result->texts IS NOT INITIAL.
                lv_json = append_text_entry( iv_json = lv_json iv_attribute = 'text_element_text'
                  iv_value = lo_cls_result->texts[ 1 ]->get_string_value( ) ).
              ENDIF.
            ENDIF.

          WHEN 'metadata_extension'.
            IF lv_field_name IS INITIAL.
              rs_response = zcl_vsp_utils=>build_error(
                iv_id = is_message-id iv_code = 'MISSING_PARAM'
                iv_message = 'field_name is required for metadata_extension get_translation' ).
              RETURN.
            ENDIF.
            DATA(lo_me) = xco_i18n=>target->metadata_extension->field(
              iv_metadata_extension_name = CONV sxco_cds_object_name( lv_object_name )
              iv_field_name              = CONV sxco_cds_field_name( lv_field_name )
            ).
            DATA lt_me_attrs TYPE sxco_t_me_fld_text_attributes.
            DATA lt_me_attr_names TYPE string_table.
            APPEND 'endusertext_label'              TO lt_me_attr_names.
            APPEND 'endusertext_quickinfo'          TO lt_me_attr_names.
            APPEND 'ui_lineitem_label'              TO lt_me_attr_names.
            APPEND 'ui_identification_label'        TO lt_me_attr_names.
            APPEND 'consumption_dynamiclabel_label'  TO lt_me_attr_names.
            APPEND 'ui_fieldgroup_label'            TO lt_me_attr_names.
            APPEND 'ui_fieldgroup_grouplabel'       TO lt_me_attr_names.
            APPEND 'ui_facet_label'                 TO lt_me_attr_names.
            APPEND 'consumption_valuehelpdef_label' TO lt_me_attr_names.
            DATA lo_me_ta TYPE REF TO cl_xco_me_fld_text_attribute.
            LOOP AT lt_me_attr_names INTO DATA(lv_me_attr_name).
              lo_me_ta = get_me_field_attr( iv_name = lv_me_attr_name iv_position = lv_position ).
              IF lo_me_ta IS BOUND. APPEND lo_me_ta TO lt_me_attrs. ENDIF.
            ENDLOOP.
            DATA(lo_me_result) = lo_me->get_translation( io_language = lo_language it_text_attributes = lt_me_attrs ).
            DATA(lv_me_idx) = 0.
            LOOP AT lo_me_result->texts INTO DATA(lo_me_text).
              lv_me_idx = lv_me_idx + 1.
              READ TABLE lt_me_attr_names INDEX lv_me_idx INTO DATA(lv_me_out_name).
              lv_json = append_text_entry( iv_json = lv_json iv_attribute = lv_me_out_name iv_value = lo_me_text->get_string_value( ) ).
            ENDLOOP.

          WHEN 'application_log_object'.
            IF lv_subobj_name IS NOT INITIAL.
              TRANSLATE lv_subobj_name TO UPPER CASE.
              DATA(lo_aplo_sub) = xco_i18n=>target->application_log_object->subobject(
                iv_object_name    = CONV sxco_aplo_object_name( lv_object_name )
                iv_subobject_name = CONV if_xco_aplo_subobject=>tv_name( lv_subobj_name )
              ).
              DATA lt_aplo_sub_attrs TYPE sxco_t_aplo_subobj_txt_attrbts.
              APPEND xco_cp_application_log_object=>text_attribute->subobject->short_description TO lt_aplo_sub_attrs.
              DATA(lo_aplo_sub_res) = lo_aplo_sub->get_translation( io_language = lo_language it_text_attributes = lt_aplo_sub_attrs ).
              IF lo_aplo_sub_res->texts IS NOT INITIAL.
                lv_json = append_text_entry( iv_json = lv_json iv_attribute = 'short_description'
                  iv_value = lo_aplo_sub_res->texts[ 1 ]->get_string_value( ) ).
              ENDIF.
            ELSE.
              DATA(lo_aplo_obj) = xco_i18n=>target->application_log_object->object( iv_name = CONV sxco_aplo_object_name( lv_object_name ) ).
              DATA lt_aplo_obj_attrs TYPE sxco_t_aplo_obj_text_attribts.
              APPEND xco_cp_application_log_object=>text_attribute->object->short_description TO lt_aplo_obj_attrs.
              DATA(lo_aplo_obj_res) = lo_aplo_obj->get_translation( io_language = lo_language it_text_attributes = lt_aplo_obj_attrs ).
              IF lo_aplo_obj_res->texts IS NOT INITIAL.
                lv_json = append_text_entry( iv_json = lv_json iv_attribute = 'short_description'
                  iv_value = lo_aplo_obj_res->texts[ 1 ]->get_string_value( ) ).
              ENDIF.
            ENDIF.

          WHEN 'business_configuration_object'.
            DATA(lo_bco) = xco_i18n=>target->business_configuration_object->object(
              iv_name = CONV sxco_bco_name( lv_object_name ) ).
            DATA lt_bco_attrs TYPE sxco_t_bco_text_attributes.
            APPEND xco_cp_business_cnfgrtn_object=>text_attribute->description TO lt_bco_attrs.
            DATA(lo_bco_result) = lo_bco->get_translation( io_language = lo_language it_text_attributes = lt_bco_attrs ).
            IF lo_bco_result->texts IS NOT INITIAL.
              lv_json = append_text_entry( iv_json = lv_json iv_attribute = 'description'
                iv_value = lo_bco_result->texts[ 1 ]->get_string_value( ) ).
            ENDIF.

          WHEN OTHERS.
            rs_response = zcl_vsp_utils=>build_error(
              iv_id = is_message-id iv_code = 'UNSUPPORTED_TARGET'
              iv_message = |get_translation: target_type '{ lv_target_type }' is not supported| ).
            RETURN.
        ENDCASE.

        DATA(lv_data) = zcl_vsp_utils=>json_obj( zcl_vsp_utils=>json_join( VALUE #(
          ( zcl_vsp_utils=>json_str( iv_key = 'target_type'  iv_value = lv_target_type ) )
          ( zcl_vsp_utils=>json_str( iv_key = 'object_name'  iv_value = lv_object_name ) )
          ( zcl_vsp_utils=>json_str( iv_key = 'language'     iv_value = lv_language    ) )
          ( |"texts":[{ lv_json }]| )
        ) ) ).
        rs_response = zcl_vsp_utils=>build_success( iv_id = is_message-id iv_data = lv_data ).

      CATCH cx_root INTO DATA(lx_error).
        rs_response = zcl_vsp_utils=>build_error(
          iv_id = is_message-id iv_code = 'I18N_GET_ERROR' iv_message = lx_error->get_text( ) ).
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
    DATA(lv_subobj_name) = zcl_vsp_utils=>extract_param( iv_params = is_message-params iv_name = 'subobject_name' ).
    DATA(lv_position_s)  = zcl_vsp_utils=>extract_param( iv_params = is_message-params iv_name = 'position' ).

    IF lv_target_type IS INITIAL OR lv_object_name IS INITIAL OR lv_language IS INITIAL OR lv_transport IS INITIAL.
      rs_response = zcl_vsp_utils=>build_error(
        iv_id = is_message-id iv_code = 'MISSING_PARAM'
        iv_message = 'target_type, object_name, language, and transport are required' ).
      RETURN.
    ENDIF.

    TRANSLATE lv_object_name TO UPPER CASE.
    TRANSLATE lv_language TO UPPER CASE.
    TRANSLATE lv_transport TO UPPER CASE.

    DATA(lv_position) = 1.
    IF lv_position_s IS NOT INITIAL.
      lv_position = CONV i( lv_position_s ).
    ENDIF.

    FIND PCRE '"texts"\s*:\s*(\[[^\]]*\])' IN is_message-params SUBMATCHES DATA(lv_texts_str).
    IF sy-subrc <> 0 OR lv_texts_str IS INITIAL.
      rs_response = zcl_vsp_utils=>build_error(
        iv_id = is_message-id iv_code = 'MISSING_PARAM'
        iv_message = 'texts array is required' ).
      RETURN.
    ENDIF.

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

    DATA lv_attr TYPE string.
    DATA lv_val  TYPE string.

    TRY.
        DATA(lo_language)        = xco_cp=>language( CONV spras( lv_language ) ).
        DATA(lo_change_scenario) = xco_cp_cts=>transport->for( CONV #( lv_transport ) ).

        CASE lv_target_type.

          WHEN 'data_element'.
            DATA(lo_de_set) = xco_i18n=>target->data_element->object( CONV sxco_ad_object_name( lv_object_name ) ).
            DATA lt_dtel_texts TYPE sxco_t_dtel_texts.
            DATA lo_de_ta_w TYPE REF TO cl_xco_dtel_text_attribute.
            DO lines( lt_attrs ) TIMES.
              DATA(lv_idx_de) = sy-index.
              READ TABLE lt_attrs INDEX lv_idx_de INTO lv_attr.
              READ TABLE lt_vals  INDEX lv_idx_de INTO lv_val.
              lo_de_ta_w = get_de_text_attr( lv_attr ).
              IF lo_de_ta_w IS BOUND.
                DATA(lo_de_tv) = CAST if_xco_i18n_text_attribute( lo_de_ta_w )->get_text_for_string( lv_val ).
                APPEND lo_de_ta_w->create_text( io_value = lo_de_tv ) TO lt_dtel_texts.
              ENDIF.
            ENDDO.
            IF lt_dtel_texts IS INITIAL.
              rs_response = zcl_vsp_utils=>build_error(
                iv_id = is_message-id iv_code = 'INVALID_ATTRS'
                iv_message = |No valid text attributes found for target_type '{ lv_target_type }'| ).
              RETURN.
            ENDIF.
            lo_de_set->set_translation(
              it_texts           = lt_dtel_texts
              io_language        = lo_language
              io_change_scenario = lo_change_scenario
            ).

          WHEN 'domain'.
            DATA(lo_dom_set) = xco_i18n=>target->domain->fixed_value(
              iv_domain_name = CONV sxco_ad_object_name( lv_object_name )
              iv_lower_limit = CONV if_xco_domain_fixed_value=>tv_lower_limit( lv_fixed_value )
            ).
            DATA lt_dom_texts TYPE sxco_t_domain_texts.
            DATA(lo_dom_ta_w) = xco_cp_domain=>text_attribute->fixed_value_description.
            DO lines( lt_attrs ) TIMES.
              READ TABLE lt_vals INDEX sy-index INTO lv_val.
              DATA(lo_dom_tv) = CAST if_xco_i18n_text_attribute( lo_dom_ta_w )->get_text_for_string( lv_val ).
              APPEND lo_dom_ta_w->create_text( io_value = lo_dom_tv ) TO lt_dom_texts.
            ENDDO.
            lo_dom_set->set_translation(
              it_texts           = lt_dom_texts
              io_language        = lo_language
              io_change_scenario = lo_change_scenario
            ).

          WHEN 'data_definition'.
            IF lv_field_name IS INITIAL.
              rs_response = zcl_vsp_utils=>build_error(
                iv_id = is_message-id iv_code = 'MISSING_PARAM'
                iv_message = 'field_name is required for data_definition set_translation' ).
              RETURN.
            ENDIF.
            TRANSLATE lv_field_name TO LOWER CASE.
            DATA(lo_ddls_set) = xco_i18n=>target->data_definition->field(
              iv_entity_name = CONV sxco_cds_object_name( lv_object_name )
              iv_field_name  = CONV sxco_cds_field_name( lv_field_name )
            ).
            DATA lt_ddls_texts TYPE sxco_t_ddef_fld_texts.
            DATA lo_fld_ta_w TYPE REF TO cl_xco_ddef_fld_text_attribute.
            DO lines( lt_attrs ) TIMES.
              DATA(lv_idx_fld) = sy-index.
              READ TABLE lt_attrs INDEX lv_idx_fld INTO lv_attr.
              READ TABLE lt_vals  INDEX lv_idx_fld INTO lv_val.
              lo_fld_ta_w = get_ddls_field_attr( lv_attr ).
              IF lo_fld_ta_w IS BOUND.
                DATA(lo_fld_tv) = CAST if_xco_i18n_text_attribute( lo_fld_ta_w )->get_text_for_string( lv_val ).
                APPEND lo_fld_ta_w->create_text( io_value = lo_fld_tv ) TO lt_ddls_texts.
              ENDIF.
            ENDDO.
            IF lt_ddls_texts IS INITIAL.
              rs_response = zcl_vsp_utils=>build_error(
                iv_id = is_message-id iv_code = 'INVALID_ATTRS'
                iv_message = |No valid text attributes found for target_type '{ lv_target_type }'| ).
              RETURN.
            ENDIF.
            lo_ddls_set->set_translation(
              io_language        = lo_language
              it_texts           = lt_ddls_texts
              io_change_scenario = lo_change_scenario
            ).

          WHEN 'message_class'.
            DATA(lo_mc_set) = xco_i18n=>target->message_class->message(
              iv_message_class_name = CONV sxco_mc_object_name( lv_object_name )
              iv_message_number     = CONV if_xco_mc_message=>tv_number( lv_msg_number )
            ).
            DATA lt_mc_texts TYPE sxco_t_mc_texts.
            DATA(lo_mc_ta_w) = xco_cp_message_class=>text_attribute->message_short_text.
            DO lines( lt_attrs ) TIMES.
              READ TABLE lt_vals INDEX sy-index INTO lv_val.
              DATA(lo_mc_tv) = CAST if_xco_i18n_text_attribute( lo_mc_ta_w )->get_text_for_string( lv_val ).
              APPEND lo_mc_ta_w->create_text( io_value = lo_mc_tv ) TO lt_mc_texts.
            ENDDO.
            lo_mc_set->set_translation(
              it_texts           = lt_mc_texts
              io_language        = lo_language
              io_change_scenario = lo_change_scenario
            ).

          WHEN 'text_pool'.
            DATA lt_tp_texts TYPE sxco_t_tp_texts.
            DATA(lo_tp_ta_w) = xco_cp_text_pool=>text_attribute->text_element_text.
            DO lines( lt_attrs ) TIMES.
              READ TABLE lt_vals INDEX sy-index INTO lv_val.
              DATA(lo_tp_tv) = CAST if_xco_i18n_text_attribute( lo_tp_ta_w )->get_text_for_string( lv_val ).
              APPEND lo_tp_ta_w->create_text( io_value = lo_tp_tv ) TO lt_tp_texts.
            ENDDO.
            IF lv_pool_type = 'function_group'.
              DATA(lo_fg_set) = xco_i18n=>target->text_pool->function_group_text_symbol(
                iv_function_group_name = CONV sxco_fg_object_name( lv_object_name )
                iv_text_symbol_id      = CONV if_xco_i18n_tp_target_factory=>tv_text_symbol_id( lv_text_sym_id )
              ).
              lo_fg_set->set_translation(
                it_texts           = lt_tp_texts
                io_language        = lo_language
                io_change_scenario = lo_change_scenario
              ).
            ELSE.
              DATA(lo_cls_set) = xco_i18n=>target->text_pool->class_text_symbol(
                iv_class_name     = CONV sxco_ao_object_name( lv_object_name )
                iv_text_symbol_id = CONV if_xco_i18n_tp_target_factory=>tv_text_symbol_id( lv_text_sym_id )
              ).
              lo_cls_set->set_translation(
                it_texts           = lt_tp_texts
                io_language        = lo_language
                io_change_scenario = lo_change_scenario
              ).
            ENDIF.

          WHEN 'metadata_extension'.
            IF lv_field_name IS INITIAL.
              rs_response = zcl_vsp_utils=>build_error(
                iv_id = is_message-id iv_code = 'MISSING_PARAM'
                iv_message = 'field_name is required for metadata_extension set_translation' ).
              RETURN.
            ENDIF.
            DATA(lo_me_set) = xco_i18n=>target->metadata_extension->field(
              iv_metadata_extension_name = CONV sxco_cds_object_name( lv_object_name )
              iv_field_name              = CONV sxco_cds_field_name( lv_field_name )
            ).
            DATA lt_me_texts TYPE sxco_t_me_fld_texts.
            DATA lo_me_ta_w TYPE REF TO cl_xco_me_fld_text_attribute.
            DO lines( lt_attrs ) TIMES.
              DATA(lv_idx_me) = sy-index.
              READ TABLE lt_attrs INDEX lv_idx_me INTO lv_attr.
              READ TABLE lt_vals  INDEX lv_idx_me INTO lv_val.
              lo_me_ta_w = get_me_field_attr( iv_name = lv_attr iv_position = lv_position ).
              IF lo_me_ta_w IS BOUND.
                DATA(lo_me_tv) = CAST if_xco_i18n_text_attribute( lo_me_ta_w )->get_text_for_string( lv_val ).
                APPEND lo_me_ta_w->create_text( io_value = lo_me_tv ) TO lt_me_texts.
              ENDIF.
            ENDDO.
            IF lt_me_texts IS INITIAL.
              rs_response = zcl_vsp_utils=>build_error(
                iv_id = is_message-id iv_code = 'INVALID_ATTRS'
                iv_message = |No valid text attributes found for target_type '{ lv_target_type }'| ).
              RETURN.
            ENDIF.
            lo_me_set->set_translation(
              it_texts           = lt_me_texts
              io_language        = lo_language
              io_change_scenario = lo_change_scenario
            ).

          WHEN 'application_log_object'.
            IF lv_subobj_name IS NOT INITIAL.
              TRANSLATE lv_subobj_name TO UPPER CASE.
              DATA(lo_set_aplo_sub) = xco_i18n=>target->application_log_object->subobject(
                iv_object_name    = CONV sxco_aplo_object_name( lv_object_name )
                iv_subobject_name = CONV if_xco_aplo_subobject=>tv_name( lv_subobj_name )
              ).
              DATA lt_aplo_sub_texts TYPE sxco_t_aplo_subobj_texts.
              DATA(lo_aplo_sub_ta) = xco_cp_application_log_object=>text_attribute->subobject->short_description.
              DO lines( lt_attrs ) TIMES.
                READ TABLE lt_vals INDEX sy-index INTO lv_val.
                DATA(lo_aplo_sub_tv) = CAST if_xco_i18n_text_attribute( lo_aplo_sub_ta )->get_text_for_string( lv_val ).
                APPEND lo_aplo_sub_ta->create_text( io_value = lo_aplo_sub_tv ) TO lt_aplo_sub_texts.
              ENDDO.
              lo_set_aplo_sub->set_translation(
                it_texts           = lt_aplo_sub_texts
                io_language        = lo_language
                io_change_scenario = lo_change_scenario
              ).
            ELSE.
              DATA(lo_set_aplo_obj) = xco_i18n=>target->application_log_object->object( iv_name = CONV sxco_aplo_object_name( lv_object_name ) ).
              DATA lt_aplo_obj_texts TYPE sxco_t_aplo_obj_texts.
              DATA(lo_aplo_obj_ta) = xco_cp_application_log_object=>text_attribute->object->short_description.
              DO lines( lt_attrs ) TIMES.
                READ TABLE lt_vals INDEX sy-index INTO lv_val.
                DATA(lo_aplo_obj_tv) = CAST if_xco_i18n_text_attribute( lo_aplo_obj_ta )->get_text_for_string( lv_val ).
                APPEND lo_aplo_obj_ta->create_text( io_value = lo_aplo_obj_tv ) TO lt_aplo_obj_texts.
              ENDDO.
              lo_set_aplo_obj->set_translation(
                it_texts           = lt_aplo_obj_texts
                io_language        = lo_language
                io_change_scenario = lo_change_scenario
              ).
            ENDIF.

          WHEN 'business_configuration_object'.
            DATA(lo_bco_set) = xco_i18n=>target->business_configuration_object->object(
              iv_name = CONV sxco_bco_name( lv_object_name ) ).
            DATA lt_bco_texts TYPE sxco_t_bco_texts.
            DATA(lo_bco_ta_w) = xco_cp_business_cnfgrtn_object=>text_attribute->description.
            DO lines( lt_attrs ) TIMES.
              READ TABLE lt_vals INDEX sy-index INTO lv_val.
              DATA(lo_bco_tv) = CAST if_xco_i18n_text_attribute( lo_bco_ta_w )->get_text_for_string( lv_val ).
              APPEND lo_bco_ta_w->create_text( io_value = lo_bco_tv ) TO lt_bco_texts.
            ENDDO.
            lo_bco_set->set_translation(
              it_texts           = lt_bco_texts
              io_language        = lo_language
              io_change_scenario = lo_change_scenario
            ).

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
        SELECT Language,
               LanguageISOCode
          FROM I_Language
          INTO TABLE @DATA(lt_langs)
          ORDER BY Language.

        DATA lv_langs_json TYPE string.
        LOOP AT lt_langs INTO DATA(ls_lang).
          DATA(lv_name) = xco_cp=>language( ls_lang-Language )->get_name( ).
          IF lv_langs_json IS NOT INITIAL.
            lv_langs_json = lv_langs_json && |,|.
          ENDIF.
          lv_langs_json = lv_langs_json && zcl_vsp_utils=>json_obj( zcl_vsp_utils=>json_join( VALUE #(
            ( zcl_vsp_utils=>json_str( iv_key = 'sap_code' iv_value = CONV string( ls_lang-Language ) ) )
            ( zcl_vsp_utils=>json_str( iv_key = 'iso_code' iv_value = CONV string( ls_lang-LanguageISOCode ) ) )
            ( zcl_vsp_utils=>json_str( iv_key = 'name'     iv_value = CONV string( lv_name ) ) )
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
    DATA(lv_position_s)  = zcl_vsp_utils=>extract_param( iv_params = is_message-params iv_name = 'position' ).
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

    DATA(lv_position) = 1.
    IF lv_position_s IS NOT INITIAL.
      lv_position = CONV i( lv_position_s ).
    ENDIF.

    FIND PCRE '"fields"\s*:\s*\[([^\]]*)\]' IN is_message-params SUBMATCHES DATA(lv_fields_str).
    IF sy-subrc = 0 AND lv_fields_str IS NOT INITIAL.
      lt_fields = parse_string_array( lv_fields_str ).
    ENDIF.

    TRY.
        DATA(lo_src_lang) = xco_cp=>language( CONV spras( lv_source_lang ) ).
        DATA(lo_tgt_lang) = xco_cp=>language( CONV spras( lv_target_lang ) ).

        CASE lv_target_type.

          WHEN 'data_definition'.
            IF lt_fields IS INITIAL.
              rs_response = zcl_vsp_utils=>build_error(
                iv_id = is_message-id iv_code = 'MISSING_PARAM'
                iv_message = 'fields array required for data_definition compare_translations' ).
              RETURN.
            ENDIF.
            DATA lt_cmp_fld_ta TYPE sxco_t_ddef_fld_text_attributs.
            APPEND xco_cp_data_definition=>text_attribute->field->endusertext_label TO lt_cmp_fld_ta.
            DATA lv_src_lbl TYPE string.
            DATA lv_tgt_lbl TYPE string.
            LOOP AT lt_fields INTO DATA(lv_field).
              DATA(lv_fld_lower) = lv_field.
              TRANSLATE lv_fld_lower TO LOWER CASE.
              DATA(lo_cmp_fld) = xco_i18n=>target->data_definition->field(
                iv_entity_name = CONV sxco_cds_object_name( lv_object_name )
                iv_field_name  = CONV sxco_cds_field_name( lv_fld_lower )
              ).
              DATA(lo_cmp_src_t) = lo_cmp_fld->get_translation( io_language = lo_src_lang it_text_attributes = lt_cmp_fld_ta ).
              DATA(lo_cmp_tgt_t) = lo_cmp_fld->get_translation( io_language = lo_tgt_lang it_text_attributes = lt_cmp_fld_ta ).
              CLEAR: lv_src_lbl, lv_tgt_lbl.
              IF lo_cmp_src_t->texts IS NOT INITIAL. lv_src_lbl = lo_cmp_src_t->texts[ 1 ]->get_string_value( ). ENDIF.
              IF lo_cmp_tgt_t->texts IS NOT INITIAL. lv_tgt_lbl = lo_cmp_tgt_t->texts[ 1 ]->get_string_value( ). ENDIF.
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
            DATA(lo_cmp_de) = xco_i18n=>target->data_element->object( CONV sxco_ad_object_name( lv_object_name ) ).
            DATA lt_cmp_de_attr_names TYPE string_table.
            APPEND 'short_field_label'    TO lt_cmp_de_attr_names.
            APPEND 'medium_field_label'   TO lt_cmp_de_attr_names.
            APPEND 'long_field_label'     TO lt_cmp_de_attr_names.
            APPEND 'heading_field_label'  TO lt_cmp_de_attr_names.
            DATA lv_src_texts_json TYPE string.
            DATA lv_tgt_texts_json TYPE string.
            DATA lv_any_diff       TYPE abap_bool VALUE abap_false.
            DATA lo_cmp_de_ta TYPE REF TO cl_xco_dtel_text_attribute.
            DATA lt_cmp_de_single_ta TYPE sxco_t_dtel_text_attributes.
            DATA lv_src_t TYPE string.
            DATA lv_tgt_t TYPE string.
            LOOP AT lt_cmp_de_attr_names INTO DATA(lv_cmp_attr).
              lo_cmp_de_ta = get_de_text_attr( lv_cmp_attr ).
              CHECK lo_cmp_de_ta IS BOUND.
              CLEAR lt_cmp_de_single_ta.
              APPEND lo_cmp_de_ta TO lt_cmp_de_single_ta.
              DATA(lo_cmp_de_src) = lo_cmp_de->get_translation( io_language = lo_src_lang it_text_attributes = lt_cmp_de_single_ta ).
              DATA(lo_cmp_de_tgt) = lo_cmp_de->get_translation( io_language = lo_tgt_lang it_text_attributes = lt_cmp_de_single_ta ).
              CLEAR: lv_src_t, lv_tgt_t.
              IF lo_cmp_de_src->texts IS NOT INITIAL. lv_src_t = lo_cmp_de_src->texts[ 1 ]->get_string_value( ). ENDIF.
              IF lo_cmp_de_tgt->texts IS NOT INITIAL. lv_tgt_t = lo_cmp_de_tgt->texts[ 1 ]->get_string_value( ). ENDIF.
              IF lv_src_t <> lv_tgt_t OR lv_tgt_t IS INITIAL. lv_any_diff = abap_true. ENDIF.
              lv_src_texts_json = append_text_entry( iv_json = lv_src_texts_json iv_attribute = lv_cmp_attr iv_value = lv_src_t ).
              lv_tgt_texts_json = append_text_entry( iv_json = lv_tgt_texts_json iv_attribute = lv_cmp_attr iv_value = lv_tgt_t ).
            ENDLOOP.
            lv_items_json = zcl_vsp_utils=>json_obj( zcl_vsp_utils=>json_join( VALUE #(
              ( zcl_vsp_utils=>json_str(  iv_key = 'field_or_key'   iv_value = lv_object_name ) )
              ( |"source_texts":[{ lv_src_texts_json }]| )
              ( |"target_texts":[{ lv_tgt_texts_json }]| )
              ( zcl_vsp_utils=>json_bool( iv_key = 'has_difference' iv_value = lv_any_diff    ) )
            ) ) ).

          WHEN 'metadata_extension'.
            IF lt_fields IS INITIAL.
              rs_response = zcl_vsp_utils=>build_error(
                iv_id = is_message-id iv_code = 'MISSING_PARAM'
                iv_message = 'fields array required for metadata_extension compare_translations' ).
              RETURN.
            ENDIF.
            DATA lt_cmp_me_attr_names TYPE string_table.
            APPEND 'endusertext_label'              TO lt_cmp_me_attr_names.
            APPEND 'endusertext_quickinfo'          TO lt_cmp_me_attr_names.
            APPEND 'ui_lineitem_label'              TO lt_cmp_me_attr_names.
            APPEND 'ui_identification_label'        TO lt_cmp_me_attr_names.
            APPEND 'consumption_dynamiclabel_label'  TO lt_cmp_me_attr_names.
            APPEND 'ui_fieldgroup_label'            TO lt_cmp_me_attr_names.
            APPEND 'ui_fieldgroup_grouplabel'       TO lt_cmp_me_attr_names.
            APPEND 'ui_facet_label'                 TO lt_cmp_me_attr_names.
            APPEND 'consumption_valuehelpdef_label' TO lt_cmp_me_attr_names.
            DATA lo_cmp_me_ta TYPE REF TO cl_xco_me_fld_text_attribute.
            DATA lt_cmp_me_single TYPE sxco_t_me_fld_text_attributes.
            DATA lv_cmp_me_src TYPE string.
            DATA lv_cmp_me_tgt TYPE string.
            LOOP AT lt_fields INTO DATA(lv_me_field).
              DATA(lv_me_src_json) = ||.
              DATA(lv_me_tgt_json) = ||.
              DATA(lv_me_any_diff) = abap_false.
              DATA(lo_cmp_me) = xco_i18n=>target->metadata_extension->field(
                iv_metadata_extension_name = CONV sxco_cds_object_name( lv_object_name )
                iv_field_name              = CONV sxco_cds_field_name( lv_me_field )
              ).
              LOOP AT lt_cmp_me_attr_names INTO DATA(lv_cmp_me_attr).
                lo_cmp_me_ta = get_me_field_attr( iv_name = lv_cmp_me_attr iv_position = lv_position ).
                CHECK lo_cmp_me_ta IS BOUND.
                CLEAR lt_cmp_me_single.
                APPEND lo_cmp_me_ta TO lt_cmp_me_single.
                CLEAR: lv_cmp_me_src, lv_cmp_me_tgt.
                TRY.
                    DATA(lo_cmp_me_src_t) = lo_cmp_me->get_translation( io_language = lo_src_lang it_text_attributes = lt_cmp_me_single ).
                    IF lo_cmp_me_src_t->texts IS NOT INITIAL. lv_cmp_me_src = lo_cmp_me_src_t->texts[ 1 ]->get_string_value( ). ENDIF.
                  CATCH cx_root.
                ENDTRY.
                TRY.
                    DATA(lo_cmp_me_tgt_t) = lo_cmp_me->get_translation( io_language = lo_tgt_lang it_text_attributes = lt_cmp_me_single ).
                    IF lo_cmp_me_tgt_t->texts IS NOT INITIAL. lv_cmp_me_tgt = lo_cmp_me_tgt_t->texts[ 1 ]->get_string_value( ). ENDIF.
                  CATCH cx_root.
                ENDTRY.
                IF lv_cmp_me_src <> lv_cmp_me_tgt OR lv_cmp_me_tgt IS INITIAL. lv_me_any_diff = abap_true. ENDIF.
                lv_me_src_json = append_text_entry( iv_json = lv_me_src_json iv_attribute = lv_cmp_me_attr iv_value = lv_cmp_me_src ).
                lv_me_tgt_json = append_text_entry( iv_json = lv_me_tgt_json iv_attribute = lv_cmp_me_attr iv_value = lv_cmp_me_tgt ).
              ENDLOOP.
              IF lv_items_json IS NOT INITIAL. lv_items_json = lv_items_json && |,|. ENDIF.
              lv_items_json = lv_items_json && zcl_vsp_utils=>json_obj( zcl_vsp_utils=>json_join( VALUE #(
                ( zcl_vsp_utils=>json_str(  iv_key = 'field_or_key'   iv_value = lv_me_field    ) )
                ( |"source_texts":[{ lv_me_src_json }]| )
                ( |"target_texts":[{ lv_me_tgt_json }]| )
                ( zcl_vsp_utils=>json_bool( iv_key = 'has_difference' iv_value = lv_me_any_diff ) )
              ) ) ).
            ENDLOOP.

          WHEN OTHERS.
            rs_response = zcl_vsp_utils=>build_error(
              iv_id = is_message-id iv_code = 'UNSUPPORTED_TARGET'
              iv_message = |compare_translations: target_type '{ lv_target_type }' not supported. Use: data_element, data_definition (with fields[]), metadata_extension (with fields[])| ).
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

  METHOD handle_list_texts.
    DATA(lv_target_type) = zcl_vsp_utils=>extract_param( iv_params = is_message-params iv_name = 'target_type' ).
    DATA(lv_object_name) = zcl_vsp_utils=>extract_param( iv_params = is_message-params iv_name = 'object_name' ).
    DATA(lv_language)    = zcl_vsp_utils=>extract_param( iv_params = is_message-params iv_name = 'language' ).
    DATA(lv_pool_type)   = zcl_vsp_utils=>extract_param( iv_params = is_message-params iv_name = 'text_pool_owner_type' ).

    IF lv_target_type IS INITIAL OR lv_object_name IS INITIAL.
      rs_response = zcl_vsp_utils=>build_error(
        iv_id = is_message-id iv_code = 'MISSING_PARAM'
        iv_message = 'target_type and object_name are required' ).
      RETURN.
    ENDIF.

    TRANSLATE lv_object_name TO UPPER CASE.
    IF lv_language IS INITIAL. lv_language = 'E'. ENDIF.
    TRANSLATE lv_language TO UPPER CASE.

    TRY.
        DATA(lo_language) = xco_cp=>language( CONV spras( lv_language ) ).
        DATA lv_texts_json TYPE string.

        CASE lv_target_type.

          WHEN 'data_element'.
            DATA(lo_lt_de) = xco_i18n=>target->data_element->object( CONV sxco_ad_object_name( lv_object_name ) ).
            DATA lt_lt_de_names TYPE string_table.
            APPEND 'short_field_label'   TO lt_lt_de_names.
            APPEND 'medium_field_label'  TO lt_lt_de_names.
            APPEND 'long_field_label'    TO lt_lt_de_names.
            APPEND 'heading_field_label' TO lt_lt_de_names.
            DATA lt_lt_de_attrs TYPE sxco_t_dtel_text_attributes.
            DATA lo_lt_de_ta TYPE REF TO cl_xco_dtel_text_attribute.
            LOOP AT lt_lt_de_names INTO DATA(lv_lt_de_n).
              lo_lt_de_ta = get_de_text_attr( lv_lt_de_n ).
              IF lo_lt_de_ta IS BOUND. APPEND lo_lt_de_ta TO lt_lt_de_attrs. ENDIF.
            ENDLOOP.
            DATA(lo_lt_de_r) = lo_lt_de->get_translation( io_language = lo_language it_text_attributes = lt_lt_de_attrs ).
            DATA(lv_lt_de_idx) = 0.
            LOOP AT lo_lt_de_r->texts INTO DATA(lo_lt_de_t).
              lv_lt_de_idx = lv_lt_de_idx + 1.
              READ TABLE lt_lt_de_names INDEX lv_lt_de_idx INTO DATA(lv_lt_de_an).
              IF lv_texts_json IS NOT INITIAL. lv_texts_json = lv_texts_json && |,|. ENDIF.
              lv_texts_json = lv_texts_json && zcl_vsp_utils=>json_obj( zcl_vsp_utils=>json_join( VALUE #(
                ( zcl_vsp_utils=>json_str( iv_key = 'level'      iv_value = 'entity' ) )
                ( zcl_vsp_utils=>json_str( iv_key = 'field_name' iv_value = '' ) )
                ( zcl_vsp_utils=>json_str( iv_key = 'attribute'  iv_value = lv_lt_de_an ) )
                ( zcl_vsp_utils=>json_str( iv_key = 'value'      iv_value = lo_lt_de_t->get_string_value( ) ) )
              ) ) ).
            ENDLOOP.

          WHEN 'domain'.
            SELECT domvalue_l FROM dd07l
              WHERE domname = @lv_object_name AND as4local = 'A'
              ORDER BY valpos
              INTO TABLE @DATA(lt_lt_dom_fvs).
            LOOP AT lt_lt_dom_fvs INTO DATA(ls_lt_dom_fv).
              DATA(lo_lt_dom) = xco_i18n=>target->domain->fixed_value(
                iv_domain_name = CONV sxco_ad_object_name( lv_object_name )
                iv_lower_limit = ls_lt_dom_fv-domvalue_l
              ).
              DATA lt_lt_dom_a TYPE sxco_t_domain_text_attributes.
              CLEAR lt_lt_dom_a.
              APPEND xco_cp_domain=>text_attribute->fixed_value_description TO lt_lt_dom_a.
              DATA(lo_lt_dom_r) = lo_lt_dom->get_translation( io_language = lo_language it_text_attributes = lt_lt_dom_a ).
              DATA(lv_fv_val) = ||.
              IF lo_lt_dom_r->texts IS NOT INITIAL. lv_fv_val = lo_lt_dom_r->texts[ 1 ]->get_string_value( ). ENDIF.
              IF lv_texts_json IS NOT INITIAL. lv_texts_json = lv_texts_json && |,|. ENDIF.
              lv_texts_json = lv_texts_json && zcl_vsp_utils=>json_obj( zcl_vsp_utils=>json_join( VALUE #(
                ( zcl_vsp_utils=>json_str( iv_key = 'level'      iv_value = 'fixed_value' ) )
                ( zcl_vsp_utils=>json_str( iv_key = 'field_name' iv_value = CONV string( ls_lt_dom_fv-domvalue_l ) ) )
                ( zcl_vsp_utils=>json_str( iv_key = 'attribute'  iv_value = 'fixed_value_description' ) )
                ( zcl_vsp_utils=>json_str( iv_key = 'value'      iv_value = lv_fv_val ) )
              ) ) ).
            ENDLOOP.

          WHEN 'data_definition'.
            DATA(lo_lt_cds) = xco_cp_cds=>data_definition( CONV sxco_cds_object_name( lv_object_name ) ).
            DATA(lv_lt_cds_type) = lo_lt_cds->get_type( )->value.
            DATA lt_lt_cds_fld_names TYPE string_table.
            CASE lv_lt_cds_type.
              WHEN 'V'.
                DATA(lt_lt_vf) = lo_lt_cds->view( )->fields->all->get( ).
                LOOP AT lt_lt_vf INTO DATA(lo_lt_vf2). APPEND lo_lt_vf2->name TO lt_lt_cds_fld_names. ENDLOOP.
              WHEN 'E'.
                DATA(lt_lt_ef) = lo_lt_cds->view_entity( )->fields->all->get( ).
                LOOP AT lt_lt_ef INTO DATA(lo_lt_ef2). APPEND lo_lt_ef2->name TO lt_lt_cds_fld_names. ENDLOOP.
              WHEN 'P'.
                DATA(lt_lt_pf) = lo_lt_cds->projection_view( )->fields->all->get( ).
                LOOP AT lt_lt_pf INTO DATA(lo_lt_pf2). APPEND lo_lt_pf2->name TO lt_lt_cds_fld_names. ENDLOOP.
              WHEN 'A'.
                DATA(lt_lt_af) = lo_lt_cds->abstract_entity( )->fields->all->get( ).
                LOOP AT lt_lt_af INTO DATA(lo_lt_af2). APPEND lo_lt_af2->name TO lt_lt_cds_fld_names. ENDLOOP.
              WHEN 'C'.
                DATA(lt_lt_cf) = lo_lt_cds->custom_entity( )->fields->all->get( ).
                LOOP AT lt_lt_cf INTO DATA(lo_lt_cf2). APPEND lo_lt_cf2->name TO lt_lt_cds_fld_names. ENDLOOP.
            ENDCASE.
            DATA lt_lt_fld_attrs TYPE string_table.
            APPEND 'endusertext_label'     TO lt_lt_fld_attrs.
            APPEND 'endusertext_quickinfo' TO lt_lt_fld_attrs.
            LOOP AT lt_lt_cds_fld_names INTO DATA(lv_lt_fn).
              DATA lt_lt_fa TYPE sxco_t_ddef_fld_text_attributs.
              DATA lo_lt_fta TYPE REF TO cl_xco_ddef_fld_text_attribute.
              LOOP AT lt_lt_fld_attrs INTO DATA(lv_lt_fan).
                CLEAR lt_lt_fa.
                lo_lt_fta = get_ddls_field_attr( lv_lt_fan ).
                CHECK lo_lt_fta IS BOUND.
                APPEND lo_lt_fta TO lt_lt_fa.
                DATA(lo_lt_fld) = xco_i18n=>target->data_definition->field(
                  iv_entity_name = CONV sxco_cds_object_name( lv_object_name )
                  iv_field_name  = CONV sxco_cds_field_name( lv_lt_fn )
                ).
                TRY.
                    DATA(lo_lt_fr) = lo_lt_fld->get_translation( io_language = lo_language it_text_attributes = lt_lt_fa ).
                    DATA(lv_lt_fv) = ||.
                    IF lo_lt_fr->texts IS NOT INITIAL. lv_lt_fv = lo_lt_fr->texts[ 1 ]->get_string_value( ). ENDIF.
                  CATCH cx_root.
                    CLEAR lv_lt_fv.
                ENDTRY.
                IF lv_texts_json IS NOT INITIAL. lv_texts_json = lv_texts_json && |,|. ENDIF.
                lv_texts_json = lv_texts_json && zcl_vsp_utils=>json_obj( zcl_vsp_utils=>json_join( VALUE #(
                  ( zcl_vsp_utils=>json_str( iv_key = 'level'      iv_value = 'field' ) )
                  ( zcl_vsp_utils=>json_str( iv_key = 'field_name' iv_value = lv_lt_fn ) )
                  ( zcl_vsp_utils=>json_str( iv_key = 'attribute'  iv_value = lv_lt_fan ) )
                  ( zcl_vsp_utils=>json_str( iv_key = 'value'      iv_value = lv_lt_fv ) )
                ) ) ).
              ENDLOOP.
            ENDLOOP.

          WHEN 'metadata_extension'.
            " ME annotates a CDS view - get annotated entity from DDLS name (ME name = CDS name convention)
            " Try to get fields from the CDS data definition with same name
            DATA lt_lt_me_field_names TYPE string_table.
            DATA(lo_lt_me_cds) = xco_cp_cds=>data_definition( CONV sxco_cds_object_name( lv_object_name ) ).
            TRY.
                DATA(lv_lt_me_type) = lo_lt_me_cds->get_type( )->value.
                CASE lv_lt_me_type.
                  WHEN 'V'.
                    DATA(lt_mevf) = lo_lt_me_cds->view( )->fields->all->get( ).
                    LOOP AT lt_mevf INTO DATA(lo_mevf). APPEND lo_mevf->name TO lt_lt_me_field_names. ENDLOOP.
                  WHEN 'E'.
                    DATA(lt_meef) = lo_lt_me_cds->view_entity( )->fields->all->get( ).
                    LOOP AT lt_meef INTO DATA(lo_meef). APPEND lo_meef->name TO lt_lt_me_field_names. ENDLOOP.
                  WHEN 'P'.
                    DATA(lt_mepf) = lo_lt_me_cds->projection_view( )->fields->all->get( ).
                    LOOP AT lt_mepf INTO DATA(lo_mepf). APPEND lo_mepf->name TO lt_lt_me_field_names. ENDLOOP.
                  WHEN 'A'.
                    DATA(lt_meaf) = lo_lt_me_cds->abstract_entity( )->fields->all->get( ).
                    LOOP AT lt_meaf INTO DATA(lo_meaf). APPEND lo_meaf->name TO lt_lt_me_field_names. ENDLOOP.
                  WHEN 'C'.
                    DATA(lt_mecf) = lo_lt_me_cds->custom_entity( )->fields->all->get( ).
                    LOOP AT lt_mecf INTO DATA(lo_mecf). APPEND lo_mecf->name TO lt_lt_me_field_names. ENDLOOP.
                ENDCASE.
              CATCH cx_root.
                " CDS not found or inaccessible - ME without matching CDS
            ENDTRY.
            DATA lt_lt_me_attrs TYPE string_table.
            APPEND 'endusertext_label'              TO lt_lt_me_attrs.
            APPEND 'endusertext_quickinfo'          TO lt_lt_me_attrs.
            APPEND 'ui_lineitem_label'              TO lt_lt_me_attrs.
            APPEND 'ui_identification_label'        TO lt_lt_me_attrs.
            APPEND 'consumption_dynamiclabel_label' TO lt_lt_me_attrs.
            APPEND 'ui_fieldgroup_label'            TO lt_lt_me_attrs.
            APPEND 'ui_fieldgroup_grouplabel'       TO lt_lt_me_attrs.
            APPEND 'ui_facet_label'                 TO lt_lt_me_attrs.
            APPEND 'consumption_valuehelpdef_label' TO lt_lt_me_attrs.
            LOOP AT lt_lt_me_field_names INTO DATA(lv_lt_mfn).
              DATA lo_lt_mta TYPE REF TO cl_xco_me_fld_text_attribute.
              LOOP AT lt_lt_me_attrs INTO DATA(lv_lt_man).
                lo_lt_mta = get_me_field_attr( iv_name = lv_lt_man iv_position = 1 ).
                CHECK lo_lt_mta IS BOUND.
                DATA lt_lt_ma TYPE sxco_t_me_fld_text_attributes.
                CLEAR lt_lt_ma.
                APPEND lo_lt_mta TO lt_lt_ma.
                DATA(lo_lt_me_tgt) = xco_i18n=>target->metadata_extension->field(
                  iv_metadata_extension_name = CONV sxco_cds_object_name( lv_object_name )
                  iv_field_name              = CONV sxco_cds_field_name( lv_lt_mfn )
                ).
                TRY.
                    DATA(lo_lt_mr) = lo_lt_me_tgt->get_translation( io_language = lo_language it_text_attributes = lt_lt_ma ).
                    DATA(lv_lt_mv) = ||.
                    IF lo_lt_mr->texts IS NOT INITIAL. lv_lt_mv = lo_lt_mr->texts[ 1 ]->get_string_value( ). ENDIF.
                  CATCH cx_root.
                    CLEAR lv_lt_mv.
                ENDTRY.
                IF lv_texts_json IS NOT INITIAL. lv_texts_json = lv_texts_json && |,|. ENDIF.
                lv_texts_json = lv_texts_json && zcl_vsp_utils=>json_obj( zcl_vsp_utils=>json_join( VALUE #(
                  ( zcl_vsp_utils=>json_str( iv_key = 'level'      iv_value = 'field' ) )
                  ( zcl_vsp_utils=>json_str( iv_key = 'field_name' iv_value = lv_lt_mfn ) )
                  ( zcl_vsp_utils=>json_str( iv_key = 'attribute'  iv_value = lv_lt_man ) )
                  ( zcl_vsp_utils=>json_str( iv_key = 'value'      iv_value = lv_lt_mv ) )
                ) ) ).
              ENDLOOP.
            ENDLOOP.

          WHEN 'message_class'.
            SELECT msgnr FROM t100
              WHERE sprsl = @lv_language AND arbgb = @lv_object_name
              ORDER BY msgnr
              INTO TABLE @DATA(lt_lt_mc_nums).
            LOOP AT lt_lt_mc_nums INTO DATA(ls_lt_mc_num).
              DATA(lo_lt_mc_tgt) = xco_i18n=>target->message_class->message(
                iv_message_class_name = CONV sxco_mc_object_name( lv_object_name )
                iv_message_number     = CONV if_xco_mc_message=>tv_number( ls_lt_mc_num-msgnr )
              ).
              DATA lt_lt_mc_a TYPE sxco_t_mc_text_attributes.
              CLEAR lt_lt_mc_a.
              APPEND xco_cp_message_class=>text_attribute->message_short_text TO lt_lt_mc_a.
              DATA(lo_lt_mc_r) = lo_lt_mc_tgt->get_translation( io_language = lo_language it_text_attributes = lt_lt_mc_a ).
              DATA(lv_lt_mc_v) = ||.
              IF lo_lt_mc_r->texts IS NOT INITIAL. lv_lt_mc_v = lo_lt_mc_r->texts[ 1 ]->get_string_value( ). ENDIF.
              IF lv_texts_json IS NOT INITIAL. lv_texts_json = lv_texts_json && |,|. ENDIF.
              lv_texts_json = lv_texts_json && zcl_vsp_utils=>json_obj( zcl_vsp_utils=>json_join( VALUE #(
                ( zcl_vsp_utils=>json_str( iv_key = 'level'      iv_value = 'message' ) )
                ( zcl_vsp_utils=>json_str( iv_key = 'field_name' iv_value = CONV string( ls_lt_mc_num-msgnr ) ) )
                ( zcl_vsp_utils=>json_str( iv_key = 'attribute'  iv_value = 'message_short_text' ) )
                ( zcl_vsp_utils=>json_str( iv_key = 'value'      iv_value = lv_lt_mc_v ) )
              ) ) ).
            ENDLOOP.

          WHEN 'text_pool'.
            IF lv_pool_type = 'function_group'.
              DATA lv_lt_fg_prog TYPE syrepid.
              lv_lt_fg_prog = |SAPL{ lv_object_name }|.
              DATA lt_lt_fg_tp TYPE TABLE OF textpool.
              DATA(lv_lt_fg_lang) = CONV spras( lv_language ).
              READ TEXTPOOL lv_lt_fg_prog INTO lt_lt_fg_tp LANGUAGE lv_lt_fg_lang.
              LOOP AT lt_lt_fg_tp INTO DATA(ls_lt_fg_tp) WHERE id = 'I'.
                DATA(lv_lt_fg_key) = ls_lt_fg_tp-key.
                DATA(lo_lt_fg_tgt) = xco_i18n=>target->text_pool->function_group_text_symbol(
                  iv_function_group_name = CONV sxco_fg_object_name( lv_object_name )
                  iv_text_symbol_id      = CONV if_xco_i18n_tp_target_factory=>tv_text_symbol_id( lv_lt_fg_key )
                ).
                DATA lt_lt_tp_a TYPE sxco_t_tp_text_attributes.
                CLEAR lt_lt_tp_a.
                APPEND xco_cp_text_pool=>text_attribute->text_element_text TO lt_lt_tp_a.
                DATA(lo_lt_fg_r) = lo_lt_fg_tgt->get_translation( io_language = lo_language it_text_attributes = lt_lt_tp_a ).
                DATA(lv_lt_fg_v) = ||.
                IF lo_lt_fg_r->texts IS NOT INITIAL. lv_lt_fg_v = lo_lt_fg_r->texts[ 1 ]->get_string_value( ). ENDIF.
                IF lv_texts_json IS NOT INITIAL. lv_texts_json = lv_texts_json && |,|. ENDIF.
                lv_texts_json = lv_texts_json && zcl_vsp_utils=>json_obj( zcl_vsp_utils=>json_join( VALUE #(
                  ( zcl_vsp_utils=>json_str( iv_key = 'level'      iv_value = 'text_symbol' ) )
                  ( zcl_vsp_utils=>json_str( iv_key = 'field_name' iv_value = CONV string( lv_lt_fg_key ) ) )
                  ( zcl_vsp_utils=>json_str( iv_key = 'attribute'  iv_value = 'text_element_text' ) )
                  ( zcl_vsp_utils=>json_str( iv_key = 'value'      iv_value = lv_lt_fg_v ) )
                ) ) ).
              ENDLOOP.
            ELSE.
              DATA lv_lt_cls_prog TYPE syrepid.
              lv_lt_cls_prog = |{ lv_object_name }======================CP|.
              DATA lt_lt_cls_tp TYPE TABLE OF textpool.
              DATA(lv_lt_cls_lang) = CONV spras( lv_language ).
              READ TEXTPOOL lv_lt_cls_prog INTO lt_lt_cls_tp LANGUAGE lv_lt_cls_lang.
              LOOP AT lt_lt_cls_tp INTO DATA(ls_lt_cls_tp) WHERE id = 'I'.
                DATA(lv_lt_cls_key) = ls_lt_cls_tp-key.
                DATA(lo_lt_cls_tgt) = xco_i18n=>target->text_pool->class_text_symbol(
                  iv_class_name     = CONV sxco_ao_object_name( lv_object_name )
                  iv_text_symbol_id = CONV if_xco_i18n_tp_target_factory=>tv_text_symbol_id( lv_lt_cls_key )
                ).
                CLEAR lt_lt_tp_a.
                APPEND xco_cp_text_pool=>text_attribute->text_element_text TO lt_lt_tp_a.
                DATA(lo_lt_cls_r) = lo_lt_cls_tgt->get_translation( io_language = lo_language it_text_attributes = lt_lt_tp_a ).
                DATA(lv_lt_cls_v) = ||.
                IF lo_lt_cls_r->texts IS NOT INITIAL. lv_lt_cls_v = lo_lt_cls_r->texts[ 1 ]->get_string_value( ). ENDIF.
                IF lv_texts_json IS NOT INITIAL. lv_texts_json = lv_texts_json && |,|. ENDIF.
                lv_texts_json = lv_texts_json && zcl_vsp_utils=>json_obj( zcl_vsp_utils=>json_join( VALUE #(
                  ( zcl_vsp_utils=>json_str( iv_key = 'level'      iv_value = 'text_symbol' ) )
                  ( zcl_vsp_utils=>json_str( iv_key = 'field_name' iv_value = CONV string( lv_lt_cls_key ) ) )
                  ( zcl_vsp_utils=>json_str( iv_key = 'attribute'  iv_value = 'text_element_text' ) )
                  ( zcl_vsp_utils=>json_str( iv_key = 'value'      iv_value = lv_lt_cls_v ) )
                ) ) ).
              ENDLOOP.
            ENDIF.

          WHEN OTHERS.
            rs_response = zcl_vsp_utils=>build_error(
              iv_id = is_message-id iv_code = 'UNSUPPORTED_TARGET'
              iv_message = |list_texts: target_type '{ lv_target_type }' is not supported| ).
            RETURN.
        ENDCASE.

        DATA(lv_data) = zcl_vsp_utils=>json_obj( zcl_vsp_utils=>json_join( VALUE #(
          ( zcl_vsp_utils=>json_str( iv_key = 'target_type'  iv_value = lv_target_type ) )
          ( zcl_vsp_utils=>json_str( iv_key = 'object_name'  iv_value = lv_object_name ) )
          ( zcl_vsp_utils=>json_str( iv_key = 'language'     iv_value = lv_language    ) )
          ( |"texts":[{ lv_texts_json }]| )
        ) ) ).
        rs_response = zcl_vsp_utils=>build_success( iv_id = is_message-id iv_data = lv_data ).

      CATCH cx_root INTO DATA(lx_error).
        rs_response = zcl_vsp_utils=>build_error(
          iv_id = is_message-id iv_code = 'LIST_TEXTS_ERROR' iv_message = lx_error->get_text( ) ).
    ENDTRY.
  ENDMETHOD.

  METHOD parse_string_array.
    DATA lv_val TYPE string.
    DATA(lv_content) = iv_content.
    WHILE lv_content IS NOT INITIAL.
      FIND PCRE '"([^"]*)"' IN lv_content SUBMATCHES lv_val MATCH LENGTH DATA(lv_len) MATCH OFFSET DATA(lv_off).
      IF sy-subrc <> 0. EXIT. ENDIF.
      APPEND lv_val TO rt_values.
      DATA(lv_next) = lv_off + lv_len.
      IF lv_next >= strlen( lv_content ). EXIT. ENDIF.
      lv_content = lv_content+lv_next.
    ENDWHILE.
  ENDMETHOD.

  METHOD append_text_entry.
    DATA(lv_entry) = zcl_vsp_utils=>json_obj( zcl_vsp_utils=>json_join( VALUE #(
      ( zcl_vsp_utils=>json_str( iv_key = 'attribute' iv_value = iv_attribute ) )
      ( zcl_vsp_utils=>json_str( iv_key = 'value'     iv_value = iv_value     ) )
    ) ) ).
    IF iv_json IS NOT INITIAL.
      rv_json = iv_json && ',' && lv_entry.
    ELSE.
      rv_json = lv_entry.
    ENDIF.
  ENDMETHOD.

  METHOD get_de_text_attr.
    CASE iv_name.
      WHEN 'short_field_label'.    ro_attr = xco_cp_data_element=>text_attribute->short_field_label.
      WHEN 'medium_field_label'.   ro_attr = xco_cp_data_element=>text_attribute->medium_field_label.
      WHEN 'long_field_label'.     ro_attr = xco_cp_data_element=>text_attribute->long_field_label.
      WHEN 'heading_field_label'.  ro_attr = xco_cp_data_element=>text_attribute->heading_field_label.
    ENDCASE.
  ENDMETHOD.

  METHOD get_ddls_field_attr.
    CASE iv_name.
      WHEN 'endusertext_label'.     ro_attr = xco_cp_data_definition=>text_attribute->field->endusertext_label.
      WHEN 'endusertext_quickinfo'. ro_attr = xco_cp_data_definition=>text_attribute->field->endusertext_quickinfo.
    ENDCASE.
  ENDMETHOD.

  METHOD get_me_field_attr.
    CASE iv_name.
      WHEN 'endusertext_label'.              ro_attr = xco_cp_metadata_extension=>text_attribute->field->endusertext_label.
      WHEN 'endusertext_quickinfo'.          ro_attr = xco_cp_metadata_extension=>text_attribute->field->endusertext_quickinfo.
      WHEN 'ui_lineitem_label'.              ro_attr = xco_cp_metadata_extension=>text_attribute->field->ui_lineitem_label( iv_position ).
      WHEN 'ui_identification_label'.        ro_attr = xco_cp_metadata_extension=>text_attribute->field->ui_identification_label( iv_position ).
      WHEN 'consumption_dynamiclabel_label'. ro_attr = xco_cp_metadata_extension=>text_attribute->field->consumption_dynamiclabel_label.
      WHEN 'ui_fieldgroup_label'.            ro_attr = xco_cp_metadata_extension=>text_attribute->field->ui_fieldgroup_label( iv_position ).
      WHEN 'ui_fieldgroup_grouplabel'.       ro_attr = xco_cp_metadata_extension=>text_attribute->field->ui_fieldgroup_grouplabel( iv_position ).
      WHEN 'ui_facet_label'.                 ro_attr = xco_cp_metadata_extension=>text_attribute->field->ui_facet_label( iv_position ).
      WHEN 'consumption_valuehelpdef_label'. ro_attr = xco_cp_metadata_extension=>text_attribute->field->consumption_valuehelpdef_label( iv_position ).
    ENDCASE.
  ENDMETHOD.

ENDCLASS.
"! <p class="shorttext synchronized">VSP Debug Domain Service</p>
"! Provides full debugging capabilities via WebSocket.
"! Integrates with SAP TPDAPI for real debugger operations.
CLASS zcl_vsp_debug_service DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_vsp_service.

    TYPES:
      BEGIN OF ty_breakpoint_state,
        id         TYPE string,
        kind       TYPE string,
        uri        TYPE string,
        line       TYPE i,
        enabled    TYPE abap_bool,
        condition  TYPE string,
        exception  TYPE string,
        statement  TYPE string,
      END OF ty_breakpoint_state,
      tt_breakpoints TYPE STANDARD TABLE OF ty_breakpoint_state WITH KEY id.

  PRIVATE SECTION.
    DATA mv_session_id TYPE string.
    DATA mv_debug_user TYPE sy-uname.
    DATA mt_breakpoints TYPE tt_breakpoints.
    DATA mv_attached_debuggee TYPE string.
    DATA mo_dbg_service TYPE REF TO if_tpdapi_service.
    DATA mo_dbg_session TYPE REF TO if_tpdapi_session.
    DATA mv_listener_active TYPE abap_bool.
    DATA mo_static_bp_services TYPE REF TO if_tpdapi_static_bp_services.
    DATA mv_bp_context_set TYPE abap_bool.
    "! Terminal ID for session isolation (avoids user-level listener conflicts)
    DATA mv_terminal_id TYPE if_tpdapi_service=>typ_terminal_id.
    DATA mv_ide_id TYPE if_tpdapi_service=>typ_ide_id.
    "! Listen mode: TERMINAL (isolated) or USER (legacy)
    DATA mv_listen_mode TYPE string VALUE 'USER'.

    " Maps our breakpoint IDs to TPDAPI breakpoint references
    TYPES:
      BEGIN OF ty_bp_mapping,
        id     TYPE string,
        ref_bp TYPE REF TO if_tpdapi_bp,
      END OF ty_bp_mapping,
      tt_bp_mappings TYPE STANDARD TABLE OF ty_bp_mapping WITH KEY id.
    DATA mt_bp_mappings TYPE tt_bp_mappings.

    METHODS handle_set_breakpoint
      IMPORTING is_message         TYPE zif_vsp_service=>ty_message
      RETURNING VALUE(rs_response) TYPE zif_vsp_service=>ty_response.

    METHODS handle_get_breakpoints
      IMPORTING is_message         TYPE zif_vsp_service=>ty_message
      RETURNING VALUE(rs_response) TYPE zif_vsp_service=>ty_response.

    METHODS handle_delete_breakpoint
      IMPORTING is_message         TYPE zif_vsp_service=>ty_message
      RETURNING VALUE(rs_response) TYPE zif_vsp_service=>ty_response.

    METHODS handle_listen
      IMPORTING is_message         TYPE zif_vsp_service=>ty_message
      RETURNING VALUE(rs_response) TYPE zif_vsp_service=>ty_response.

    METHODS handle_get_debuggees
      IMPORTING is_message         TYPE zif_vsp_service=>ty_message
      RETURNING VALUE(rs_response) TYPE zif_vsp_service=>ty_response.

    METHODS handle_attach
      IMPORTING is_message         TYPE zif_vsp_service=>ty_message
      RETURNING VALUE(rs_response) TYPE zif_vsp_service=>ty_response.

    METHODS handle_step
      IMPORTING is_message         TYPE zif_vsp_service=>ty_message
      RETURNING VALUE(rs_response) TYPE zif_vsp_service=>ty_response.

    METHODS handle_get_stack
      IMPORTING is_message         TYPE zif_vsp_service=>ty_message
      RETURNING VALUE(rs_response) TYPE zif_vsp_service=>ty_response.

    METHODS handle_get_variables
      IMPORTING is_message         TYPE zif_vsp_service=>ty_message
      RETURNING VALUE(rs_response) TYPE zif_vsp_service=>ty_response.

    METHODS handle_detach
      IMPORTING is_message         TYPE zif_vsp_service=>ty_message
      RETURNING VALUE(rs_response) TYPE zif_vsp_service=>ty_response.

    METHODS handle_get_status
      IMPORTING is_message         TYPE zif_vsp_service=>ty_message
      RETURNING VALUE(rs_response) TYPE zif_vsp_service=>ty_response.

    METHODS escape_json
      IMPORTING iv_string         TYPE string
      RETURNING VALUE(rv_escaped) TYPE string.

    METHODS error_response
      IMPORTING iv_id              TYPE string
                iv_code            TYPE string
                iv_message         TYPE string
      RETURNING VALUE(rs_response) TYPE zif_vsp_service=>ty_response.

    METHODS extract_param
      IMPORTING iv_params       TYPE string
                iv_name         TYPE string
      RETURNING VALUE(rv_value) TYPE string.

    METHODS extract_param_int
      IMPORTING iv_params       TYPE string
                iv_name         TYPE string
      RETURNING VALUE(rv_value) TYPE i.

    METHODS extract_param_array
      IMPORTING iv_params          TYPE string
                iv_name            TYPE string
      RETURNING VALUE(rt_values)   TYPE string_table.

    METHODS get_debugger_service
      RETURNING VALUE(ro_service) TYPE REF TO if_tpdapi_service.

    METHODS get_static_bp_services
      RETURNING VALUE(ro_services) TYPE REF TO if_tpdapi_static_bp_services
      RAISING   cx_tpdapi_failure.

    METHODS ensure_bp_context
      RAISING cx_tpdapi_invalid_user
              cx_tpdapi_invalid_param
              cx_tpdapi_not_authorized
              cx_tpdapi_failure.

    METHODS extract_program_from_uri
      IMPORTING iv_uri            TYPE string
      RETURNING VALUE(rv_program) TYPE string.

    "! Initialize terminal/IDE IDs for session isolation
    METHODS init_terminal_ids.

    "! Cleanup stale debug artifacts (breakpoints, listeners) for current user
    METHODS cleanup_stale_artifacts.
    METHODS set_terminal_id_epp IMPORTING iv_terminal_id TYPE sysuuid_c32.

ENDCLASS.


CLASS zcl_vsp_debug_service IMPLEMENTATION.

  METHOD zif_vsp_service~get_domain.
    rv_domain = 'debug'.
  ENDMETHOD.

  METHOD zif_vsp_service~handle_message.
    mv_session_id = iv_session_id.
    IF mv_debug_user IS INITIAL.
      mv_debug_user = sy-uname.
    ENDIF.
    " Accept external terminal ID (e.g. SAP GUI) for cross-tool debugging
    IF mv_terminal_id IS INITIAL.
      DATA(lv_ext_tid) = extract_param( iv_params = is_message-params iv_name = 'terminalId' ).
      IF lv_ext_tid IS NOT INITIAL.
        mv_terminal_id = lv_ext_tid.
        mv_ide_id = lv_ext_tid.
        " Auto-use TERMINAL mode when external terminal ID is provided
        mv_listen_mode = 'TERMINAL'.
      ENDIF.
    ENDIF.
    " Accept external IDE ID (separate from terminal ID, e.g. from SAP GUI/ADT)
    DATA(lv_ext_ide) = extract_param( iv_params = is_message-params iv_name = 'ideId' ).
    IF lv_ext_ide IS NOT INITIAL.
      mv_ide_id = lv_ext_ide.
    ENDIF.
    " Initialize terminal IDs for session isolation on first call
    init_terminal_ids( ).

    CASE is_message-action.
      WHEN 'setBreakpoint'.
        rs_response = handle_set_breakpoint( is_message ).
      WHEN 'getBreakpoints'.
        rs_response = handle_get_breakpoints( is_message ).
      WHEN 'deleteBreakpoint'.
        rs_response = handle_delete_breakpoint( is_message ).
      WHEN 'listen'.
        rs_response = handle_listen( is_message ).
      WHEN 'getDebuggees'.
        rs_response = handle_get_debuggees( is_message ).
      WHEN 'attach'.
        rs_response = handle_attach( is_message ).
      WHEN 'step'.
        rs_response = handle_step( is_message ).
      WHEN 'getStack'.
        rs_response = handle_get_stack( is_message ).
      WHEN 'getVariables'.
        rs_response = handle_get_variables( is_message ).
      WHEN 'detach'.
        rs_response = handle_detach( is_message ).
      WHEN 'getStatus'.
        rs_response = handle_get_status( is_message ).
      WHEN OTHERS.
        rs_response = error_response(
          iv_id      = is_message-id
          iv_code    = 'UNKNOWN_ACTION'
          iv_message = |Action '{ is_message-action }' not supported|
        ).
    ENDCASE.
  ENDMETHOD.

  METHOD zif_vsp_service~on_disconnect.
    " Clean up debug session
    IF mo_dbg_session IS NOT INITIAL.
      TRY.
          mo_dbg_session->get_control_services( )->end_debugger( ).
        CATCH cx_tpdapi_failure cx_root ##NO_HANDLER.
      ENDTRY.
    ENDIF.

    " Stop listener (use appropriate mode)
    IF mv_listener_active = abap_true AND mo_dbg_service IS NOT INITIAL.
      TRY.
          IF mv_listen_mode = 'TERMINAL' AND mv_terminal_id IS NOT INITIAL.
            mo_dbg_service->stop_listener_for_terminal_id(
              i_terminal_id = mv_terminal_id
              i_ide_id      = mv_ide_id ).
          ELSE.
            mo_dbg_service->stop_listener_for_user( i_request_user = mv_debug_user ).
          ENDIF.
        CATCH cx_tpdapi_failure cx_root ##NO_HANDLER.
      ENDTRY.
    ENDIF.

    " Do NOT delete breakpoints on disconnect:
    " The Go client creates a new WebSocket per command, so breakpoints
    " set in one connection must persist for the listener in the next.
    " Breakpoints are cleaned up by SAP's standard timeout mechanism.

    CLEAR: mv_attached_debuggee, mt_breakpoints, mt_bp_mappings,
           mo_dbg_session, mv_listener_active, mv_bp_context_set,
           mv_terminal_id, mv_ide_id.
  ENDMETHOD.

  METHOD get_debugger_service.
    IF mo_dbg_service IS INITIAL.
      mo_dbg_service = cl_tpdapi_service=>s_get_instance( ).
    ENDIF.
    ro_service = mo_dbg_service.
  ENDMETHOD.

  METHOD get_static_bp_services.
    IF mo_static_bp_services IS INITIAL.
      DATA(lo_service) = get_debugger_service( ).
      mo_static_bp_services = lo_service->get_static_bp_services( ).
    ENDIF.
    ro_services = mo_static_bp_services.
  ENDMETHOD.

  METHOD ensure_bp_context.
    IF mv_bp_context_set = abap_true.
      RETURN.
    ENDIF.

    init_terminal_ids( ).

    " Activate debug session for user-based breakpoints (%_SYSTEM)
    TRY.
        DATA(lo_service) = get_debugger_service( ).
        lo_service->activate_session_for_ext_debug(
          i_ide_user    = mv_debug_user
          i_terminal_id = mv_terminal_id
          i_ide_id      = mv_ide_id ).
      CATCH cx_root ##NO_HANDLER.
    ENDTRY.

    DATA(lo_bp_services) = get_static_bp_services( ).

    " Set user-based BP context (creates %_SYSTEM icfattrib entry)
    lo_bp_services->set_external_bp_context_user(
      i_ide_user     = mv_debug_user
      i_request_user = mv_debug_user
      i_ide_id       = mv_ide_id ).

    mv_bp_context_set = abap_true.
  ENDMETHOD.

  METHOD extract_program_from_uri.
    DATA lv_uri TYPE string.
    DATA lt_parts TYPE TABLE OF string.

    lv_uri = iv_uri.
    TRANSLATE lv_uri TO UPPER CASE.

    SPLIT lv_uri AT '/' INTO TABLE lt_parts.

    LOOP AT lt_parts INTO DATA(lv_part).
      DATA(lv_idx) = sy-tabix.
      IF lv_part = 'PROGRAMS' OR lv_part = 'CLASSES' OR lv_part = 'FMODULES'.
        READ TABLE lt_parts INTO rv_program INDEX lv_idx + 1.
        IF sy-subrc = 0.
          IF lv_part = 'CLASSES'.
            rv_program = |{ rv_program }================CP|.
          ENDIF.
          EXIT.
        ENDIF.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD handle_listen.
    DATA(lv_brace_open) = '{'.
    DATA(lv_brace_close) = '}'.
    DATA lv_timeout TYPE i.
    DATA lv_user TYPE syuname.
    DATA lv_mode TYPE string.

    lv_timeout = extract_param_int( iv_params = is_message-params iv_name = 'timeout' ).
    IF lv_timeout <= 0.
      lv_timeout = 60.
    ENDIF.
    IF lv_timeout > 240.
      lv_timeout = 240.
    ENDIF.

    lv_user = extract_param( iv_params = is_message-params iv_name = 'user' ).
    IF lv_user IS INITIAL.
      lv_user = mv_debug_user.
    ENDIF.

    lv_mode = extract_param( iv_params = is_message-params iv_name = 'mode' ).
    IF lv_mode IS NOT INITIAL.
      mv_listen_mode = to_upper( lv_mode ).
    ENDIF.

    IF cl_tpdapi_service=>is_debugging_available( ) IS INITIAL.
      rs_response = error_response(
        iv_id      = is_message-id
        iv_code    = 'DEBUG_NOT_AVAILABLE'
        iv_message = 'Debugging is not available on this system'
      ).
      RETURN.
    ENDIF.

    TRY.
        DATA(lo_service) = get_debugger_service( ).

        cleanup_stale_artifacts( ).

        " Pre-check for listener conflicts and auto-resolve
        TRY.
            IF mv_listen_mode = 'TERMINAL'.
              lo_service->check_listener_conflict_termid(
                i_terminal_id = mv_terminal_id
                i_ide_id      = mv_ide_id ).
            ELSE.
              lo_service->check_listener_conflict_user(
                i_user   = lv_user
                i_ide_id = mv_ide_id ).
            ENDIF.
          CATCH cx_abdbg_actext_conflict_lis.
            TRY.
                IF mv_listen_mode = 'TERMINAL'.
                  lo_service->stop_listener_for_terminal_id(
                    i_terminal_id = mv_terminal_id
                    i_ide_id      = mv_ide_id ).
                ELSE.
                  lo_service->stop_listener_for_user( i_request_user = lv_user ).
                ENDIF.
              CATCH cx_tpdapi_failure ##NO_HANDLER.
            ENDTRY.
          CATCH cx_tpdapi_invalid_user ##NO_HANDLER.
        ENDTRY.

        lo_service->activate_session_for_ext_debug(
          i_ide_user    = mv_debug_user
          i_terminal_id = mv_terminal_id
          i_ide_id      = mv_ide_id ).

        " Cross-server: set terminal ID in kernel (EPP) and activate
        IF mv_listen_mode = 'TERMINAL'.
          set_terminal_id_epp( mv_terminal_id ).
          TRY.
              cl_abdbg_act_for_attach__ideid=>activate_request_for_attach(
                ideuser = mv_debug_user
                ideid   = mv_ide_id ).
            CATCH cx_root ##NO_HANDLER.
          ENDTRY.
        ENDIF.

        mv_listener_active = abap_true.

        " Use activation class directly to preserve m_context_id across
        " start_listener -> get_waiting_debuggees (CL_TPDAPI_SERVICE creates
        " a new instance per call, losing the context).
        DATA lt_debuggees TYPE if_tpdapi_service=>typ_tab_debuggees.

        IF mv_listen_mode = 'TERMINAL'.
          DATA(lo_act_tid) = cl_abdbg_act_for_attach__tid=>create_instance(
            termid  = mv_terminal_id
            ideid   = mv_ide_id
            ideuser = mv_debug_user ).
          lo_act_tid->start_listener( time_out = lv_timeout ).
          DATA lt_raw_dbgees TYPE abdbg_act_debuggees.
          TRY.
              lo_act_tid->get_waiting_debuggees( IMPORTING debuggees = lt_raw_dbgees ).
            CATCH cx_abdbg_actext_no_debuggees ##NO_HANDLER.
          ENDTRY.
          LOOP AT lt_raw_dbgees INTO DATA(ls_raw).
            APPEND VALUE #( BASE CORRESPONDING #( ls_raw )
              host           = ls_raw-appserver
              is_same_server = COND #( WHEN ls_raw-appserver IS NOT INITIAL THEN abap_true ELSE abap_false )
            ) TO lt_debuggees.
          ENDLOOP.
        ELSE.
          lo_service->start_listener_for_user(
            i_request_user = lv_user
            i_ide_user     = mv_debug_user
            i_ide_id       = mv_ide_id
            i_timeout      = lv_timeout ).
          lt_debuggees = lo_service->get_waiting_debuggees(
            i_terminal_id  = mv_terminal_id
            i_ide_id       = mv_ide_id
            i_request_user = lv_user
            i_ide_user     = mv_debug_user ).
        ENDIF.

        mv_listener_active = abap_false.

        IF lt_debuggees IS INITIAL.
          rs_response = VALUE #(
            id      = is_message-id
            success = abap_true
            data    = |{ lv_brace_open }"status":"timeout","debuggees":[]{ lv_brace_close }|
          ).
        ELSE.
          DATA lv_json TYPE string.
          DATA lv_first TYPE abap_bool VALUE abap_true.
          lv_json = '['.

          LOOP AT lt_debuggees INTO DATA(ls_debuggee).
            IF lv_first = abap_false.
              lv_json = |{ lv_json },|.
            ENDIF.
            lv_first = abap_false.

            DATA(lv_host) = CONV string( ls_debuggee-host ).
            DATA(lv_prog) = CONV string( ls_debuggee-program ).

            lv_json = |{ lv_json }{ lv_brace_open }| &&
                      |"id":"{ ls_debuggee-debuggee_id }",| &&
                      |"host":"{ escape_json( lv_host ) }",| &&
                      |"user":"{ ls_debuggee-debuggee_user }",| &&
                      |"program":"{ escape_json( lv_prog ) }",| &&
                      |"sameServer":{ COND #( WHEN ls_debuggee-is_same_server IS NOT INITIAL THEN 'true' ELSE 'false' ) }| &&
                      |{ lv_brace_close }|.
          ENDLOOP.

          lv_json = |{ lv_json }]|.

          rs_response = VALUE #(
            id      = is_message-id
            success = abap_true
            data    = |{ lv_brace_open }"status":"caught","debuggees":{ lv_json },"listenMode":"{ mv_listen_mode }"{ lv_brace_close }|
          ).
        ENDIF.

      CATCH cx_abdbg_actext_lis_timeout.
        mv_listener_active = abap_false.
        rs_response = VALUE #(
          id      = is_message-id
          success = abap_true
          data    = |{ lv_brace_open }"status":"timeout","debuggees":[]{ lv_brace_close }|
        ).

      CATCH cx_abdbg_actext_conflict_lis INTO DATA(lx_conflict).
        mv_listener_active = abap_false.
        rs_response = error_response(
          iv_id      = is_message-id
          iv_code    = 'LISTENER_CONFLICT'
          iv_message = |Another listener is already active: { lx_conflict->get_text( ) }|
        ).

      CATCH cx_tpdapi_failure cx_root INTO DATA(lx_error).
        mv_listener_active = abap_false.
        rs_response = error_response(
          iv_id      = is_message-id
          iv_code    = 'LISTEN_FAILED'
          iv_message = lx_error->get_text( )
        ).
    ENDTRY.
  ENDMETHOD.

  METHOD handle_get_debuggees.
    DATA(lv_brace_open) = '{'.
    DATA(lv_brace_close) = '}'.
    DATA lv_user TYPE syuname.

    lv_user = extract_param( iv_params = is_message-params iv_name = 'user' ).
    IF lv_user IS INITIAL.
      lv_user = mv_debug_user.
    ENDIF.

    TRY.
        DATA(lo_service) = get_debugger_service( ).
        DATA(lt_debuggees) = lo_service->get_waiting_debuggees(
          i_request_user = lv_user
          i_ide_user     = mv_debug_user ).

        DATA lv_json TYPE string.
        DATA lv_first TYPE abap_bool VALUE abap_true.
        lv_json = '['.

        LOOP AT lt_debuggees INTO DATA(ls_debuggee).
          IF lv_first = abap_false.
            lv_json = |{ lv_json },|.
          ENDIF.
          lv_first = abap_false.

          DATA(lv_host) = CONV string( ls_debuggee-host ).
          DATA(lv_prog) = CONV string( ls_debuggee-program ).

          lv_json = |{ lv_json }{ lv_brace_open }| &&
                    |"id":"{ ls_debuggee-debuggee_id }",| &&
                    |"host":"{ escape_json( lv_host ) }",| &&
                    |"user":"{ ls_debuggee-debuggee_user }",| &&
                    |"program":"{ escape_json( lv_prog ) }"| &&
                    |{ lv_brace_close }|.
        ENDLOOP.

        lv_json = |{ lv_json }]|.

        rs_response = VALUE #(
          id      = is_message-id
          success = abap_true
          data    = |{ lv_brace_open }"debuggees":{ lv_json }{ lv_brace_close }|
        ).

      CATCH cx_tpdapi_failure cx_root INTO DATA(lx_error).
        rs_response = error_response(
          iv_id      = is_message-id
          iv_code    = 'GET_DEBUGGEES_FAILED'
          iv_message = lx_error->get_text( )
        ).
    ENDTRY.
  ENDMETHOD.

  METHOD handle_attach.
    DATA(lv_brace_open) = '{'.
    DATA(lv_brace_close) = '}'.
    DATA lv_debuggee_id TYPE string.

    lv_debuggee_id = extract_param( iv_params = is_message-params iv_name = 'debuggeeId' ).
    IF lv_debuggee_id IS INITIAL.
      rs_response = error_response(
        iv_id      = is_message-id
        iv_code    = 'INVALID_PARAMS'
        iv_message = 'debuggeeId parameter required'
      ).
      RETURN.
    ENDIF.

    IF mo_dbg_session IS NOT INITIAL.
      rs_response = error_response(
        iv_id      = is_message-id
        iv_code    = 'ALREADY_ATTACHED'
        iv_message = |Already attached to debuggee { mv_attached_debuggee }. Detach first.|
      ).
      RETURN.
    ENDIF.

    TRY.
        DATA(lo_service) = get_debugger_service( ).
        mo_dbg_session = lo_service->attach_debuggee( i_debuggee_id = CONV #( lv_debuggee_id ) ).
        mv_attached_debuggee = lv_debuggee_id.

        DATA(lo_stack_handler) = mo_dbg_session->get_stack_handler( ).
        DATA(lt_stack) = lo_stack_handler->get_stack( ).

        DATA lv_program TYPE string.
        DATA lv_include TYPE string.
        DATA lv_line TYPE i.

        READ TABLE lt_stack INTO DATA(ls_stack) WITH KEY flg_active = abap_true.
        IF sy-subrc = 0.
          lv_program = ls_stack-program.
          lv_include = ls_stack-include.
          lv_line = ls_stack-line.
        ENDIF.

        rs_response = VALUE #(
          id      = is_message-id
          success = abap_true
          data    = |{ lv_brace_open }"attached":true,"debuggeeId":"{ escape_json( lv_debuggee_id ) }",| &&
                    |"program":"{ escape_json( lv_program ) }",| &&
                    |"include":"{ escape_json( lv_include ) }",| &&
                    |"line":{ lv_line }{ lv_brace_close }|
        ).

      CATCH cx_tpdapi_failure cx_root INTO DATA(lx_error).
        CLEAR: mo_dbg_session, mv_attached_debuggee.
        rs_response = error_response(
          iv_id      = is_message-id
          iv_code    = 'ATTACH_FAILED'
          iv_message = lx_error->get_text( )
        ).
    ENDTRY.
  ENDMETHOD.

  METHOD handle_step.
    DATA(lv_brace_open) = '{'.
    DATA(lv_brace_close) = '}'.
    DATA lv_step_type TYPE string.

    IF mo_dbg_session IS INITIAL.
      rs_response = error_response(
        iv_id      = is_message-id
        iv_code    = 'NOT_ATTACHED'
        iv_message = 'Not attached to any debuggee. Use attach first.'
      ).
      RETURN.
    ENDIF.

    lv_step_type = extract_param( iv_params = is_message-params iv_name = 'type' ).
    IF lv_step_type IS INITIAL.
      lv_step_type = 'into'.
    ENDIF.

    TRY.
        DATA(lo_control) = mo_dbg_session->get_control_services( ).
        DATA lo_steptype TYPE REF TO ie_tpdapi_steptype.

        CASE lv_step_type.
          WHEN 'into'.
            lo_steptype = ce_tpdapi_steptype=>into.
          WHEN 'over'.
            lo_steptype = ce_tpdapi_steptype=>over.
          WHEN 'return'.
            lo_steptype = ce_tpdapi_steptype=>out.
          WHEN 'continue'.
            lo_steptype = ce_tpdapi_steptype=>continue.
          WHEN OTHERS.
            rs_response = error_response(
              iv_id      = is_message-id
              iv_code    = 'INVALID_STEP_TYPE'
              iv_message = |Invalid step type '{ lv_step_type }'. Use: into, over, return, continue|
            ).
            RETURN.
        ENDCASE.

        lo_control->debug_step( i_ref_steptype = lo_steptype ).

        DATA(lo_stack_handler) = mo_dbg_session->get_stack_handler( ).
        DATA(lt_stack) = lo_stack_handler->get_stack( ).

        DATA lv_program TYPE string.
        DATA lv_include TYPE string.
        DATA lv_line TYPE i.
        DATA lv_procname TYPE string.

        READ TABLE lt_stack INTO DATA(ls_stack) WITH KEY flg_active = abap_true.
        IF sy-subrc = 0.
          lv_program = ls_stack-program.
          lv_include = ls_stack-include.
          lv_line = ls_stack-line.
          lv_procname = ls_stack-procname.
        ENDIF.

        rs_response = VALUE #(
          id      = is_message-id
          success = abap_true
          data    = |{ lv_brace_open }"stepped":"{ lv_step_type }",| &&
                    |"program":"{ escape_json( lv_program ) }",| &&
                    |"include":"{ escape_json( lv_include ) }",| &&
                    |"line":{ lv_line },| &&
                    |"procedure":"{ escape_json( lv_procname ) }"{ lv_brace_close }|
        ).

      CATCH cx_tpdapi_debuggee_ended.
        CLEAR: mo_dbg_session, mv_attached_debuggee.
        rs_response = VALUE #(
          id      = is_message-id
          success = abap_true
          data    = |{ lv_brace_open }"stepped":"{ lv_step_type }","ended":true,"message":"Debuggee ended"{ lv_brace_close }|
        ).

      CATCH cx_tpdapi_failure cx_root INTO DATA(lx_error).
        rs_response = error_response(
          iv_id      = is_message-id
          iv_code    = 'STEP_FAILED'
          iv_message = lx_error->get_text( )
        ).
    ENDTRY.
  ENDMETHOD.

  METHOD handle_get_stack.
    DATA(lv_brace_open) = '{'.
    DATA(lv_brace_close) = '}'.

    IF mo_dbg_session IS INITIAL.
      rs_response = error_response(
        iv_id      = is_message-id
        iv_code    = 'NOT_ATTACHED'
        iv_message = 'Not attached to any debuggee'
      ).
      RETURN.
    ENDIF.

    TRY.
        DATA(lo_stack_handler) = mo_dbg_session->get_stack_handler( ).
        DATA(lt_stack) = lo_stack_handler->get_stack( ).

        DATA lv_json TYPE string.
        DATA lv_first TYPE abap_bool VALUE abap_true.
        DATA lv_idx TYPE i.
        lv_json = '['.

        LOOP AT lt_stack INTO DATA(ls_frame).
          lv_idx = sy-tabix - 1.
          IF lv_first = abap_false.
            lv_json = |{ lv_json },|.
          ENDIF.
          lv_first = abap_false.

          DATA(lv_prog) = CONV string( ls_frame-program ).
          DATA(lv_incl) = CONV string( ls_frame-include ).
          DATA(lv_proc) = CONV string( ls_frame-procname ).

          lv_json = |{ lv_json }{ lv_brace_open }| &&
                    |"index":{ lv_idx },| &&
                    |"program":"{ escape_json( lv_prog ) }",| &&
                    |"include":"{ escape_json( lv_incl ) }",| &&
                    |"line":{ ls_frame-line },| &&
                    |"procedure":"{ escape_json( lv_proc ) }",| &&
                    |"active":{ COND #( WHEN ls_frame-flg_active IS NOT INITIAL THEN 'true' ELSE 'false' ) },| &&
                    |"system":{ COND #( WHEN ls_frame-flg_sysprog IS NOT INITIAL THEN 'true' ELSE 'false' ) }| &&
                    |{ lv_brace_close }|.
        ENDLOOP.

        lv_json = |{ lv_json }]|.

        rs_response = VALUE #(
          id      = is_message-id
          success = abap_true
          data    = |{ lv_brace_open }"stack":{ lv_json }{ lv_brace_close }|
        ).

      CATCH cx_tpdapi_failure cx_root INTO DATA(lx_error).
        rs_response = error_response(
          iv_id      = is_message-id
          iv_code    = 'GET_STACK_FAILED'
          iv_message = lx_error->get_text( )
        ).
    ENDTRY.
  ENDMETHOD.

  METHOD handle_get_variables.
    DATA(lv_brace_open) = '{'.
    DATA(lv_brace_close) = '}'.
    DATA lv_scope TYPE string.

    IF mo_dbg_session IS INITIAL.
      rs_response = error_response(
        iv_id      = is_message-id
        iv_code    = 'NOT_ATTACHED'
        iv_message = 'Not attached to any debuggee'
      ).
      RETURN.
    ENDIF.

    lv_scope = extract_param( iv_params = is_message-params iv_name = 'scope' ).
    IF lv_scope IS INITIAL.
      lv_scope = 'system'.
    ENDIF.

    " Check for specific variable names
    DATA(lt_names) = extract_param_array( iv_params = is_message-params iv_name = 'names' ).

    TRY.
        DATA(lo_data_services) = mo_dbg_session->get_data_services( ).

        DATA lv_json TYPE string.
        DATA lv_first TYPE abap_bool VALUE abap_true.
        lv_json = '['.

        IF lt_names IS NOT INITIAL.
          " Read specific variables by name
          LOOP AT lt_names INTO DATA(lv_req_name).
            TRY.
                DATA(lv_upper_name) = to_upper( lv_req_name ).
                DATA(lo_named_data) = lo_data_services->get_data( i_name = lv_upper_name ).
                DATA(lv_named_val)  = lo_named_data->get_quickinfo( ).

                IF lv_first = abap_false.
                  lv_json = |{ lv_json },|.
                ENDIF.
                lv_first = abap_false.

                lv_json = |{ lv_json }{ lv_brace_open }| &&
                          |"name":"{ escape_json( lv_upper_name ) }",| &&
                          |"value":"{ escape_json( lv_named_val ) }",| &&
                          |"scope":"named"{ lv_brace_close }|.

              CATCH cx_tpdapi_failure cx_root.
                IF lv_first = abap_false.
                  lv_json = |{ lv_json },|.
                ENDIF.
                lv_first = abap_false.
                lv_json = |{ lv_json }{ lv_brace_open }| &&
                          |"name":"{ escape_json( lv_upper_name ) }",| &&
                          |"value":"<not found>",| &&
                          |"scope":"named"{ lv_brace_close }|.
            ENDTRY.
          ENDLOOP.

        ELSEIF lv_scope = 'system' OR lv_scope = 'all'.
          DATA(lt_sy_vars) = VALUE string_table(
            ( `SY-SUBRC` ) ( `SY-TABIX` ) ( `SY-INDEX` ) ( `SY-DBCNT` )
            ( `SY-UNAME` ) ( `SY-DATUM` ) ( `SY-UZEIT` ) ( `SY-CPROG` )
          ).

          LOOP AT lt_sy_vars INTO DATA(lv_var_name).
            TRY.
                DATA(lo_data) = lo_data_services->get_data( i_name = lv_var_name ).
                DATA(lv_value) = lo_data->get_quickinfo( ).

                IF lv_first = abap_false.
                  lv_json = |{ lv_json },|.
                ENDIF.
                lv_first = abap_false.

                lv_json = |{ lv_json }{ lv_brace_open }| &&
                          |"name":"{ escape_json( lv_var_name ) }",| &&
                          |"value":"{ escape_json( lv_value ) }",| &&
                          |"scope":"system"{ lv_brace_close }|.

              CATCH cx_tpdapi_failure cx_root ##NO_HANDLER.
            ENDTRY.
          ENDLOOP.
        ENDIF.

        lv_json = |{ lv_json }]|.

        rs_response = VALUE #(
          id      = is_message-id
          success = abap_true
          data    = |{ lv_brace_open }"variables":{ lv_json },"scope":"{ lv_scope }"{ lv_brace_close }|
        ).

      CATCH cx_tpdapi_failure cx_root INTO DATA(lx_error).
        rs_response = error_response(
          iv_id      = is_message-id
          iv_code    = 'GET_VARIABLES_FAILED'
          iv_message = lx_error->get_text( )
        ).
    ENDTRY.
  ENDMETHOD.

  METHOD handle_detach.
    DATA(lv_brace_open) = '{'.
    DATA(lv_brace_close) = '}'.

    IF mo_dbg_session IS INITIAL.
      rs_response = VALUE #(
        id      = is_message-id
        success = abap_true
        data    = |{ lv_brace_open }"detached":true,"message":"No active debug session"{ lv_brace_close }|
      ).
      RETURN.
    ENDIF.

    TRY.
        DATA(lo_control) = mo_dbg_session->get_control_services( ).
        lo_control->end_debugger( ).

        DATA(lv_prev_debuggee) = mv_attached_debuggee.
        CLEAR: mo_dbg_session, mv_attached_debuggee.

        rs_response = VALUE #(
          id      = is_message-id
          success = abap_true
          data    = |{ lv_brace_open }"detached":true,"debuggeeId":"{ escape_json( lv_prev_debuggee ) }"{ lv_brace_close }|
        ).

      CATCH cx_tpdapi_failure cx_root INTO DATA(lx_error).
        CLEAR: mo_dbg_session, mv_attached_debuggee.
        rs_response = VALUE #(
          id      = is_message-id
          success = abap_true
          data    = |{ lv_brace_open }"detached":true,"warning":"{ escape_json( lx_error->get_text( ) ) }"{ lv_brace_close }|
        ).
    ENDTRY.
  ENDMETHOD.

  METHOD handle_set_breakpoint.
    DATA lv_kind TYPE string.
    DATA lv_uri TYPE string.
    DATA lv_line TYPE i.
    DATA lv_exception TYPE string.
    DATA lv_statement TYPE string.
    DATA lv_condition TYPE string.
    DATA lv_program TYPE string.
    DATA lo_bp TYPE REF TO if_tpdapi_bp.

    lv_kind = extract_param( iv_params = is_message-params iv_name = 'kind' ).
    lv_uri = extract_param( iv_params = is_message-params iv_name = 'uri' ).
    lv_line = extract_param_int( iv_params = is_message-params iv_name = 'line' ).
    lv_exception = extract_param( iv_params = is_message-params iv_name = 'exception' ).
    lv_statement = extract_param( iv_params = is_message-params iv_name = 'statement' ).
    lv_condition = extract_param( iv_params = is_message-params iv_name = 'condition' ).
    lv_program = extract_param( iv_params = is_message-params iv_name = 'program' ).

    IF lv_kind IS INITIAL.
      lv_kind = 'line'.
    ENDIF.

    CASE lv_kind.
      WHEN 'line'.
        IF ( lv_uri IS INITIAL AND lv_program IS INITIAL ) OR lv_line <= 0.
          rs_response = error_response(
            iv_id = is_message-id
            iv_code = 'INVALID_PARAMS'
            iv_message = 'Line breakpoint requires (uri or program) and line parameters'
          ).
          RETURN.
        ENDIF.
        IF lv_program IS INITIAL.
          lv_program = extract_program_from_uri( lv_uri ).
        ENDIF.
        IF lv_program IS INITIAL.
          rs_response = error_response(
            iv_id = is_message-id
            iv_code = 'INVALID_URI'
            iv_message = |Cannot extract program name from URI: { lv_uri }|
          ).
          RETURN.
        ENDIF.
      WHEN 'exception'.
        IF lv_exception IS INITIAL.
          rs_response = error_response(
            iv_id = is_message-id
            iv_code = 'INVALID_PARAMS'
            iv_message = 'Exception breakpoint requires exception parameter'
          ).
          RETURN.
        ENDIF.
      WHEN 'statement'.
        IF lv_statement IS INITIAL.
          rs_response = error_response(
            iv_id = is_message-id
            iv_code = 'INVALID_PARAMS'
            iv_message = 'Statement breakpoint requires statement parameter'
          ).
          RETURN.
        ENDIF.
      WHEN OTHERS.
        rs_response = error_response(
          iv_id = is_message-id
          iv_code = 'INVALID_KIND'
          iv_message = |Invalid breakpoint kind '{ lv_kind }'|
        ).
        RETURN.
    ENDCASE.

    " Generate breakpoint ID
    DATA lv_bp_id TYPE string.
    DATA lv_uuid TYPE sysuuid_c32.
    TRY.
        lv_uuid = cl_system_uuid=>create_uuid_c32_static( ).
      CATCH cx_uuid_error.
        lv_uuid = |BP{ sy-uzeit }{ sy-datum }|.
    ENDTRY.
    lv_bp_id = lv_uuid.

    " Set breakpoint via TPDAPI
    TRY.
        ensure_bp_context( ).
        DATA(lo_bp_services) = get_static_bp_services( ).

        CASE lv_kind.
          WHEN 'line'.
            lo_bp ?= lo_bp_services->create_line_breakpoint(
              i_main_program = lv_program
              i_line_nr      = lv_line
            ).

          WHEN 'exception'.
            lo_bp ?= lo_bp_services->create_exception_breakpoint(
              i_exception = lv_exception
            ).

          WHEN 'statement'.
            lo_bp ?= lo_bp_services->create_statement_breakpoint(
              i_statement = lv_statement
            ).
        ENDCASE.

        " Store mapping between our ID and TPDAPI breakpoint
        APPEND VALUE #( id = lv_bp_id ref_bp = lo_bp ) TO mt_bp_mappings.

        " Also store in our internal table for getBreakpoints
        APPEND VALUE #(
          id        = lv_bp_id
          kind      = lv_kind
          uri       = lv_uri
          line      = lv_line
          enabled   = abap_true
          condition = lv_condition
          exception = lv_exception
          statement = lv_statement
        ) TO mt_breakpoints.

        DATA(lv_brace_open) = '{'.
        DATA(lv_brace_close) = '}'.
        rs_response = VALUE #(
          id      = is_message-id
          success = abap_true
          data    = |{ lv_brace_open }"breakpointId":"{ lv_bp_id }","kind":"{ lv_kind }","registered":true| &&
                    COND #( WHEN lv_program IS NOT INITIAL THEN |,"program":"{ escape_json( lv_program ) }"| ELSE '' ) &&
                    COND #( WHEN lv_uri IS NOT INITIAL THEN |,"uri":"{ escape_json( lv_uri ) }","line":{ lv_line }| ELSE '' ) &&
                    COND #( WHEN lv_exception IS NOT INITIAL THEN |,"exception":"{ escape_json( lv_exception ) }"| ELSE '' ) &&
                    COND #( WHEN lv_statement IS NOT INITIAL THEN |,"statement":"{ escape_json( lv_statement ) }"| ELSE '' ) &&
                    |{ lv_brace_close }|
        ).

      CATCH cx_tpdapi_existing INTO DATA(lx_existing).
        rs_response = error_response(
          iv_id      = is_message-id
          iv_code    = 'BREAKPOINT_EXISTS'
          iv_message = |Breakpoint already exists: { lx_existing->get_text( ) }|
        ).

      CATCH cx_tpdapi_invalid_param cx_tpdapi_invalid_user
            cx_tpdapi_not_authorized cx_tpdapi_insufficient_data
            cx_tpdapi_failure cx_root INTO DATA(lx_error).
        rs_response = error_response(
          iv_id      = is_message-id
          iv_code    = 'SET_BREAKPOINT_FAILED'
          iv_message = lx_error->get_text( )
        ).
    ENDTRY.
  ENDMETHOD.

  METHOD handle_get_breakpoints.
    DATA(lv_brace_open) = '{'.
    DATA(lv_brace_close) = '}'.

    DATA lv_json TYPE string.
    DATA lv_first TYPE abap_bool VALUE abap_true.

    lv_json = '['.

    LOOP AT mt_breakpoints INTO DATA(ls_bp).
      IF lv_first = abap_false.
        lv_json = |{ lv_json },|.
      ENDIF.
      lv_first = abap_false.

      lv_json = |{ lv_json }{ lv_brace_open }"id":"{ ls_bp-id }","kind":"{ ls_bp-kind }"|.
      IF ls_bp-uri IS NOT INITIAL.
        lv_json = |{ lv_json },"uri":"{ escape_json( ls_bp-uri ) }","line":{ ls_bp-line }|.
      ENDIF.
      IF ls_bp-exception IS NOT INITIAL.
        lv_json = |{ lv_json },"exception":"{ escape_json( ls_bp-exception ) }"|.
      ENDIF.
      IF ls_bp-statement IS NOT INITIAL.
        lv_json = |{ lv_json },"statement":"{ escape_json( ls_bp-statement ) }"|.
      ENDIF.
      lv_json = |{ lv_json }{ lv_brace_close }|.
    ENDLOOP.

    lv_json = |{ lv_json }]|.

    rs_response = VALUE #(
      id      = is_message-id
      success = abap_true
      data    = |{ lv_brace_open }"breakpoints":{ lv_json }{ lv_brace_close }|
    ).
  ENDMETHOD.

  METHOD handle_delete_breakpoint.
    DATA lv_bp_id TYPE string.
    lv_bp_id = extract_param( iv_params = is_message-params iv_name = 'breakpointId' ).

    IF lv_bp_id IS INITIAL.
      rs_response = error_response(
        iv_id = is_message-id
        iv_code = 'INVALID_PARAMS'
        iv_message = 'breakpointId parameter required'
      ).
      RETURN.
    ENDIF.

    READ TABLE mt_bp_mappings WITH KEY id = lv_bp_id INTO DATA(ls_mapping).
    IF sy-subrc <> 0.
      READ TABLE mt_breakpoints WITH KEY id = lv_bp_id TRANSPORTING NO FIELDS.
      IF sy-subrc <> 0.
        rs_response = error_response(
          iv_id = is_message-id
          iv_code = 'NOT_FOUND'
          iv_message = |Breakpoint { lv_bp_id } not found|
        ).
        RETURN.
      ENDIF.
    ENDIF.

    IF ls_mapping-ref_bp IS NOT INITIAL.
      TRY.
          DATA(lo_bp_services) = get_static_bp_services( ).
          lo_bp_services->delete_breakpoint( i_ref_bp = ls_mapping-ref_bp ).
        CATCH cx_tpdapi_failure cx_root INTO DATA(lx_error).
      ENDTRY.
    ENDIF.

    DELETE mt_bp_mappings WHERE id = lv_bp_id.
    DELETE mt_breakpoints WHERE id = lv_bp_id.

    DATA(lv_brace_open) = '{'.
    DATA(lv_brace_close) = '}'.
    rs_response = VALUE #(
      id      = is_message-id
      success = abap_true
      data    = |{ lv_brace_open }"deleted":"{ lv_bp_id }"{ lv_brace_close }|
    ).
  ENDMETHOD.

  METHOD handle_get_status.
    DATA(lv_brace_open) = '{'.
    DATA(lv_brace_close) = '}'.

    DATA lv_bp_count TYPE i.
    DATA lv_attached TYPE string.
    DATA lv_listener TYPE string.

    lv_bp_count = lines( mt_breakpoints ).
    lv_attached = COND #( WHEN mo_dbg_session IS NOT INITIAL THEN 'true' ELSE 'false' ).
    lv_listener = COND #( WHEN mv_listener_active = abap_true THEN 'true' ELSE 'false' ).

    rs_response = VALUE #(
      id      = is_message-id
      success = abap_true
      data    = |{ lv_brace_open }"sessionId":"{ mv_session_id }",| &&
                |"user":"{ mv_debug_user }",| &&
                |"host":"{ sy-host }",| &&
                |"listenMode":"{ mv_listen_mode }",| &&
                |"terminalId":"{ mv_terminal_id }",| &&
                |"ideId":"{ mv_ide_id }",| &&
                |"breakpointCount":{ lv_bp_count },| &&
                |"attached":{ lv_attached },| &&
                |"attachedDebuggee":"{ escape_json( mv_attached_debuggee ) }",| &&
                |"listenerActive":{ lv_listener },| &&
                |"debuggingAvailable":{ COND #( WHEN cl_tpdapi_service=>is_debugging_available( ) IS NOT INITIAL THEN 'true' ELSE 'false' ) }| &&
                |{ lv_brace_close }|
    ).
  ENDMETHOD.

  METHOD extract_param.
    DATA lv_pattern TYPE string.
    lv_pattern = |"{ iv_name }"\\s*:\\s*"([^"]*)"|.
    FIND PCRE lv_pattern IN iv_params SUBMATCHES rv_value.
  ENDMETHOD.

  METHOD extract_param_int.
    DATA lv_pattern TYPE string.
    DATA lv_str TYPE string.
    lv_pattern = |"{ iv_name }"\\s*:\\s*(\\d+)|.
    FIND PCRE lv_pattern IN iv_params SUBMATCHES lv_str.
    IF sy-subrc = 0.
      rv_value = lv_str.
    ENDIF.
  ENDMETHOD.

  METHOD extract_param_array.
    " Extract JSON array values: "name":["val1","val2",...]
    DATA lv_array TYPE string.
    DATA(lv_pattern) = |"{ iv_name }"\\s*:\\s*\\[([^\\]]*)\\]|.
    FIND PCRE lv_pattern IN iv_params SUBMATCHES lv_array.
    IF sy-subrc = 0 AND lv_array IS NOT INITIAL.
      FIND ALL OCCURRENCES OF PCRE '"([^"]*)"' IN lv_array
        RESULTS DATA(lt_results).
      LOOP AT lt_results INTO DATA(ls_result).
        READ TABLE ls_result-submatches INTO DATA(ls_sub) INDEX 1.
        IF sy-subrc = 0.
          APPEND lv_array+ls_sub-offset(ls_sub-length) TO rt_values.
        ENDIF.
      ENDLOOP.
    ENDIF.
  ENDMETHOD.

  METHOD escape_json.
    rv_escaped = iv_string.
    REPLACE ALL OCCURRENCES OF '\' IN rv_escaped WITH '\\'.
    REPLACE ALL OCCURRENCES OF '"' IN rv_escaped WITH '\"'.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf IN rv_escaped WITH '\n'.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline IN rv_escaped WITH '\n'.
  ENDMETHOD.

  METHOD error_response.
    DATA(lv_brace_open) = '{'.
    DATA(lv_brace_close) = '}'.
    rs_response = VALUE #(
      id      = iv_id
      success = abap_false
      error   = |{ lv_brace_open }"code":"{ iv_code }","message":"{ escape_json( iv_message ) }"{ lv_brace_close }|
    ).
  ENDMETHOD.

  METHOD init_terminal_ids.
    IF mv_terminal_id IS NOT INITIAL.
      RETURN.
    ENDIF.
    " Use a deterministic terminal ID derived from the username.
    " The Go client creates a new WebSocket connection per command,
    " so breakpoints set in one connection must be found by the
    " listener in the next connection. A random UUID would differ
    " between connections, causing terminal ID mismatch.
    DATA lv_id TYPE sysuuid_c32.
    CONCATENATE 'VSPDEBUG' sy-uname INTO lv_id.
    " Fill remaining positions with zeros (CHAR32, right-padded)
    TRANSLATE lv_id USING ' 0'.
    mv_terminal_id = lv_id.
    mv_ide_id = mv_terminal_id.
  ENDMETHOD.

  METHOD cleanup_stale_artifacts.
    DATA lt_bps TYPE STANDARD TABLE OF abdbg_extdbps WITH DEFAULT KEY.
    DATA ls_bp  TYPE abdbg_extdbps.

    SELECT * FROM abdbg_extdbps
      INTO TABLE lt_bps WHERE username = sy-uname.

    LOOP AT lt_bps INTO ls_bp.
      IF ls_bp-breakpoint CP '*INCLUDE=L*VSP*'.
        DELETE FROM abdbg_extdbps
          WHERE username = sy-uname
            AND bp_index = ls_bp-bp_index.
        CALL FUNCTION 'DB_COMMIT'.
      ENDIF.
    ENDLOOP.

    DATA lt_icf TYPE STANDARD TABLE OF icfattrib WITH DEFAULT KEY.
    DATA ls_icf TYPE icfattrib.

    SELECT * FROM icfattrib
      INTO TABLE lt_icf
      WHERE cusername = sy-uname.

    LOOP AT lt_icf INTO ls_icf.
      CHECK ls_icf-call_url CS 'A=X'.
      IF mv_listen_mode = 'TERMINAL' AND mv_terminal_id IS NOT INITIAL.
        CHECK ls_icf-url = '%_TERMINAL_ID'.
        CHECK ls_icf-username(1) = '!'.
        " Preserve current session entries
        IF mv_terminal_id IS NOT INITIAL AND ls_icf-debugid CS mv_terminal_id.
          CONTINUE.
        ENDIF.
      ELSE.
        CHECK ls_icf-url = '%_SYSTEM'.
        CHECK ls_icf-username = sy-uname.
      ENDIF.
      DELETE FROM icfattrib
        WHERE username = ls_icf-username
          AND server   = ls_icf-server
          AND url      = ls_icf-url.
      CALL FUNCTION 'DB_COMMIT'.
    ENDLOOP.
  ENDMETHOD.

  METHOD set_terminal_id_epp.
    CONSTANTS:
      c_section TYPE int2 VALUE 2,
      c_key     TYPE int2 VALUE 1.
    DATA lv_termid TYPE sysuuid_x16.
    lv_termid = iv_terminal_id.
    TRY.
        cl_epp_system_factory=>get_section( id = c_section
          )->delete_item_by_key( key = c_key ).
      CATCH cx_epp_error ##NO_HANDLER.
    ENDTRY.
    TRY.
        cl_epp_system_factory=>get_section( c_section
          )->set_item_by_key_as_xuuid(
            key   = c_key
            value = lv_termid ).
      CATCH cx_epp_error ##NO_HANDLER.
    ENDTRY.
  ENDMETHOD.

ENDCLASS.

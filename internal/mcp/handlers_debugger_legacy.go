// Package mcp provides the MCP server implementation for ABAP ADT tools.
// handlers_debugger_legacy.go contains handlers for debugger session operations.
// These now use WebSocket (ZADT_VSP) via TPDAPI for all operations (listen, attach, step, etc.)
// matching the same transport used for breakpoints.
package mcp

import (
	"context"
	"fmt"
	"strings"

	"github.com/mark3labs/mcp-go/mcp"
)

// routeDebuggerLegacyAction routes "debug" sub-actions for the debugger session operations.
func (s *Server) routeDebuggerLegacyAction(ctx context.Context, action, objectType, objectName string, params map[string]any) (*mcp.CallToolResult, bool, error) {
	if action != "debug" {
		return nil, false, nil
	}
	switch objectType {
	case "LISTEN":
		return s.callHandler(ctx, s.handleDebuggerListen, params)
	case "ATTACH":
		return s.callHandler(ctx, s.handleDebuggerAttach, params)
	case "DETACH":
		return s.callHandler(ctx, s.handleDebuggerDetach, params)
	case "STEP":
		return s.callHandler(ctx, s.handleDebuggerStep, params)
	case "GET_STACK":
		return s.callHandler(ctx, s.handleDebuggerGetStack, params)
	case "GET_VARIABLES":
		return s.callHandler(ctx, s.handleDebuggerGetVariables, params)
	}
	return nil, false, nil
}

// --- WebSocket-based Debugger Session Handlers (via ZADT_VSP / TPDAPI) ---

func (s *Server) handleDebuggerListen(ctx context.Context, request mcp.CallToolRequest) (*mcp.CallToolResult, error) {
	timeout := 60 // default
	if t, ok := request.GetArguments()["timeout"].(float64); ok && t > 0 {
		timeout = int(t)
		if timeout > 240 {
			timeout = 240
		}
	}

	// Ensure WebSocket client is connected
	if err := s.ensureDebugWSClient(ctx); err != nil {
		return newToolResultError(fmt.Sprintf("Failed to connect to ZADT_VSP WebSocket: %v. Ensure ZADT_VSP is deployed and SAPC/SICF are configured.", err)), nil
	}

	debuggees, err := s.debugWSClient.Listen(ctx, timeout)
	if err != nil {
		return newToolResultError(fmt.Sprintf("DebuggerListen failed: %v", err)), nil
	}

	if len(debuggees) == 0 {
		return mcp.NewToolResultText("Listener timed out - no debuggee hit a breakpoint within the timeout period."), nil
	}

	var sb strings.Builder
	sb.WriteString("Debuggee caught!\n\n")
	for i, d := range debuggees {
		if i > 0 {
			sb.WriteString("\n---\n")
		}
		fmt.Fprintf(&sb, "Debuggee ID: %s\n", d.ID)
		fmt.Fprintf(&sb, "User: %s\n", d.User)
		fmt.Fprintf(&sb, "Program: %s\n", d.Program)
		fmt.Fprintf(&sb, "Host: %s\n", d.Host)
		fmt.Fprintf(&sb, "Same Server: %v\n", d.SameServer)
	}
	sb.WriteString("\nUse DebuggerAttach with the debuggee_id to attach to this session.")
	return mcp.NewToolResultText(sb.String()), nil
}

func (s *Server) handleDebuggerAttach(ctx context.Context, request mcp.CallToolRequest) (*mcp.CallToolResult, error) {
	debuggeeID, ok := request.GetArguments()["debuggee_id"].(string)
	if !ok || debuggeeID == "" {
		return newToolResultError("debuggee_id is required"), nil
	}

	if err := s.ensureDebugWSClient(ctx); err != nil {
		return newToolResultError(fmt.Sprintf("Failed to connect to ZADT_VSP WebSocket: %v", err)), nil
	}

	frame, err := s.debugWSClient.Attach(ctx, debuggeeID)
	if err != nil {
		return newToolResultError(fmt.Sprintf("DebuggerAttach failed: %v", err)), nil
	}

	var sb strings.Builder
	sb.WriteString("Successfully attached to debuggee!\n\n")
	fmt.Fprintf(&sb, "Debuggee ID: %s\n", debuggeeID)
	if frame != nil {
		fmt.Fprintf(&sb, "Program: %s\n", frame.Program)
		fmt.Fprintf(&sb, "Include: %s\n", frame.Include)
		fmt.Fprintf(&sb, "Line: %d\n", frame.Line)
	}
	sb.WriteString("\nUse DebuggerGetStack to see the call stack, DebuggerGetVariables to inspect variables.")
	return mcp.NewToolResultText(sb.String()), nil
}

func (s *Server) handleDebuggerDetach(ctx context.Context, request mcp.CallToolRequest) (*mcp.CallToolResult, error) {
	if err := s.ensureDebugWSClient(ctx); err != nil {
		return newToolResultError(fmt.Sprintf("Failed to connect to ZADT_VSP WebSocket: %v", err)), nil
	}

	err := s.debugWSClient.Detach(ctx)
	if err != nil {
		return newToolResultError(fmt.Sprintf("DebuggerDetach failed: %v", err)), nil
	}

	return mcp.NewToolResultText("Successfully detached from debug session."), nil
}

func (s *Server) handleDebuggerStep(ctx context.Context, request mcp.CallToolRequest) (*mcp.CallToolResult, error) {
	stepTypeStr, ok := request.GetArguments()["step_type"].(string)
	if !ok || stepTypeStr == "" {
		return newToolResultError("step_type is required"), nil
	}

	// Map MCP step type names to WebSocket step type names
	var wsStepType string
	switch stepTypeStr {
	case "stepInto":
		wsStepType = "into"
	case "stepOver":
		wsStepType = "over"
	case "stepReturn":
		wsStepType = "return"
	case "stepContinue":
		wsStepType = "continue"
	default:
		return newToolResultError(fmt.Sprintf("Invalid step_type: %s. Valid values: stepInto, stepOver, stepReturn, stepContinue", stepTypeStr)), nil
	}

	if err := s.ensureDebugWSClient(ctx); err != nil {
		return newToolResultError(fmt.Sprintf("Failed to connect to ZADT_VSP WebSocket: %v", err)), nil
	}

	frame, err := s.debugWSClient.Step(ctx, wsStepType)
	if err != nil {
		return newToolResultError(fmt.Sprintf("DebuggerStep failed: %v", err)), nil
	}

	if frame == nil {
		return mcp.NewToolResultText(fmt.Sprintf("Step '%s' executed. Debuggee has ended.", stepTypeStr)), nil
	}

	var sb strings.Builder
	fmt.Fprintf(&sb, "Step '%s' executed.\n\n", stepTypeStr)
	fmt.Fprintf(&sb, "Program: %s\n", frame.Program)
	fmt.Fprintf(&sb, "Include: %s\n", frame.Include)
	fmt.Fprintf(&sb, "Line: %d\n", frame.Line)
	if frame.Procedure != "" {
		fmt.Fprintf(&sb, "Procedure: %s\n", frame.Procedure)
	}
	sb.WriteString("\nUse DebuggerGetStack to see current position, DebuggerGetVariables to inspect variables.")
	return mcp.NewToolResultText(sb.String()), nil
}

func (s *Server) handleDebuggerGetStack(ctx context.Context, request mcp.CallToolRequest) (*mcp.CallToolResult, error) {
	if err := s.ensureDebugWSClient(ctx); err != nil {
		return newToolResultError(fmt.Sprintf("Failed to connect to ZADT_VSP WebSocket: %v", err)), nil
	}

	stack, err := s.debugWSClient.GetStack(ctx)
	if err != nil {
		return newToolResultError(fmt.Sprintf("DebuggerGetStack failed: %v", err)), nil
	}

	if len(stack) == 0 {
		return mcp.NewToolResultText("Call stack is empty."), nil
	}

	var sb strings.Builder
	sb.WriteString("Call Stack:\n\n")

	for i, frame := range stack {
		marker := "  "
		if frame.Active {
			marker = "→ "
		}
		fmt.Fprintf(&sb, "%s[%d] %s (line %d)\n", marker, frame.Index, frame.Program, frame.Line)
		if frame.Include != "" && frame.Include != frame.Program {
			fmt.Fprintf(&sb, "      Include: %s\n", frame.Include)
		}
		if frame.Procedure != "" {
			fmt.Fprintf(&sb, "      Procedure: %s\n", frame.Procedure)
		}
		if frame.System {
			sb.WriteString("      (system program)\n")
		}
		if i < len(stack)-1 {
			sb.WriteString("\n")
		}
	}

	return mcp.NewToolResultText(sb.String()), nil
}

func (s *Server) handleDebuggerGetVariables(ctx context.Context, request mcp.CallToolRequest) (*mcp.CallToolResult, error) {
	if err := s.ensureDebugWSClient(ctx); err != nil {
		return newToolResultError(fmt.Sprintf("Failed to connect to ZADT_VSP WebSocket: %v", err)), nil
	}

	// Determine scope from variable_ids parameter for backward compatibility
	scope := "system"
	if ids, ok := request.GetArguments()["variable_ids"].([]interface{}); ok && len(ids) > 0 {
		// If specific variables are requested, use "all" scope
		if len(ids) > 0 {
			if firstID, ok := ids[0].(string); ok && firstID != "@ROOT" {
				scope = "all"
			}
		}
	}

	variables, err := s.debugWSClient.GetVariables(ctx, scope)
	if err != nil {
		return newToolResultError(fmt.Sprintf("DebuggerGetVariables failed: %v", err)), nil
	}

	if len(variables) == 0 {
		return mcp.NewToolResultText("No variables found."), nil
	}

	var sb strings.Builder
	sb.WriteString("Variables:\n\n")

	for _, v := range variables {
		fmt.Fprintf(&sb, "%s = %s\n", v.Name, v.Value)
		if v.Scope != "" {
			fmt.Fprintf(&sb, "  Scope: %s\n", v.Scope)
		}
	}

	return mcp.NewToolResultText(sb.String()), nil
}

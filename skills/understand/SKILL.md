---
name: understand
description: "Multi-specialist collaborative analysis to understand how features, functions, or components work. Use when the user says '/understand', 'how does X work', 'explain this feature', 'trace this function', or wants a comprehensive analysis of a codebase component."
---

# Multi-Agent Understanding Analysis

Execute multi-specialist analysis using independent subagents to comprehensively understand codebase features. This skill is runtime-neutral and works in Claude Code, OpenCode, and Codex.

## Arguments

```text
/understand [feature/function/component to analyze]
```

The argument may be a feature name, function, component, module, or system area to analyze (e.g., "authentication system", "User model", "PDF generation").

## Runtime Compatibility

| Runtime | Specialist Launch | Codex Fresh Eyes |
|---|---|---|
| Claude Code | Use Task/Agent with subagents | Use `mcp__codex__codex` if available |
| OpenCode | Use the Task tool with subagents | Use `codex_codex` if available |
| Codex | Spawn custom agents when available; otherwise run prompts directly | Use a separate Codex session when available |

## Phase 1: Specialist Assignment and Analysis

Analyze target scope and launch 4-7 parallel subagents. Select specialists based on what the target actually is — skip irrelevant ones.

### Specialist Roster

| Specialist | Purpose | Select When |
|---|---|---|
| Code Structure Analyst | Definitions, file locations, dependencies, imports, module relationships | Always |
| Data Flow Analyst | Input/output, transformations, state management, side effects | Always |
| Usage Pattern Analyst | Where used, how called, integration points, configuration | Always |
| UX/UI Analyst | Components, templates, styling, interactions, accessibility | UI components, pages, frontend features |
| Database Analyst | Schema, queries, constraints, indexes, relationships | Data models, persistence, migrations |
| API Analyst | Endpoints, request/response patterns, GraphQL, external services | API routes, service integrations |
| Test Coverage Analyst | Test files, coverage, scenarios, edge cases, testing strategy | Always |
| Codex Fresh Eyes | High-level purpose, design decisions, architectural choices | When Codex is available |

### Selection Criteria

| Target Type | Specialists |
|---|---|
| Function/Method | Code Structure, Data Flow, Usage Pattern, Test Coverage |
| UI Component | Code Structure, UX/UI, Usage Pattern, Data Flow, Test Coverage |
| API/Service | Code Structure, API, Data Flow, Usage Pattern, Test Coverage |
| Database Logic | Database, Code Structure, Data Flow, Test Coverage |
| Feature/System | All applicable specialists |

### Specialist Prompts

Each specialist must:
- Use Grep/Glob extensively to map the codebase
- Read key implementation files for detailed analysis
- Provide findings with `file:line` references
- Focus on facts and structure, not evaluation

**Code Structure Analyst**: Analyze [target] structure by finding definitions, tracing implementation paths, identifying file locations, dependencies, and imports. Map the module/file graph.

**Data Flow Analyst**: Examine [target] data flow, input/output patterns, state management, transformations, and side effects. Trace data from entry to exit points.

**Usage Pattern Analyst**: Find where [target] is used/called, identify integration points, common usage patterns, configuration options, and calling contexts throughout codebase.

**UX/UI Analyst**: Analyze [target] user interface aspects including components, templates, styling, user interactions, and accessibility patterns.

**Database Analyst**: Investigate [target] database interactions, schema relationships, queries, constraints, indexes, and data integrity patterns.

**API Analyst**: Examine [target] API interactions, endpoints, request/response patterns, GraphQL queries/mutations, REST calls, and external service integrations.

**Test Coverage Analyst**: Locate tests for [target], analyze test coverage, key test scenarios, edge cases, and testing strategies. Map test files to implementation.

**Codex Fresh Eyes**: Analyze [target] from scratch with fresh eyes. What is this component/feature actually doing at a high level? How would you explain its purpose and implementation approach to someone unfamiliar with this codebase? What design decisions and architectural choices do you recognize?

## Phase 2: Cross-Pollination and Integration

After collecting specialist reports, perform a synthesis pass:

1. Connect findings across specialists — identify interaction patterns
2. Validate conclusions across domains
3. Identify gaps where no specialist covered a relevant area
4. Resolve contradictions between specialist findings

When Codex is available, run a **Codex Integration Synthesis**: Review all specialist analyses and identify key insights about how the pieces fit together, integration patterns not fully explored, and architectural relationships across the broader system.

## Phase 3: Synthesis and Output

Collect all outputs and produce a structured understanding report:

```text
=== MULTI-AGENT UNDERSTANDING: [Target] ===
Scope: [Function/Component/Feature/System] | Specialists: [list]

SPECIALIST ANALYSIS
[Each specialist's domain findings with file:line references]

CODEX FRESH EYES (when available)
[Independent perspective on purpose and implementation approach]

CROSS-VALIDATION
[How specialist findings connect, validate, or contradict each other]

--- COMPREHENSIVE UNDERSTANDING ---

### Overview
[Purpose, functionality, and role in system]

### Location and Structure
- Main files: [paths:line numbers]
- Related files: [connected modules and dependencies]

### How It Works
[Step-by-step flow]
1. [Entry points and initialization]
2. [Key logic and processing steps]
3. [Output and side effects]

### Dependencies
- Internal: [project dependencies]
- External: [libraries, APIs, services]

### Usage Examples
[Common patterns with examples and calling contexts]

### UI/UX Integration (if applicable)
- Components: [structure and hierarchy]
- Interactions: [user flows and state changes]
- Styling: [CSS/styling approaches]

### Database Integration (if applicable)
- Tables/schemas: [relevant tables and relationships]
- Queries: [key database operations]
- Constraints: [indexes and integrity rules]

### API Integration (if applicable)
- Endpoints: [REST/GraphQL operations]
- Data flow: [request/response patterns]
- Services: [external integrations]

### Testing
- Test files: [paths and coverage]
- Key scenarios: [test cases and edge cases]

### Notes and Considerations
- Performance: [implications and bottlenecks]
- Security: [considerations and risks]
- Limitations: [known constraints]
```

## Search Strategy

Specialists use a systematic approach:
- Grep for definitions and usages across the codebase
- Glob to locate related files by patterns
- Read key implementation files for detailed analysis
- Use runtime-specific MCP tools when available (Tidewave for Elixir/Ecto, psql for database)

## Rules

- Launch specialists in parallel when the runtime supports it
- Every finding must include `file:line` references
- Focus on understanding, not evaluation — describe what exists and how it works
- Skip specialists that are not relevant to the target
- Codex Fresh Eyes is included when Codex is available; otherwise skip it
- Do not modify any files — this skill is read-only analysis

$ARGUMENTS

---
name: document
description: "Generate focused documentation for components, functions, APIs, and features. Use when the user says '/document', 'document this', 'generate docs', 'write docs for', or needs inline, API, guide, or external documentation."
---

# /document - Focused Documentation Generation

Generate focused documentation for specific components, functions, APIs, and features. This skill is runtime-neutral and works in Claude Code, OpenCode, and Codex.

## Arguments

```text
/document [what to document] [format: inline/api/guide/external]
```

The argument may be a file path, function name, feature area, or description of what to document. An optional format hint (inline, api, guide, external) controls the output style. If omitted, infer the best format from context.

## Behavioral Flow

1. **Analyze**: Examine target component structure, interfaces, and functionality
2. **Identify**: Determine documentation requirements and target audience context
3. **Generate**: Create appropriate documentation content
4. **Format**: Apply consistent structure and organizational patterns
5. **Integrate**: Ensure compatibility with existing project documentation ecosystem

Key behaviors:
- Code structure analysis with API extraction and usage pattern identification
- Multi-format documentation generation (inline, external, API reference, guides)
- Consistent formatting and cross-reference integration
- Project-specific documentation patterns matching existing conventions

## Tool Coordination

- **Read**: Component analysis and existing documentation review
- **Grep**: Reference extraction and pattern identification
- **Write**: Documentation file creation with proper formatting
- **Glob**: Multi-file documentation projects and organization
- **Bash**: Database structure analysis for data model documentation

## Documentation Formats

### Inline Documentation
Add JSDoc, docstrings, typespecs, or inline comments directly to source files.

1. Read the target file(s)
2. Identify functions, modules, types, and interfaces that lack documentation
3. Analyze parameter types, return values, side effects, and usage patterns
4. Add documentation comments following the language's conventions:
   - **JavaScript/TypeScript**: JSDoc with `@param`, `@returns`, `@example`
   - **Elixir**: `@doc`, `@moduledoc`, `@spec` typespecs
   - **Python**: Docstrings with parameter and return descriptions
5. Preserve existing documentation — only add or enhance, never remove

### API Documentation
Generate reference material for APIs, endpoints, or public interfaces.

1. Identify all public endpoints, functions, or interfaces in the target
2. Extract request/response schemas, parameters, and return types
3. Generate structured reference with:
   - Endpoint or function signature
   - Parameter descriptions with types and constraints
   - Response format with examples
   - Error cases and status codes
   - Usage examples with realistic data
4. Write to the specified output path or `docs/api/`

### User Guide
Create task-oriented documentation for end users or developers.

1. Analyze the feature's user-facing behavior and common workflows
2. Structure as a guide with:
   - Overview and purpose
   - Prerequisites
   - Step-by-step usage instructions
   - Configuration options
   - Common patterns and examples
   - Troubleshooting
3. Write to the specified output path or `docs/guides/`

### External Documentation
Generate standalone documentation files for components or libraries.

1. Analyze the component's public API, props/parameters, and behavior
2. Generate documentation with:
   - Component overview and purpose
   - Props/parameters with types and defaults
   - Usage examples
   - Integration patterns
   - Related components or modules
3. Write to the specified output path or alongside the component

## Examples

```text
/document src/auth/login.js inline
# Adds JSDoc comments to all functions in login.js

/document GraphQL API api
# Creates API reference in docs/api/ with all endpoints

/document payment module guide
# Creates user guide in docs/guides/ with workflows and examples

/document React components external
# Generates external docs with props, usage, and integration patterns

/document lib/my_app/accounts.ex inline
# Adds @doc, @moduledoc, and @spec to Elixir module
```

## Rules

- Read existing documentation conventions in the project before generating
- Match the project's existing documentation style and structure
- Never expose sensitive implementation details, secrets, or internal URLs
- Preserve existing documentation — enhance, don't replace
- Include practical examples with realistic data
- Cross-reference related components and modules where appropriate

$ARGUMENTS

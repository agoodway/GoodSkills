---
name: scratchpad
description: "Manage a gitignored .scratchpad/ directory for temporary project files. Use when the user says '/scratchpad bootstrap', '/scratchpad write', '/scratchpad edit', '/scratchpad list', or mentions 'scratchpad'. Supports creating the dir, writing files, editing files, and listing contents."
---

# Scratchpad

Manage a `.scratchpad/` directory in the current project for temporary, gitignored files.

This skill is runtime-neutral and works in Claude Code, OpenCode, and Codex. Use the current runtime's file-editing tools for writes and edits, shell tool for directory checks and listing, and question mechanism for missing user input.

## Commands

Parse the command from ARGUMENTS. Format: `/scratchpad <command> [args]`

### bootstrap

Set up `.scratchpad/` in the project root.

1. Create `.scratchpad/` directory if it doesn't exist: `mkdir -p .scratchpad`
2. Check if `.gitignore` exists at project root
   - If not, create it with `.scratchpad/` as the only entry
   - If it exists, read it and check whether `.scratchpad/` or `.scratchpad` is already listed
   - If not listed, append `.scratchpad/` on a new line at the end
3. Confirm what was done

### write \<filename\>

Write content to `.scratchpad/<filename>`.

1. Verify `.scratchpad/` exists. If not, run bootstrap first.
2. Ask the user what content to write if not provided in ARGUMENTS.
3. Use the runtime's write/edit capability to create or overwrite `.scratchpad/<filename>`.

### edit \<filename\>

Edit a file in `.scratchpad/`.

1. Verify `.scratchpad/<filename>` exists. If not, tell the user.
2. Read the file with the runtime's read capability.
3. Ask the user what changes to make if not clear from ARGUMENTS.
4. Use the runtime's edit capability to apply changes.

### list

List files in `.scratchpad/`.

1. Verify `.scratchpad/` exists. If not, tell the user to run bootstrap.
2. Run `ls -la .scratchpad/` to show contents.

# Spinner Usage Guide

This guide explains how to use the shared spinner library across all scripts.

## Quick Start

### For New Scripts

```bash
#!/usr/bin/env bash

set -euo pipefail

# Source the shared library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/spinner.sh"

# Check for required commands
require_cmd jq

# Use spinner for long operations
start_spinner "Fetching data..."
data=$(curl -s "https://api.example.com/data")
stop_spinner

echo "Done!"
```

### For Existing Scripts

To add spinner support to an existing script:

1. Add these lines after the shebang:
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/spinner.sh"
```

2. Replace `require_cmd()` definitions with library import

3. Wrap long operations with spinner:
```bash
# Before:
echo "Fetching issues..."
issues=$(gh issue list)

# After:
start_spinner "Fetching issues..."
issues=$(gh issue list)
stop_spinner
```

## Files Changed

### Created
- `lib/spinner.sh` - Shared library with spinner and require_cmd functions
- `lib/README.md` - Documentation for the library

### Modified
- `github/pr-buddy.sh` - Now sources `lib/spinner.sh` instead of duplicating functions

## Available Functions

### `start_spinner(message)`
Starts a rotating spinner animation with custom message.

### `stop_spinner()`
Stops the active spinner and cleans up the terminal.

### `require_cmd(cmd)`
Checks if a command is available; exits if not found.

## Best Practices

1. **Always call `stop_spinner()`** - Even if operations fail, ensure cleanup happens
2. **Use descriptive messages** - Users should know what's happening
3. **Wrap async operations** - Perfect for API calls, file operations, network requests
4. **Check syntax** - Always test with `bash -n yourscript.sh` after changes

## Example Operations to Wrap

- `gh` CLI commands (API calls)
- `curl` network requests
- `git fetch/pull` operations
- File processing loops
- Any operation taking >0.5 seconds

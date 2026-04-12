# lib

Shared utility functions for all scripts in this repository.

## spinner.sh

Common utility functions including spinner animations and helper functions.

### Functions

#### `start_spinner(message)`
Displays a rotating spinner animation while a long-running operation executes.

```bash
start_spinner "Processing data..."
# Your long-running operation here
stop_spinner
```

#### `stop_spinner()`
Stops the active spinner animation and clears the line.

**Note:** Always call `stop_spinner()` after `start_spinner()` to ensure cleanup.

#### `require_cmd(cmd)`
Checks if a required command is available and exits with error if not.

```bash
require_cmd gh
require_cmd jq
```

## Usage

To use these utilities in any script:

```bash
#!/usr/bin/env bash

# Determine script directory and source library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/spinner.sh"

# Now you can use the functions
require_cmd jq
start_spinner "Fetching data..."
# ... perform operation ...
stop_spinner
```

## Notes

- The spinner uses Unicode characters that require a modern terminal
- Cursor is hidden during animation and restored when stopped
- Spinner runs as a background process to avoid blocking
- Always ensure `stop_spinner()` is called, even if operations fail

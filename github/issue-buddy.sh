#!/usr/bin/env bash
#
# issue-buddy.sh: Minimal helper to create GitHub issues from the terminal.

set -euo pipefail

require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        echo "❌ Required command '$cmd' is not installed."
        exit 1
    fi
}

# --- Pre-flight checks ---
require_cmd gh
require_cmd jq

if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    echo "⚠️  Warning: Not inside a Git repository. gh will use your default repo context."
fi

echo "✅ Ready to create a GitHub issue."
echo "------------------------------"

# --- Gather user input ---
read -erp "Issue title: " issue_title
if [[ -z "$issue_title" ]]; then
    echo "❌ Title cannot be empty."
    exit 1
fi

read -erp "Issue description (optional): " issue_body

# --- Collect labels ---
declare -a selected_labels=()

mapfile -t labels_array < <(gh label list --json name --jq '.[].name' 2>/dev/null || true)

if ((${#labels_array[@]} > 0)); then
    if command -v fzf &>/dev/null; then
        echo "Select labels (space to toggle, enter to confirm):"
        label_selection=$(printf "%s\n" "${labels_array[@]}" | fzf --multi --bind "space:toggle" --prompt="Labels: " --height=100% --border || true)
        while IFS= read -r label; do
            [[ -n "$label" ]] && selected_labels+=("$label")
        done <<<"$label_selection"
    else
        echo "Available labels:"
        for i in "${!labels_array[@]}"; do
            printf "%2d. %s\n" $((i + 1)) "${labels_array[$i]}"
        done
        read -erp "Enter label numbers or names separated by commas (leave blank for none): " label_input
        if [[ -n "$label_input" ]]; then
            IFS=',' read -r -a label_tokens <<<"$label_input"
            for token in "${label_tokens[@]}"; do
                trimmed=$(echo "$token" | sed -e 's/^[ \t]*//' -e 's/[ \t]*$//')
                if [[ "$trimmed" =~ ^[0-9]+$ ]]; then
                    idx=$((trimmed))
                    if ((idx >= 1 && idx <= ${#labels_array[@]})); then
                        selected_labels+=("${labels_array[idx-1]}")
                    else
                        echo "⚠️  Ignoring unknown label index: $trimmed"
                    fi
                elif [[ -n "$trimmed" ]]; then
                    selected_labels+=("$trimmed")
                fi
            done
        fi
    fi
else
    echo "ℹ️  No labels found or unable to fetch labels."
fi

# --- Assemble gh issue create command ---
declare -a gh_args=(
    --title "$issue_title"
    --body "$issue_body"
)

gh_args+=(--assignee "@me")

for label in "${selected_labels[@]}"; do
    gh_args+=(--label "$label")
done

echo "------------------------------"
echo "Creating issue with:"
echo "Title: $issue_title"
if [[ -n "$issue_body" ]]; then
    echo "Body: (provided)"
else
    echo "Body: (none)"
fi
if ((${#selected_labels[@]} > 0)); then
    labels_joined=$(printf "%s, " "${selected_labels[@]}")
    labels_joined=${labels_joined%, }
    echo "Labels: ${labels_joined}"
else
    echo "Labels: (none)"
fi
echo "------------------------------"

if ! issue_response=$(gh issue create "${gh_args[@]}" 2>&1); then
    echo "❌ Failed to create issue."
    echo "$issue_response"
    exit 1
fi

issue_url=$(echo "$issue_response" | awk 'NF' | tail -n1)
if [[ "$issue_url" =~ /issues/([0-9]+) ]]; then
    issue_number="${BASH_REMATCH[1]}"
else
    issue_number="?"
fi

echo "✅ Issue #${issue_number} created: ${issue_url}"

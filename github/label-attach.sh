#!/usr/bin/env bash
#
# label-attach.sh: Add labels to an existing GitHub issue or pull request.

set -euo pipefail

require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        echo "❌ Required command '$cmd' is not installed."
        exit 1
    fi
}

require_cmd gh
require_cmd jq

repo_name=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)
if [[ -n "$repo_name" ]]; then
    echo "📦 Current repository: $repo_name"
else
    echo "⚠️  Unable to detect the current repository; using gh default context."
fi

if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    echo "⚠️  Not inside a git repository. gh will use your default repo context."
fi

read -erp "Apply labels to an issue or pull request? ([i]ssue/[p]r) [i]: " target_choice
target_choice=$(echo "${target_choice:-i}" | tr '[:upper:]' '[:lower:]')
if [[ "$target_choice" == "p" || "$target_choice" == "pr" ]]; then
    target_type="pr"
    echo "ℹ️  Targeting open pull requests."
else
    target_type="issue"
    echo "ℹ️  Targeting open issues."
fi

if [[ "$target_type" == "issue" ]]; then
    items_json=$(gh issue list --state open --limit 50 --json number,title,url 2>/dev/null || true)
else
    items_json=$(gh pr list --state open --limit 50 --json number,title,url 2>/dev/null || true)
fi

item_count=$(echo "$items_json" | jq 'length' 2>/dev/null || echo "0")
if [[ "$item_count" -eq 0 ]]; then
    echo "❌ No open ${target_type}s found (or failed to fetch)."
    exit 1
fi

mapfile -t item_lines < <(echo "$items_json" | jq -r '.[] | "#\(.number): \(.title)"')
mapfile -t item_numbers < <(echo "$items_json" | jq -r '.[].number')

selected_line=""
if command -v fzf &>/dev/null; then
    echo "Tip: type to filter, ↑/↓ to move, Enter to pick."
    selected_line=$(printf "%s\n" "${item_lines[@]}" | fzf --prompt="Select ${target_type}: " --height=100% --border || true)
fi

if [[ -z "$selected_line" ]]; then
    echo "Open ${target_type}s:"
    for i in "${!item_lines[@]}"; do
        printf "%2d. %s\n" $((i + 1)) "${item_lines[$i]}"
    done
    read -erp "Choose by list index or type a ${target_type} number: " manual_choice
    manual_choice=$(echo "$manual_choice" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    if [[ -z "$manual_choice" ]]; then
        echo "❌ Selection cannot be blank."
        exit 1
    fi
    if [[ "$manual_choice" =~ ^[0-9]+$ ]]; then
        idx=$((manual_choice))
        if ((idx >= 1 && idx <= ${#item_numbers[@]})); then
            selected_line="${item_lines[idx-1]}"
        else
            # Assume the user typed an explicit issue/PR number.
            selected_line="#${manual_choice}: (entered manually)"
        fi
    else
        echo "❌ Invalid selection."
        exit 1
    fi
fi

target_number=$(echo "$selected_line" | sed -n 's/^#\([0-9]\+\).*/\1/p')
if [[ -z "$target_number" ]]; then
    echo "❌ Unable to parse selection."
    exit 1
fi

target_url=$(echo "$items_json" | jq -r --arg num "$target_number" '.[] | select((.number|tostring) == $num) | .url' | head -n1)

declare -a labels_available=()
mapfile -t labels_available < <(gh label list --json name --jq '.[].name' 2>/dev/null || true)

declare -a selected_labels=()
if ((${#labels_available[@]} > 0)); then
    if command -v fzf &>/dev/null; then
        echo "Select labels to add (space to toggle, enter to confirm). Type to filter."
        label_selection=$(printf "%s\n" "${labels_available[@]}" | fzf --multi --bind "space:toggle" --prompt="Labels: " --height=100% --border || true)
        while IFS= read -r label; do
            [[ -n "$label" ]] && selected_labels+=("$label")
        done <<<"$label_selection"
    else
        echo "Available labels:"
        for i in "${!labels_available[@]}"; do
            printf "%2d. %s\n" $((i + 1)) "${labels_available[$i]}"
        done
        read -erp "Enter label numbers or names separated by commas: " label_input
        IFS=',' read -r -a label_tokens <<<"$label_input"
        for token in "${label_tokens[@]}"; do
            trimmed=$(echo "$token" | sed -e 's/^[ \t]*//' -e 's/[ \t]*$//')
            if [[ -z "$trimmed" ]]; then
                continue
            elif [[ "$trimmed" =~ ^[0-9]+$ ]]; then
                idx=$((trimmed))
                if ((idx >= 1 && idx <= ${#labels_available[@]})); then
                    selected_labels+=("${labels_available[idx-1]}")
                else
                    echo "⚠️  Ignoring unknown label index: $trimmed"
                fi
            else
                selected_labels+=("$trimmed")
            fi
        done
    fi
else
    echo "ℹ️  No labels found. You can still type label names to add."
    read -erp "Enter label names separated by commas: " label_input
    IFS=',' read -r -a label_tokens <<<"$label_input"
    for token in "${label_tokens[@]}"; do
        trimmed=$(echo "$token" | sed -e 's/^[ \t]*//' -e 's/[ \t]*$//')
        [[ -n "$trimmed" ]] && selected_labels+=("$trimmed")
    done
fi

# Deduplicate labels while preserving order.
declare -A seen_labels=()
declare -a unique_labels=()
for label in "${selected_labels[@]}"; do
    if [[ -n "$label" && -z "${seen_labels[$label]:-}" ]]; then
        unique_labels+=("$label")
        seen_labels[$label]=1
    fi
done
selected_labels=("${unique_labels[@]}")

if ((${#selected_labels[@]} == 0)); then
    echo "❌ No labels selected. Nothing to do."
    exit 1
fi

echo "------------------------------"
echo "Applying labels to #${target_number} (${target_type})"
if [[ -n "$target_url" ]]; then
    echo "URL: $target_url"
fi
echo "Labels: $(printf "%s, " "${selected_labels[@]}" | sed 's/, $//')"
echo "------------------------------"

declare -a gh_cmd
if [[ "$target_type" == "issue" ]]; then
    gh_cmd=(gh issue edit "$target_number")
else
    gh_cmd=(gh pr edit "$target_number")
fi
for label in "${selected_labels[@]}"; do
    gh_cmd+=(--add-label "$label")
done

if "${gh_cmd[@]}"; then
    echo "✅ Added labels to #${target_number}."
else
    echo "❌ Failed to update labels."
    exit 1
fi

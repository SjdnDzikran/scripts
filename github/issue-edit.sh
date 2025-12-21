#!/usr/bin/env bash
#
# issue-edit.sh: Helper to edit GitHub issues from the terminal.

set -euo pipefail

require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        echo "Required command '$cmd' is not installed."
        exit 1
    fi
}

# --- Pre-flight checks ---
require_cmd gh
require_cmd jq

if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    echo "Warning: Not inside a Git repository. gh will use your default repo context."
fi

echo "Ready to edit a GitHub issue."
echo "------------------------------"

# --- Select issue ---
issue_number=""
issues_json=$(gh issue list --state all --json number,title,state -L 200 2>/dev/null || echo "[]")
issue_count=$(echo "$issues_json" | jq 'length')

if ((issue_count > 0)) && command -v fzf &>/dev/null; then
    issue_line=$(
        echo "$issues_json" |
            jq -r '.[] | "#\(.number)\t[\(.state)]\t\(.title)"' |
            fzf --prompt="Issue: " --height=100% --border || true
    )
    if [[ -n "$issue_line" ]]; then
        issue_number=$(echo "$issue_line" | awk -F'\t' '{print $1}' | tr -d '#')
    fi
fi

if [[ -z "$issue_number" ]]; then
    read -erp "Issue number to edit: " issue_number
fi

if [[ -z "$issue_number" ]]; then
    echo "No issue selected."
    exit 1
fi

# --- Load current issue data ---
issue_json=$(gh issue view "$issue_number" --json title,body,labels,state,url 2>/dev/null) || {
    echo "Failed to load issue #${issue_number}."
    exit 1
}

current_title=$(echo "$issue_json" | jq -r '.title // ""')
current_body=$(echo "$issue_json" | jq -r '.body // ""')
current_state=$(echo "$issue_json" | jq -r '.state // ""')
issue_url=$(echo "$issue_json" | jq -r '.url // ""')

mapfile -t current_labels < <(echo "$issue_json" | jq -r '.labels[].name' 2>/dev/null || true)

echo "Editing: #${issue_number} ${issue_url}"
echo "Current title: ${current_title}"
echo "Current state: ${current_state}"
if ((${#current_labels[@]} > 0)); then
    current_labels_joined=$(printf "%s, " "${current_labels[@]}")
    current_labels_joined=${current_labels_joined%, }
    echo "Current labels: ${current_labels_joined}"
else
    echo "Current labels: (none)"
fi
echo "------------------------------"

# --- Gather updates ---
read -erp "New title (leave blank to keep current): " -i "$current_title" new_title

new_body="$current_body"
if [[ -n "${EDITOR:-}" ]]; then
    read -rp "Edit body in \$EDITOR? (y/N): " edit_body
    if [[ "$edit_body" =~ ^[Yy]$ ]]; then
        body_file=$(mktemp)
        printf "%s" "$current_body" >"$body_file"
        "$EDITOR" "$body_file"
        new_body=$(cat "$body_file")
        rm -f "$body_file"
    else
        read -erp "New body (leave blank to keep current): " -i "$current_body" body_input
        if [[ -n "$body_input" ]]; then
            new_body="$body_input"
        fi
    fi
else
    read -erp "New body (leave blank to keep current): " -i "$current_body" body_input
    if [[ -n "$body_input" ]]; then
        new_body="$body_input"
    fi
fi

update_labels="n"
read -rp "Update labels? (y/N): " update_labels

selected_labels=()
if [[ "$update_labels" =~ ^[Yy]$ ]]; then
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
            read -rp "Enter label numbers or names separated by commas (leave blank for none): " label_input
            if [[ -n "$label_input" ]]; then
                IFS=',' read -r -a label_tokens <<<"$label_input"
                for token in "${label_tokens[@]}"; do
                    trimmed=$(echo "$token" | sed -e 's/^[ \t]*//' -e 's/[ \t]*$//')
                    if [[ "$trimmed" =~ ^[0-9]+$ ]]; then
                        idx=$((trimmed))
                        if ((idx >= 1 && idx <= ${#labels_array[@]})); then
                            selected_labels+=("${labels_array[idx-1]}")
                        else
                            echo "Ignoring unknown label index: $trimmed"
                        fi
                    elif [[ -n "$trimmed" ]]; then
                        selected_labels+=("$trimmed")
                    fi
                done
            fi
        fi
    else
        echo "No labels found or unable to fetch labels."
    fi
else
    selected_labels=("${current_labels[@]}")
fi

read -rp "Change state (open/closed/leave blank to keep current): " new_state
new_state=$(echo "$new_state" | tr '[:upper:]' '[:lower:]')
if [[ -z "$new_state" ]]; then
    new_state="$current_state"
fi

# --- Assemble gh issue edit command ---
declare -a gh_args=()
changes=0

if [[ "$new_title" != "$current_title" ]]; then
    gh_args+=(--title "$new_title")
    changes=1
fi

if [[ "$new_body" != "$current_body" ]]; then
    gh_args+=(--body "$new_body")
    changes=1
fi

if [[ "$new_state" != "$current_state" ]]; then
    if [[ "$new_state" == "open" || "$new_state" == "closed" ]]; then
        gh_args+=(--state "$new_state")
        changes=1
    else
        echo "Invalid state: ${new_state}. Keeping current state."
    fi
fi

if [[ "$update_labels" =~ ^[Yy]$ ]]; then
    declare -A current_label_map=()
    declare -A new_label_map=()
    for label in "${current_labels[@]}"; do
        current_label_map["$label"]=1
    done
    for label in "${selected_labels[@]}"; do
        new_label_map["$label"]=1
    done

    for label in "${selected_labels[@]}"; do
        if [[ -z "${current_label_map[$label]:-}" ]]; then
            gh_args+=(--add-label "$label")
            changes=1
        fi
    done

    for label in "${current_labels[@]}"; do
        if [[ -z "${new_label_map[$label]:-}" ]]; then
            gh_args+=(--remove-label "$label")
            changes=1
        fi
    done
fi

if [[ "$changes" -eq 0 ]]; then
    echo "No changes requested. Exiting."
    exit 0
fi

echo "------------------------------"
echo "Updating issue #${issue_number}..."
if ! gh issue edit "$issue_number" "${gh_args[@]}" 2>&1; then
    echo "Failed to update issue #${issue_number}."
    exit 1
fi

echo "Issue #${issue_number} updated successfully."

#!/usr/bin/env bash
#
# label-buddy.sh: Interactive helper for creating or updating GitHub labels.

set -euo pipefail

require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        echo "❌ Required command '$cmd' is not installed."
        exit 1
    fi
}

require_cmd gh

declare -a famous_colors=(
    "Ferrari Red:#ff2800"
    "Tiffany Blue:#0abab5"
    "British Racing Green:#004225"
    "International Klein Blue:#002fa7"
    "Harley-Davidson Orange:#ff6600"
    "Royal Purple:#7851a9"
    "Canary Yellow:#ffef00"
    "Midnight Blue:#191970"
)
rand_index=$((RANDOM % ${#famous_colors[@]}))
IFS=":" read -r random_color_name random_color_hex <<<"${famous_colors[$rand_index]}"

repo_name=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)
if [[ -n "$repo_name" ]]; then
    echo "🏷  Current repository: $repo_name"
else
    echo "⚠️  Unable to detect the current repository; using gh default context."
fi

echo "🎨 Suggested color: ${random_color_name} (${random_color_hex})"

read -rp "Label name: " label_name
label_name=$(echo "$label_name" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
if [[ -z "$label_name" ]]; then
    echo "❌ Label name cannot be blank."
    exit 1
fi

read -rp "Label color hex (press Enter to use ${random_color_name} ${random_color_hex}): " label_color
label_color=${label_color:-$random_color_hex}
label_color=${label_color#"#"}
if [[ ! "$label_color" =~ ^[0-9A-Fa-f]{6}$ ]]; then
    echo "❌ Color must be a 6-digit hexadecimal value (e.g., ffffff)."
    exit 1
fi

read -rp "Label description (optional): " label_description

declare -a gh_args=(
    --color "$label_color"
)
if [[ -n "$label_description" ]]; then
    gh_args+=(--description "$label_description")
fi

if gh label view "$label_name" &>/dev/null; then
    echo "ℹ️  Label '$label_name' already exists."
    read -rp "Update existing label with new color/description? (y/N): " update_choice
    if [[ ! "$update_choice" =~ ^[Yy]$ ]]; then
        echo "❌ Label already exists; aborting."
        exit 1
    fi
    if gh label edit "$label_name" "${gh_args[@]}"; then
        echo "✅ Label '$label_name' updated."
    else
        echo "❌ Failed to update label."
        exit 1
    fi
else
    if gh label create "$label_name" "${gh_args[@]}"; then
        echo "✅ Label '$label_name' created."
    else
        echo "❌ Failed to create label."
        exit 1
    fi
fi

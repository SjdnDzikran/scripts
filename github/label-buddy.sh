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

rand_between() {
    local min="$1"
    local max="$2"
    echo $((min + RANDOM % (max - min + 1)))
}

hsl_to_hex() {
    local h="$1"
    local s="$2"
    local l="$3"
    awk -v h="$h" -v s="$s" -v l="$l" '
    function abs(x) { return x < 0 ? -x : x }
    BEGIN {
        s = s / 100.0
        l = l / 100.0
        c = (1 - abs(2 * l - 1)) * s
        h_ = h / 60.0
        x = c * (1 - abs((h_ % 2) - 1))
        if (h_ >= 0 && h_ < 1) { r1 = c; g1 = x; b1 = 0 }
        else if (h_ >= 1 && h_ < 2) { r1 = x; g1 = c; b1 = 0 }
        else if (h_ >= 2 && h_ < 3) { r1 = 0; g1 = c; b1 = x }
        else if (h_ >= 3 && h_ < 4) { r1 = 0; g1 = x; b1 = c }
        else if (h_ >= 4 && h_ < 5) { r1 = x; g1 = 0; b1 = c }
        else { r1 = c; g1 = 0; b1 = x }
        m = l - (c / 2)
        r = int((r1 + m) * 255 + 0.5)
        g = int((g1 + m) * 255 + 0.5)
        b = int((b1 + m) * 255 + 0.5)
        if (r < 0) r = 0; if (r > 255) r = 255
        if (g < 0) g = 0; if (g > 255) g = 255
        if (b < 0) b = 0; if (b > 255) b = 255
        printf("%02x%02x%02x", r, g, b)
    }'
}

random_color_hex=""
random_color_name=""
if ((RANDOM % 2 == 0)); then
    random_color_name="Pastel"
    h=$(rand_between 0 359)
    s=$(rand_between 35 65)
    l=$(rand_between 72 88)
    random_color_hex=$(hsl_to_hex "$h" "$s" "$l")
else
    random_color_name="Neon"
    h=$(rand_between 0 359)
    s=$(rand_between 80 100)
    l=$(rand_between 45 60)
    random_color_hex=$(hsl_to_hex "$h" "$s" "$l")
fi

repo_name=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)
if [[ -n "$repo_name" ]]; then
    echo "🏷  Current repository: $repo_name"
else
    echo "⚠️  Unable to detect the current repository; using gh default context."
fi

echo "🎨 Suggested color: ${random_color_name} (#${random_color_hex})"

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

#!/usr/bin/env bash
#
# list-issues.sh: Display open GitHub issues with their labels.

set -euo pipefail

if ! command -v gh &>/dev/null; then
    echo "❌ Required command 'gh' (GitHub CLI) is not installed."
    exit 1
fi

if ! command -v jq &>/dev/null; then
    echo "❌ Required command 'jq' is not installed."
    exit 1
fi

issues_json=$(gh issue list --state open --json number,title,labels,url) || {
    echo "❌ Failed to fetch issues."
    exit 1
}

issue_count=$(echo "$issues_json" | jq 'length')
echo "✅ Found ${issue_count} open issue(s)."
echo "------------------------------"

echo "$issues_json" | jq -r '
  sort_by(.number) |
  .[] |
  "#\(.number): \(.title)
   URL: \(.url)
   Labels: " + (if (.labels | length) > 0 then (.labels | map(.name) | join(", ")) else "(none)" end) + "\n"
'

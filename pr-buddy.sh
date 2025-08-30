#!/usr/bin/env bash
#
# pr-buddy.sh: A script to generate a PR title and description using Gemini,
# with context from code diffs and linked GitHub issues.
# This version uses a JSON-structured prompt for more reliable parsing.

# --- Configuration ---
set -e
set -u
set -o pipefail

# --- Pre-flight Checks ---
# 1. Check for Gemini API Key
if [[ -z "${GEMINI_API_KEY:-}" ]]; then
    echo "Error: The GEMINI_API_KEY environment variable is not set."
    echo "Please get a key from Google AI Studio and set it:"
    echo "export GEMINI_API_KEY='your_api_key_here'"
    exit 1
fi

# 2. Check for required command-line tools
for cmd in git curl jq fzf; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: Required command '$cmd' is not installed."
        exit 1
    fi
done

# 3. Check if inside a Git repository
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    echo "Error: This script must be run from within a Git repository."
    exit 1
fi

echo "✅ Pre-flight checks passed."
echo "------------------------------"

# --- Step 1: Get branch names from the user ---
current_branch=$(git rev-parse --abbrev-ref HEAD)
default_branch=$(git remote show origin | awk '/HEAD branch/ {print $NF}')

read -p "Enter the source branch (from) [default: ${current_branch}]: " from_branch
from_branch=${from_branch:-$current_branch}

read -p "Enter the target branch (to) [default: ${default_branch}]: " to_branch
to_branch=${to_branch:-$default_branch}

echo "------------------------------"
echo "➡️  Comparing branches: ${from_branch} -> ${to_branch}"

# --- Step 2: Get the code diff ---
echo "🔄  Fetching latest changes and getting diff..."
git fetch origin "${to_branch}" --quiet
diff_output=$(git diff "origin/${to_branch}...${from_branch}")

if [[ -z "$diff_output" ]]; then
    echo "⚠️  No differences found between '${from_branch}' and 'origin/${to_branch}'."
    echo "There is nothing to create a PR for. Exiting."
    exit 0
fi

echo "✅  Found code differences."
echo "------------------------------"

# --- Step 3: Get the user's prompt and solved issues ---

# MODIFIED: Prompt now asks for a JSON object.
# Note the escaped single quotes \' for bash compatibility.
default_prompt=$'Based on the code diff and linked issues, generate a JSON object with a PR title and a technical PR description.

**Response Format Instructions:**

Your entire output must be a single, valid JSON object. Do not include any text, explanations, or markdown formatting outside of this JSON object.

The JSON object must have the following structure:
{
  "title": "string",
  "description": "string"
}

**Content Rules:**

1.  `title` (string):
    * Follow the Conventional Commit Format: `type(scope): subject`.
    * `type`: Must be one of `feat`, `fix`, `chore`, `refactor`, `style`, `ci`, `docs`.
    * `scope` (optional): A noun for the codebase section (e.g., `api`, `camera`, `ui`, `auth`, `build`).
    * `subject`: A short, imperative-mood summary of the change.
    * Example: "feat(camera): Add continuous torch mode"

2.  `description` (string):
    * This string must contain the full technical description formatted in Markdown.
    * Do not add any introductory sentences. Start directly with the first relevant category heading.
    * Group technical changes into the following categories using `###` (H3) headings. Only include categories with relevant changes.
        * `### ✨ New Functionality`
        * `### 🛠️ Refactoring & Architectural Changes`
        * `### 🐛 Bug Fixes`
        * `### ⚡ Performance Improvements`
        * `### 🧹 Maintenance & Chores`
    * Under each category, list changes as concise, technical bullet points.
    * For each bullet point that resolves a GitHub issue, append `Fixes #{issue_number}` or `Closes #{issue_number}` at the end of that bullet point\'s line.

---
GitHub Issues to close with this PR:'

# Using an editor for the prompt is a better user experience
# If you don't have $EDITOR set, it will use the default_prompt
user_prompt=${user_prompt:-$default_prompt}

# --- Step 3.1: Fetch GitHub issues and let the user select ---
echo "🔍 Fetching open issues from GitHub..."
repo_url=$(git config --get remote.origin.url | sed -E 's#(git@|https://)github.com[:/](.*)\.git#\2#')
issues_list=""
if command -v gh &>/dev/null; then
    issues_list=$(gh issue list --limit 50 --json number,title --jq '.[] | "#\(.number) | \(.title)"')
else
    # Fallback to curl if gh is not available
    issues_list=$(curl -s -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/${repo_url}/issues?state=open&per_page=50" |
        jq -r '.[] | "#\(.number) | \(.title)"')
fi

solved_issues=()
if [[ -z "$issues_list" ]]; then
    echo "⚠️  No open issues found."
else
    echo "✅  Select related issues (space to toggle, enter to confirm):"
    selected=$(echo "$issues_list" | fzf --multi --bind "space:toggle" --prompt="Select issues: ")

    # FIX: Use a robust `while read` loop to parse fzf output.
    # This correctly handles issue titles with special characters like single quotes,
    # which caused the `xargs: unmatched single quote` error.
    while IFS='|' read -r num_part title_part; do
        # Trim whitespace and the '#' from the number part
        issue_number=$(echo "$num_part" | sed -e 's/^[ \t]*#[ \t]*//' -e 's/[ \t]*$//')
        # Trim whitespace from the title part
        issue_title=$(echo "$title_part" | sed -e 's/^[ \t]*//' -e 's/[ \t]*$//')

        # Ensure we have valid data before adding to the array
        if [[ -n "$issue_number" && -n "$issue_title" ]]; then
            solved_issues+=("- ${issue_title} #${issue_number}")
        fi
    done <<< "$selected"
fi


# --- Step 4 & 5: Send to Gemini API and output response ---
echo "------------------------------"
echo "🤖  Sending prompt, issues, and diff to Gemini. Please wait..."

issues_text=""
if [ ${#solved_issues[@]} -gt 0 ]; then
    issues_text=$(printf "%s\n" "${solved_issues[@]}")
fi

full_prompt_text=$(
    cat <<EOF
${user_prompt}

${issues_text}

---
Here is the code diff to analyze:
\`\`\`diff
${diff_output}
\`\`\`
EOF
)

# MODIFIED: Tell the API we want a JSON response for better model adherence
tmpfile=$(mktemp)
printf '%s' "$full_prompt_text" > "$tmpfile"

json_payload=$(
    jq -n --rawfile text "$tmpfile" \
        '{ 
          contents: [ { parts: [ { text: $text } ] } ],
          generationConfig: { responseMimeType: "application/json" }
        }'
)
rm "$tmpfile"

# Using gemini-2.5-pro as it's fast and great for structured output
API_URL="https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-pro:generateContent?key=${GEMINI_API_KEY}"

payload_file=$(mktemp)
printf '%s' "$json_payload" > "$payload_file"

api_response=$(
    curl -s -H "Content-Type: application/json" -d @"$payload_file" "$API_URL"
)

rm "$payload_file"

if echo "$api_response" | jq -e '.error' >/dev/null; then
    echo "❌ Error received from Gemini API:"
    echo "$api_response" | jq .
    exit 1
fi

# MODIFIED: Extract the raw text which should be our JSON
generated_json=$(echo "$api_response" | jq -r '.candidates[0].content.parts[0].text')

# NEW: Validate if the output is valid JSON
if ! echo "$generated_json" | jq -e . >/dev/null 2>&1; then
    echo "❌ Error: Gemini did not return valid JSON."
    echo "This can happen on complex diffs. Try running it again."
    echo "Received:"
    echo "$generated_json"
    exit 1
fi

# MODIFIED: Extract title and body using jq. This is much more robust!
pr_title=$(echo "$generated_json" | jq -r '.title')
pr_body=$(echo "$generated_json" | jq -r '.description')

echo "------------------------------"
echo "✨ Here is the suggested PR:"
echo "------------------------------"
echo -e "\n--[ PR Title ]-------------"
echo "${pr_title}"
echo -e "\n--[ PR Body ]--------------"
echo "${pr_body}"
echo -e "\n---------------------------"


# --- Step 6: Automatically create PR (optional) ---
read -p "Do you want to create a GitHub PR with this? (Y/n): " create_pr
if [[ ! "${create_pr}" =~ ^[Nn]$ ]]; then
    if ! command -v gh &>/dev/null; then
        echo "Error: 'gh' command is not installed. Cannot create PR."
        echo "Please install the GitHub CLI: https://cli.github.com/"
        exit 1
    fi
    echo "📤 Creating PR: \"$pr_title\"..."
    # The variables are already clean and ready to use
    gh pr create --base "$to_branch" --head "$from_branch" --title "$pr_title" --body "$pr_body"
fi

echo "✅ Done."

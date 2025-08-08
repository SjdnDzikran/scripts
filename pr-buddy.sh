#!/usr/bin/env bash

# pr-buddy.sh: A script to generate a PR title and description using Gemini,
# with context from code diffs and linked GitHub issues.

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
for cmd in git curl jq; do
  if ! command -v "$cmd" &> /dev/null; then
    echo "Error: Required command '$cmd' is not installed."
    exit 1
  fi
done

# 3. Check if inside a Git repository
if ! git rev-parse --is-inside-work-tree &> /dev/null; then
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
git fetch origin "$to_branch" --quiet
diff_output=$(git diff "origin/${to_branch}...${from_branch}")

if [[ -z "$diff_output" ]]; then
  echo "⚠️  No differences found between '${from_branch}' and 'origin/${to_branch}'."
  echo "There is nothing to create a PR for. Exiting."
  exit 0
fi

echo "✅  Found code differences."
echo "------------------------------"


# --- Step 3: Get the user's prompt and solved issues ---

# Updated default prompt to ask the model to consider GitHub issues.
default_prompt=$'Based on the code diff, help me write a PR title and a purely technical description.\n\n**Instructions:**\n\n1.  **PR Title (Conventional Commit Format):**\n    *   **Format:** `type(scope): subject`\n    *   **`type`:** Choose from `feat`, `fix`, `chore`, `refactor`, `style`, `ci`, `docs`.\n    *   **`scope` (optional):** A noun for the codebase section (e.g., `api`, `camera`, `ui`, `auth`, `build`).\n    *   **`subject`:** A short, imperative-mood summary of the change.\n    *   **Example:** `feat(camera): Add continuous torch mode`\n\n2.  **PR Description (Technical Only):**\n    *   Write a description containing **only technical implementation details**.\n    *   The entire description must be formatted within a **single markdown code block**.\n\n---\n\n**Description Formatting Rules:**\n\n*   **No Introduction:** The description must start **directly** with the first relevant category heading. Do not add any introductory sentences.\n\n*   **Category Headings:** Group technical changes into the following categories using `##` (H2) headings. Only include categories that have relevant changes.\n    *   `### ✨ New Functionality`\n    *   `### 🛠️ Refactoring & Architectural Changes`\n    *   `### 🐛 Bug Fixes`\n    *   `### ⚡ Performance Improvements`\n    *   `### 🧹 Maintenance & Chores`\n\n*   **Technical Bullet Points:** Under each category, list the changes as concise, technical bullet points. Focus on the \"how\" and \"what\" of the code changes (e.g., \"Refactored `UserService` to use dependency injection,\" \"Replaced `Promise.all` with `for...of` loop to handle rate limiting\").\n\n*   **Issue Linking:** For each bullet point that resolves a GitHub issue, append `Fixes #{issue_number}` or `Closes #{issue_number}` at the **end of that specific bullet point\'s line.**\n\n---\n\n**GitHub Issues to close with this PR:**'

echo "Enter your prompt for Gemini. Press Enter to use the default:"
echo -e "\nDefault Prompt:\n\"${default_prompt}\"\n"
read -p "> " user_prompt
user_prompt=${user_prompt:-$default_prompt}

# --- Step 3.1: Fetch GitHub issues and let the user select ---
echo "---"
echo "🔍 Fetching open issues from GitHub..."

# Ensure gh or curl + jq are available
if command -v gh &>/dev/null; then
    issues_list=$(gh issue list --limit 50 --json number,title --jq '.[] | "\(.number) | \(.title)"')
else
    repo_url=$(git config --get remote.origin.url | sed -E 's#(git@|https://)github.com[:/]##; s/.git$//')
    issues_list=$(curl -s "https://api.github.com/repos/${repo_url}/issues?state=open&per_page=50" \
        | jq -r '.[] | "\(.number) | \(.title)"')
fi

if [[ -z "$issues_list" ]]; then
    echo "⚠️  No open issues found."
    solved_issues=()
else
    echo "✅ Select related issues (space to toggle, enter to confirm):"
    selected=$(echo "$issues_list" | fzf --multi --bind "space:toggle" --prompt="Select issues: ")
    
    solved_issues=()
    while IFS= read -r line; do
        issue_number=$(echo "$line" | awk '{print $1}')
        issue_title=$(echo "$line" | cut -d'|' -f2- | sed 's/^ *//')
        solved_issues+=("${issue_title} #${issue_number}")
    done <<< "$selected"
fi



# --- Step 4 & 5: Send to Gemini API and output response ---

echo "------------------------------"
echo "🤖  Sending prompt, issues, and diff to Gemini. Please wait..."

### NEW ###
# Prepare the issues text block, only if issues were provided.
issues_text=""
if [[ ${#solved_issues[@]} -gt 0 ]]; then
    issues_text+="This PR resolves the following GitHub issues:\n"
    for issue in "${solved_issues[@]}"; do
        issues_text+="* ${issue}\n"
    done
fi

### MODIFIED ###
# We combine the user's prompt, the issues, and the git diff into a single payload.
# The new 'issues_text' variable is now included.
full_prompt_text=$(cat <<EOF
${user_prompt}

${issues_text}
Here is the code diff to analyze:
\`\`\`diff
${diff_output}
\`\`\`
EOF
)

json_payload=$(jq -n --arg text "$full_prompt_text" \
'{
  "contents": [{
    "parts": [{
      "text": $text
    }]
  }]
}')

### MODIFIED ###
# The API URL now points to the gemini-1.5-pro model.
# This model is more powerful but may have slightly higher latency and cost.
API_URL="https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-pro:generateContent?key=${GEMINI_API_KEY}"

api_response=$(curl -s -H "Content-Type: application/json" -d "$json_payload" "$API_URL")

if echo "$api_response" | jq -e '.error' > /dev/null; then
    echo "❌ Error received from Gemini API:"
    echo "$api_response" | jq .
    exit 1
fi

generated_text=$(echo "$api_response" | jq -r '.candidates[0].content.parts[0].text')

echo "------------------------------"
echo "✨ Here is the suggested PR Title and Description:"
echo "------------------------------"
echo "$generated_text"
echo "------------------------------"

# --- Step 6: Automatically create PR (optional) ---
read -p "Do you want to create a GitHub PR with this? (y/N): " create_pr
if [[ "$create_pr" =~ ^[Yy]$ ]]; then
    # Extract PR title
    pr_title=$(echo "$generated_text" | sed -n '/\*\*PR Title:/,/PR Description:/p' \
        | grep -E '^`.*`$' \
        | sed 's/^`//;s/`$//')

    # Extract PR body (everything after "PR Description:")
    pr_body=$(echo "$ai_response" | sed -n '/^```markdown$/,/^```$/p' | sed '1d;$d')

    echo "📤 Creating PR: \"$pr_title\"..."
    gh pr create --base "$to_branch" --head "$from_branch" --title "$pr_title" --body "$pr_body"
fi

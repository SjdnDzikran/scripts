#!/usr/bin/env python3
"""
pr_buddy.py: A script to generate a PR title and description using Gemini,
with context from code diffs and linked GitHub issues.
"""

import os
import sys
import subprocess
import json
import shutil
from typing import List, Dict, Any

import requests

# --- Configuration ---
REQUIRED_CMDS = ["git", "curl", "jq", "fzf"]
API_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-pro:generateContent"


# --- Helpers ---
def run(cmd, capture=True, check=True, text=True):
    return subprocess.run(
        cmd,
        shell=True,
        capture_output=capture,
        text=text,
        check=check,
    ).stdout.strip() if capture else subprocess.run(cmd, shell=True, check=check)


def error(msg):
    print(f"❌ {msg}", file=sys.stderr)
    sys.exit(1)


def confirm(prompt, default="y"):
    ans = input(f"{prompt} (Y/n): ").strip().lower()
    if not ans:
        ans = default
    return ans not in ["n", "no"]


# --- Pre-flight Checks ---
api_key = os.getenv("GEMINI_API_KEY")
if not api_key:
    error("The GEMINI_API_KEY environment variable is not set. Please run:\nexport GEMINI_API_KEY='your_api_key_here'")

for cmd in REQUIRED_CMDS:
    if not shutil.which(cmd):
        error(f"Required command '{cmd}' is not installed.")

try:
    run("git rev-parse --is-inside-work-tree")
except subprocess.CalledProcessError:
    error("This script must be run from within a Git repository.")

print("✅ Pre-flight checks passed.\n------------------------------")


# --- Step 1: Branches ---
current_branch = run("git rev-parse --abbrev-ref HEAD")
default_branch = run("git remote show origin | awk '/HEAD branch/ {print $NF}'")

from_branch = input(f"Enter the source branch (from) [default: {current_branch}]: ").strip() or current_branch
to_branch = input(f"Enter the target branch (to) [default: {default_branch}]: ").strip() or default_branch

print(f"➡️  Comparing branches: {from_branch} -> {to_branch}")


# --- Step 2: Get the code diff ---
print("🔄 Fetching latest changes and getting diff...")
run(f"git fetch origin {to_branch} --quiet", capture=False)
diff_output = run(f"git diff origin/{to_branch}...{from_branch}")

if not diff_output:
    print(f"⚠️  No differences found between '{from_branch}' and 'origin/{to_branch}'. Exiting.")
    sys.exit(0)

print("✅ Found code differences.\n------------------------------")


# --- Step 3: Prompts ---
experimental_prompt = r"""Based on the code diff and linked issues, generate a JSON object with a PR title and a technical PR description.

**Response Format Instructions:**

Your entire output must be a single, valid JSON object. Do not include any text, explanations, or markdown formatting outside of this JSON object.

The JSON object must have the following structure:
{
  "title": "string",
  "description": "string"
}

**Content Rules:**

1.  `title` (string):
    *   Follow the Conventional Commit Format: `type(scope): subject`.
    *   `type`: Must be one of `feat`, `fix`, `chore`, `refactor`, `style`, `ci`, `docs`.
    *   `scope` (optional): A noun for the codebase section (e.g., `api`, `camera`, `ui`, `auth`, `build`).
    *   `subject`: A short, imperative-mood summary of the change.
    *   Example: "feat(camera): Add continuous torch mode"

2.  `description` (string):
    *   This string must contain the full technical description formatted in Markdown.
    *   Do not add any introductory sentences. Start directly with the first relevant category heading.
    *   Group technical changes into the following categories using `###` (H3) headings. Only include categories with relevant changes.
        * `### ✨ New Functionality`
        * `### 🛠️ Refactoring & Architectural Changes`
        * `### 🐛 Bug Fixes`
        * `### ⚡ Performance Improvements`
        * `### 🧹 Maintenance & Chores`
    *   Under each category, list each major change using the following nested structure:
        *   Start with a primary bullet point (`*`). The line must begin with a **bolded, descriptive title** that summarizes the change, followed by a colon.
        *   Immediately after the colon, write a detailed paragraph explaining the change, its impact, and the technical reasoning.
        *   On a new line, add a nested and **bolded** bullet point that contains only the issue reference. Each issue must be on its own line.
"""

default_prompt = r"""Based on the code diff and linked issues, generate a JSON object with a PR title and a technical PR description.

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
    * For each bullet point that resolves a GitHub issue, append `Fixes #{issue_number}` or `Closes #{issue_number}` at the end of that bullet point's line.
"""

use_experimental = input("Do you want to use the experimental prompt? (Y/n): ").strip().lower()
user_prompt = experimental_prompt if use_experimental not in ["n", "no"] else default_prompt


# --- Step 3.1: Issues ---
print("🔍 Fetching open issues from GitHub...")
repo_url = run("git config --get remote.origin.url")
repo_slug = repo_url.replace("git@github.com:", "").replace("https://github.com/", "").replace(".git", "")

issues_json: List[Dict[str, Any]] = []
issues_list = ""
if shutil.which("gh"):
    gh_output = run("gh issue list --limit 50 --json number,title,labels")
    if gh_output:
        try:
            issues_json = json.loads(gh_output)
        except json.JSONDecodeError as exc:
            error(f"Unable to parse GitHub CLI issue output: {exc}")
else:
    resp = requests.get(
        f"https://api.github.com/repos/{repo_slug}/issues?state=open&per_page=50",
        headers={"Accept": "application/vnd.github.v3+json"},
    )
    if resp.ok:
        issues_json = resp.json()

if issues_json:
    issues_list = "\n".join([f"#{issue['number']} | {issue['title']}" for issue in issues_json])

solved_issues = []
pr_labels: List[str] = []
label_seen = set()
if not issues_list.strip():
    print("⚠️  No open issues found.")
else:
    print("✅ Select related issues (space to toggle, enter to confirm):")
    fzf_proc = subprocess.run(
        "fzf --multi --bind 'space:toggle' --prompt='Select issues: '",
        input=issues_list,
        text=True,
        capture_output=True,
        shell=True,
    )

    selected_lines = []
    if fzf_proc.returncode == 0 and fzf_proc.stdout:
        selected_lines = [line for line in fzf_proc.stdout.splitlines() if line.strip()]

    for line in selected_lines:
        if "|" in line:
            num_part, title_part = line.split("|", 1)
            issue_number = num_part.strip().lstrip("#")
            issue_title = title_part.strip()
            if issue_number and issue_title:
                solved_issues.append(f"- {issue_title} #{issue_number}")

                try:
                    issue_num_int = int(issue_number)
                except ValueError:
                    continue

                issue_data = next((item for item in issues_json if item.get("number") == issue_num_int), None)
                if not issue_data:
                    continue

                for label in issue_data.get("labels", []):
                    label_name = label.get("name") if isinstance(label, dict) else label
                    if label_name and label_name not in label_seen:
                        label_seen.add(label_name)
                        pr_labels.append(label_name)


# --- Step 4: Send to Gemini ---
print("------------------------------")
print("🤖 Sending prompt, issues, and diff to Gemini...")

issues_text = "\n".join(solved_issues) if solved_issues else ""
full_prompt_text = f"""{user_prompt}

{issues_text}

---
Here is the code diff to analyze:
```diff
{diff_output}
```"""

payload = {
    "contents": [{"parts": [{"text": full_prompt_text}]}],
    "generationConfig": {"responseMimeType": "application/json"},
}

resp = requests.post(f"{API_URL}?key={api_key}", json=payload)
if not resp.ok:
    error(f"Error from Gemini API: {resp.text}")

data = resp.json()
try:
    generated_json = data["candidates"][0]["content"]["parts"][0]["text"]
    parsed = json.loads(generated_json)
except Exception as e:
    error(f"Gemini did not return valid JSON. Got:\n{data}\nError: {e}")

pr_title = parsed.get("title", "")
pr_body = parsed.get("description", "")

print("------------------------------")
print("✨ Here is the suggested PR:")
print("------------------------------")
print(f"\n--[ PR Title ]-------------\n{pr_title}")
print(f"\n--[ PR Body ]--------------\n{pr_body}")
print("\n---------------------------")


# --- Step 6: Optional PR creation ---
if confirm("Do you want to create a GitHub PR with this?"):
    if not shutil.which("gh"):
        error("'gh' CLI is not installed. Cannot create PR.")
    print(f"📤 Creating PR: \"{pr_title}\"...")
    assignee = run("gh api user --jq '.login'")

    gh_pr_args: List[str] = [
        "gh",
        "pr",
        "create",
        "--base",
        to_branch,
        "--head",
        from_branch,
        "--title",
        pr_title,
        "--body",
        pr_body,
        "--assignee",
        assignee,
    ]

    if pr_labels:
        print(f"🏷️  Applying labels: {', '.join(pr_labels)}")
        for label in pr_labels:
            gh_pr_args.extend(["--label", label])

    subprocess.run(gh_pr_args, check=True)

print("✅ Done.")

# GitHub Workflow Scripts

[![License](https://img.shields.io/github/license/SjdnDzikran/scripts)](LICENSE)
[![Open Issues](https://img.shields.io/github/issues/SjdnDzikran/scripts)](https://github.com/SjdnDzikran/scripts/issues)
[![Open PRs](https://img.shields.io/github/issues-pr/SjdnDzikran/scripts)](https://github.com/SjdnDzikran/scripts/pulls)
[![Last Commit](https://img.shields.io/github/last-commit/SjdnDzikran/scripts/master)](https://github.com/SjdnDzikran/scripts/commits/master)
[![Shell](https://img.shields.io/badge/shell-bash-4EAA25.svg)](https://www.gnu.org/software/bash/)

A small toolkit of Bash helpers that streamline GitHub workflows: generating PR descriptions with AI, creating issues, and managing labels from the terminal.

Scripts: [PR Buddy](#pr-buddy) · [Issue Buddy](#issue-buddy) · [Label Buddy](#label-buddy) · [Label Attach](#label-attach) · [List Issues](#list-issues)

## Common Requirements

- `gh` (GitHub CLI) authenticated (`gh auth login`)
- `jq` and `fzf` for interactive selection (optional fallback paths exist)
- A git repo with an `origin` remote for PR-related scripts
- Additional per-script needs are called out below.

## PR Buddy

`pr-buddy.sh` prepares high-quality pull request titles and descriptions using Gemini, grounded in your git diff and linked issues. It can also open the PR with branches, labels, and assignee set.

**Extra requirements**
- Google Gemini API key with access to `gemini-2.5-pro` (`export GEMINI_API_KEY=...`)
- `git`, `curl`, `jq`, `fzf`, `gh`

**Quick start**
1) Commit or stage changes on your feature branch.  
2) Run `./pr-buddy.sh` and pick source/target branches.  
3) Select issues to close; the script pulls their labels automatically.  
4) Review the generated title and description, then let it create/update the PR via `gh pr create`.

## Issue Buddy

`issue-buddy.sh` creates a GitHub issue from the terminal with optional body and label selection (multi-select via `fzf` or numeric entry fallback).

**Run it:** `./issue-buddy.sh`

## Label Buddy

`label-buddy.sh` creates or updates a label in the current repo. It suggests a random famous color, lets you override it, and supports an optional description.

**Run it:** `./label-buddy.sh`

## Label Attach

`label-attach.sh` adds labels to an existing open issue or PR. Pick the target with `fzf` (or by number), then multi-select labels in the same styled picker.

**Run it:** `./label-attach.sh`

## List Issues

`list-issues.sh` prints open issues with their numbers, titles, URLs, and labels.

**Run it:** `./list-issues.sh`

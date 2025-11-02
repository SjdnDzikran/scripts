# PR Buddy

[![License](https://img.shields.io/github/license/SjdnDzikran/scripts)](LICENSE)
[![Open Issues](https://img.shields.io/github/issues/SjdnDzikran/scripts)](https://github.com/SjdnDzikran/scripts/issues)
[![Open PRs](https://img.shields.io/github/issues-pr/SjdnDzikran/scripts)](https://github.com/SjdnDzikran/scripts/pulls)
[![Last Commit](https://img.shields.io/github/last-commit/SjdnDzikran/scripts/master)](https://github.com/SjdnDzikran/scripts/commits/master)
[![Shell](https://img.shields.io/badge/shell-bash-4EAA25.svg)](https://www.gnu.org/software/bash/)

A command-line helper that prepares high-quality pull request titles and descriptions using Gemini, grounded in your git diff and the GitHub issues you link. After previewing the generated content, PR Buddy can open the PR in GitHub with the right branches, assignee, and label set inherited from the referenced issues.

## Requirements

- Google Gemini API key with access to `gemini-2.5-pro`
- Git repository with a configured `origin` remote
- CLI tools:
  - `git`, `curl`, `jq`, `fzf`
  - `gh` (GitHub CLI) for creating the PR and fetching issues with labels

## Setup

1. **Download the script**
   ```bash
   curl -o ~/bin/pr-buddy.sh https://raw.githubusercontent.com/<your-repo>/pr-buddy.sh
   chmod +x ~/bin/pr-buddy.sh
   ```

2. **Install required tools**
   ```bash
   # macOS (Homebrew)
   brew install git curl jq fzf gh

   # Debian / Ubuntu
   sudo apt update
   sudo apt install git curl jq fzf gh
   ```

3. **Configure the Gemini API key**
   Edit your shell profile (`~/.zshrc` or `~/.bashrc`) and add:
   ```bash
   export GEMINI_API_KEY="your_gemini_api_key"
   ```
   Reload the profile or start a new terminal session to pick up the change.

4. **Authenticate the GitHub CLI**
   ```bash
   gh auth login
   ```
   Follow the prompts to sign in with the account that owns the repository.

5. **Create a convenient alias**
   Append this line to your shell profile so you can run the script from any directory:
   ```bash
   alias pr-buddy="~/bin/pr-buddy.sh"
   ```
   Reload your profile:
   ```bash
   source ~/.zshrc   # or: source ~/.bashrc
   ```

## Usage

1. Commit or stage your changes as usual, then switch to the feature branch you want to merge.
2. Run `pr-buddy` and follow the prompts to pick the source and target branches.
3. Select the GitHub issues that the PR should close. PR Buddy automatically aggregates their labels for the PR.
4. Review the generated title and description. If everything looks good, choose to create the PR; the script will call `gh pr create` with the populated metadata.

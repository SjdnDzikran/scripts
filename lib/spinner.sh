#!/usr/bin/env bash
#
# spinner.sh: Shared utility functions for scripts
# Provides spinner animations and common helper functions

spinner_pid=""
spinner_fd=""

start_spinner() {
    local message="$1"
    local interval="${2:-0.08}"
    local i=0
    local -a spinner_frames

    # Stop any existing spinner before starting a new one.
    stop_spinner >/dev/null 2>&1 || true

    if [[ "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" == *"UTF-8"* || "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" == *"utf8"* ]]; then
        spinner_frames=( "⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏" )
    else
        spinner_frames=( "|" "/" "-" "\\" )
    fi

    # Prefer writing to the active terminal directly when available.
    if [[ -t 1 ]]; then
        spinner_fd=1
    elif [[ -t 2 ]]; then
        spinner_fd=2
    else
        spinner_fd=1
    fi

    tput civis 2>/dev/null || true

    (
        trap 'exit 0' TERM INT
        while true; do
            printf "\r%s %s " "$message" "${spinner_frames[$((i % ${#spinner_frames[@]}))]}" >&"$spinner_fd"
            sleep "$interval"
            i=$((i+1))
        done
    ) &

    spinner_pid=$!
}

stop_spinner() {
    if [[ -n "$spinner_pid" ]]; then
        kill "$spinner_pid" 2>/dev/null || true
        wait "$spinner_pid" 2>/dev/null || true
        spinner_pid=""
    fi
    tput cnorm 2>/dev/null || true
    if [[ -n "$spinner_fd" ]]; then
        printf "\r\033[K" >&"$spinner_fd"
    else
        printf "\r\033[K"
    fi
    spinner_fd=""
}

require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        echo "❌ Required command '$cmd' is not installed."
        exit 1
    fi
}

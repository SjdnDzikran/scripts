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
    local spinner_color_start=""
    local spinner_color_end=""
    local spinner_color="${SPINNER_COLOR:-cyan}"

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

    # Colorize spinner frame for TTY output unless NO_COLOR is set.
    if [[ -t "$spinner_fd" && -z "${NO_COLOR:-}" ]]; then
        case "$spinner_color" in
            red) spinner_color_start=$'\033[31m' ;;
            green) spinner_color_start=$'\033[32m' ;;
            yellow) spinner_color_start=$'\033[33m' ;;
            blue) spinner_color_start=$'\033[34m' ;;
            magenta) spinner_color_start=$'\033[35m' ;;
            cyan) spinner_color_start=$'\033[36m' ;;
            white) spinner_color_start=$'\033[37m' ;;
            bold) spinner_color_start=$'\033[1m' ;;
            none|off) spinner_color_start="" ;;
            *) spinner_color_start=$'\033[36m' ;;
        esac
        if [[ -n "$spinner_color_start" ]]; then
            spinner_color_end=$'\033[0m'
        fi
    fi

    tput civis 2>/dev/null || true

    (
        trap 'exit 0' TERM INT
        while true; do
            printf "\r%s %s%s%s " "$message" "$spinner_color_start" "${spinner_frames[$((i % ${#spinner_frames[@]}))]}" "$spinner_color_end" >&"$spinner_fd"
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

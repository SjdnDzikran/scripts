#!/usr/bin/env bash
#
# bump-version.sh: Increment the Flutter/Dart version in pubspec.yaml.

set -euo pipefail

pubspec_path=${1:-pubspec.yaml}

if [[ ! -f "$pubspec_path" ]]; then
    echo "Error: pubspec.yaml not found at '$pubspec_path'."
    echo "Run this from your Flutter project root or pass the path: $0 path/to/pubspec.yaml"
    exit 1
fi

# Extract the current version value (e.g., 1.2.3 or 1.2.3+4), trim comments/whitespace/CRLF.
version_line=$(grep -E '^[[:space:]]*version:' "$pubspec_path" \
    | head -n1 \
    | sed -E 's/^[[:space:]]*version:[[:space:]]*//' \
    | cut -d'#' -f1 \
    | tr -d '[:space:]' \
    | tr -d '\r')
if [[ -z "$version_line" ]]; then
    echo "Error: Could not find a version in $pubspec_path."
    exit 1
fi

base_version=${version_line%%+*}
build_number=""
if [[ "$version_line" == *"+"* ]]; then
    build_number=${version_line#*+}
fi

IFS='.' read -r major minor patch <<< "$base_version" || {
    echo "Error: Version is not in the expected format (x.y.z or x.y.z+build)."
    exit 1
}

for part in "$major" "$minor" "$patch"; do
    if ! [[ "$part" =~ ^[0-9]+$ ]]; then
        echo "Error: Invalid numeric version component in '$version_line'."
        exit 1
    fi
done

if [[ -n "$build_number" && ! "$build_number" =~ ^[0-9]+$ ]]; then
    echo "Error: Build number must be numeric if present (found '$build_number')."
    exit 1
fi

echo "Current version: $version_line (from $pubspec_path)"
read -p "Bump which part? [M]ajor/[m]inor/[p]atch (default: patch): " bump_choice

case "$bump_choice" in
    M|major|MAJOR)
        ((major++))
        minor=0
        patch=0
        ;;
    m|minor|MINOR)
        ((minor++))
        patch=0
        ;;
    ""|p|P|patch|PATCH)
        ((patch++))
        ;;
    *)
        echo "Error: Unknown choice '$bump_choice'."
        exit 1
        ;;
esac

new_version="${major}.${minor}.${patch}"
if [[ -n "$build_number" ]]; then
    new_version+="+${build_number}"
fi

tmpfile=$(mktemp)
if ! sed -E "0,/^[[:space:]]*version:[[:space:]]*[^[:space:]]+/ { s/^([[:space:]]*version:[[:space:]]*)[^[:space:]]+([[:space:]]*.*)$/\1${new_version}\2/ }" "$pubspec_path" > "$tmpfile"; then
    echo "Error: failed to update version in $pubspec_path"
    rm -f "$tmpfile"
    exit 1
fi
mv "$tmpfile" "$pubspec_path"

echo "✅ Version bumped to: $new_version"

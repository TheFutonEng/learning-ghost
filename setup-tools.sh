#!/bin/bash
set -e

echo "Checking required tools."

# Check if asdf is installed
if ! command -v asdf &> /dev/null; then
    echo "asdf is not installed. Please install it first: https://asdf-vm.com/guide/getting-started.html"
    exit 1
fi

# Read the .tool-versions file
while IFS=' ' read -r tool version || [[ -n "$tool" ]]; do
    if [[ -z "$tool" || "$tool" =~ ^# ]]; then
        # Skip empty lines or comments
        continue
    fi

    # Check if the plugin is installed
    if ! asdf plugin list | grep -q "^$tool$"; then
        echo "Installing asdf plugin for $tool."
        asdf plugin add "$tool"
    fi

    # Check if the version is installed
    if ! asdf list "$tool" | grep -q "^$version$"; then
        echo "Installing $tool version $version."
        asdf install "$tool" "$version"
    fi

    echo "$tool $version is ready"
done < .tool-versions

echo "All required tools are installed and configured!"
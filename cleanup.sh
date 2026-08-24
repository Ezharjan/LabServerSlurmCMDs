#!/bin/bash

echo "Starting cluster cache and trash cleanup..."
echo "-------------------------------------------"

# 1. Clean the Trash
echo "[1/3] Emptying system trash..."
if [ -d "$HOME/.local/share/Trash" ]; then
    rm -rf "$HOME/.local/share/Trash"/*
    echo "  -> Trash emptied."
else
    echo "  -> No Trash directory found. Skipping."
fi

# 2. Clean Conda Cache
echo "[2/3] Cleaning Conda cache..."
if command -v conda &> /dev/null; then
    # The -y flag answers 'yes' automatically
    conda clean --all -y
    echo "  -> Conda cache cleaned."
else
    echo "  -> Conda is not currently active in this session. Skipping."
fi

# 3. Clean Pip Cache
echo "[3/3] Cleaning pip cache..."
if command -v pip &> /dev/null; then
    pip cache purge
    echo "  -> Pip cache purged."
else
    echo "  -> Pip command not found in this session."
    echo "  -> Clearing the pip cache directory directly..."
    rm -rf "$HOME/.cache/pip"
    echo "  -> Pip cache directory emptied."
fi

echo "-------------------------------------------"
echo "Cleanup complete!"

#!/bin/bash
# Helper Git Module - Git repository utilities
# No dependencies

function git_cleanout() {
    # Clean and prune git repository
    # Removes merged branches, fetches updates, and performs garbage collection
    git gc
    git fetch --prune --all
    git pull
    git remote prune origin
    git branch --merged | grep -E -v 'master|main' | grep -E -v '^\*' | xargs git branch -d
}

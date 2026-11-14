#!/bin/bash
# Helper Git Module - Git repository utilities
# No dependencies

function hh_git_cleanout() {
    # Clean and prune git repository: gc, fetch/prune, pull, then delete
    # local branches already merged into HEAD (never main/master, the
    # current branch or a branch checked out in another worktree).
    # Every step runs; the status is the first failing step's.
    # Sourced by bash and zsh: keep to the common subset (no $status).
    local rc=0 step_rc
    git gc || rc=$?
    git fetch --prune --all || { step_rc=$?; ((rc)) || rc=${step_rc}; }
    git pull || { step_rc=$?; ((rc)) || rc=${step_rc}; }
    git remote prune origin || { step_rc=$?; ((rc)) || rc=${step_rc}; }
    git branch \
        --format='%(if)%(HEAD)%(then)%(else)%(if)%(worktreepath)%(then)%(else)%(refname:short)%(end)%(end)' \
        --merged \
        | awk 'NF && $0 != "main" && $0 != "master"' \
        | xargs -r git branch -d || { step_rc=$?; ((rc)) || rc=${step_rc}; }
    return "${rc}"
}

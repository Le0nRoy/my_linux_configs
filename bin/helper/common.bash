#!/bin/bash
# Helper Common Module - Shared variables and constants
# This module provides common variables used across all helper modules

# Script metadata - these are set by the main helper.bash script
# HOME_HELPER_UNIQ_SCRIPT_NAME - name of the main script
# HOME_HELPER_UNIQ_SCRIPT_PATH - full path to the main script
# HOME_HELPER_UNIQ_SCRIPT_DIR - directory containing the main script

# Job-related variables and paths
export JOB_MOUNT_DIR="/Data/Job"
export JOB_SETUP_FILE="/Data/Job/add_exports.bash"
export JOB_TEARDOWN_FILE="/Data/Job/remove_exports.bash"

# Port assignments for services
export PORT_SWAGGER_UI=8081
export PORT_SWAGGER_EDITOR=8082

# Desktop customization
export DESKTOP_BG="${DESKTOP_BG:-${HOME}/Pictures/png_files/St_Louis_Sciamano.png}"
export LOCK_SCREEN_IMAGE="${LOCK_SCREEN_IMAGE:-${HOME}/Pictures/png_files/maximum_beat.png}"

# Tmux session name
export TMUX_SESSION="${TMUX_SESSION:-tmux-main}"

# Audio sink name (can be overridden)
export SINK_NAME="${SINK_NAME:-@DEFAULT_SINK@}"

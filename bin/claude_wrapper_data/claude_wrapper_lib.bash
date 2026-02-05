#!/bin/bash
# Claude Wrapper Library - Menu functions and helpers for claude_wrapper.bash
#
# This library provides interactive menus for selecting MCPs, skills, and presets.
# It is sourced by executable_claude_wrapper.bash.

# ===== CONSTANTS =====

# Configuration paths - WRAPPER_DATA_DIR is set by the wrapper before sourcing
WRAPPER_DATA_DIR="${WRAPPER_DATA_DIR:-$(dirname "${BASH_SOURCE[0]}")}"
WRAPPER_CONFIG="${WRAPPER_DATA_DIR}/wrapper-config.json"
WRAPPER_HELP="${WRAPPER_DATA_DIR}/wrapper-help.md"
MCP_PRESETS_DIR="${WRAPPER_DATA_DIR}/mcp-presets"

# Claude runtime directory (for skills, etc.)
CLAUDE_DIR="${HOME}/.claude"

# Local project storage (git-ignored)
LOCAL_STORAGE_DIR=".claude-wrapper"

# ===== GLOBAL STATE =====

# Selected items (arrays)
declare -a SELECTED_MCPS=()
declare -a SELECTED_SKILLS=()

# Available items (loaded from config)
declare -a AVAILABLE_MCPS=()
declare -a AVAILABLE_SKILLS=()
declare -a AVAILABLE_PRESETS=()

# ===== UTILITY FUNCTIONS =====

# Log message to stderr
wrapper_log() {
    local level="${1}"
    shift
    echo -e "[claude-wrapper] ${level}: $*" >&2
}

# Check if a value is in an array
# Usage: array_contains "value" "${array[@]}"
array_contains() {
    local needle="${1}"
    shift
    local item
    for item in "$@"; do
        [[ "${item}" == "${needle}" ]] && return 0
    done
    return 1
}

# Toggle item in array (add if not present, remove if present)
# Usage: array_toggle "value" array_name
array_toggle() {
    local value="${1}"
    local -n arr_ref="${2}"
    local -a new_arr=()
    local found=0

    for item in "${arr_ref[@]}"; do
        if [[ "${item}" == "${value}" ]]; then
            found=1
        else
            new_arr+=("${item}")
        fi
    done

    if [[ ${found} -eq 0 ]]; then
        new_arr+=("${value}")
    fi

    arr_ref=("${new_arr[@]}")
}

# Remove all items from array
# Usage: array_clear array_name
array_clear() {
    local -n arr_ref="${1}"
    arr_ref=()
}

# ===== CONFIGURATION LOADING =====

# Load available MCPs, skills, and presets from config
load_wrapper_config() {
    if [[ ! -f "${WRAPPER_CONFIG}" ]]; then
        wrapper_log "ERROR" "Configuration not found: ${WRAPPER_CONFIG}"
        return 1
    fi

    # Load MCPs
    mapfile -t AVAILABLE_MCPS < <(jq -r '.mcps[].id' "${WRAPPER_CONFIG}" 2>/dev/null)

    # Load skills
    mapfile -t AVAILABLE_SKILLS < <(jq -r '.skills[].id' "${WRAPPER_CONFIG}" 2>/dev/null)

    # Load presets
    mapfile -t AVAILABLE_PRESETS < <(jq -r '.presets[].id' "${WRAPPER_CONFIG}" 2>/dev/null)

    return 0
}

# Get MCP info by ID
# Usage: get_mcp_info "mcp-id" "field"
get_mcp_info() {
    local mcp_id="${1}"
    local field="${2}"
    jq -r ".mcps[] | select(.id == \"${mcp_id}\") | .${field}" "${WRAPPER_CONFIG}" 2>/dev/null
}

# Get skill info by ID
get_skill_info() {
    local skill_id="${1}"
    local field="${2}"
    jq -r ".skills[] | select(.id == \"${skill_id}\") | .${field}" "${WRAPPER_CONFIG}" 2>/dev/null
}

# Get preset info by ID
get_preset_info() {
    local preset_id="${1}"
    local field="${2}"
    jq -r ".presets[] | select(.id == \"${preset_id}\") | .${field}" "${WRAPPER_CONFIG}" 2>/dev/null
}

# Get preset MCPs as array
get_preset_mcps() {
    local preset_id="${1}"
    jq -r ".presets[] | select(.id == \"${preset_id}\") | .mcps[]" "${WRAPPER_CONFIG}" 2>/dev/null
}

# Get preset skills as array
get_preset_skills() {
    local preset_id="${1}"
    jq -r ".presets[] | select(.id == \"${preset_id}\") | .skills[]" "${WRAPPER_CONFIG}" 2>/dev/null
}

# ===== LOCAL STORAGE =====

# Setup local storage directory and git exclusion
setup_local_storage() {
    local project_root
    project_root="$(git rev-parse --show-toplevel 2>/dev/null)" || project_root="$(pwd)"

    local storage_dir="${project_root}/${LOCAL_STORAGE_DIR}"

    if [[ ! -d "${storage_dir}" ]]; then
        mkdir -p "${storage_dir}"
    fi

    # Add to .git/info/exclude if in a git repo
    local git_exclude="${project_root}/.git/info/exclude"
    if [[ -f "${git_exclude}" ]]; then
        if ! grep -q "^${LOCAL_STORAGE_DIR}/$" "${git_exclude}" 2>/dev/null; then
            echo "${LOCAL_STORAGE_DIR}/" >> "${git_exclude}"
        fi
    fi

    echo "${storage_dir}"
}

# Get or prompt for GitLab URL
get_gitlab_url() {
    local storage_dir
    storage_dir="$(setup_local_storage)"
    local gitlab_file="${storage_dir}/gitlab-url"

    if [[ -f "${gitlab_file}" ]]; then
        cat "${gitlab_file}"
        return 0
    fi

    # Prompt user
    echo ""
    echo "GitLab URL not configured for this project."
    echo -n "Enter GitLab instance URL (e.g., https://gitlab.example.com): "
    read -r gitlab_url

    if [[ -n "${gitlab_url}" ]]; then
        echo "${gitlab_url}" > "${gitlab_file}"
        echo "${gitlab_url}"
        return 0
    fi

    return 1
}

# ===== KUBERNETES SETUP =====

# Path to AI kubeconfig
AI_KUBECONFIG="${HOME}/.kube/ai-agent-config"

# Check if Kubernetes is configured for AI agents
is_kubernetes_configured() {
    [[ -f "${AI_KUBECONFIG}" ]]
}

# ===== MCP CONFIGURATION =====

# Expand environment variables in a string
# Usage: expand_env_vars "string with ${VAR}"
expand_env_vars() {
    local input="${1}"
    # Use envsubst if available, otherwise use eval
    if command -v envsubst &>/dev/null; then
        echo "${input}" | envsubst
    else
        eval echo "\"${input}\""
    fi
}

# Check if MCP has all required credentials and setup
# Returns 0 if ready, 1 if missing credentials
check_mcp_credentials() {
    local mcp_id="${1}"

    # Special handling for Kubernetes MCP - offer interactive setup
    if [[ "${mcp_id}" == "kubernetes-ro" ]]; then
        if ! is_kubernetes_configured; then
            echo "" >/dev/tty
            echo "Kubernetes MCP requires AI agent kubeconfig." >/dev/tty
            echo "File not found: ${AI_KUBECONFIG}" >/dev/tty
            echo -n "Would you like to set it up now? [y/N]: " >/dev/tty
            read -r setup_k8s </dev/tty

            if [[ "${setup_k8s}" == "y" || "${setup_k8s}" == "Y" ]]; then
                local setup_script="${HOME}/bin/setup_ai_kube_access.bash"
                if [[ -f "${setup_script}" ]]; then
                    bash "${setup_script}" </dev/tty >/dev/tty 2>&1
                    if ! is_kubernetes_configured; then
                        wrapper_log "WARNING" "MCP 'kubernetes-ro' skipped - setup failed" >/dev/tty
                        return 1
                    fi
                else
                    wrapper_log "WARNING" "MCP 'kubernetes-ro' skipped - setup script not found" >/dev/tty
                    return 1
                fi
            else
                wrapper_log "WARNING" "MCP 'kubernetes-ro' skipped - kubeconfig not configured" >/dev/tty
                return 1
            fi
        fi
    fi

    local requirements
    requirements=$(get_mcp_info "${mcp_id}" "requirements")

    if [[ -z "${requirements}" || "${requirements}" == "null" ]]; then
        return 0
    fi

    # Check required environment variables
    local env_vars missing_vars=()
    mapfile -t env_vars < <(echo "${requirements}" | jq -r '.env[]? // empty' 2>/dev/null)
    for var in "${env_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("${var}")
        fi
    done

    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        wrapper_log "WARNING" "MCP '${mcp_id}' skipped - missing env vars: ${missing_vars[*]}" >/dev/tty
        return 1
    fi

    # Check required files (except for kubernetes which we handled above)
    if [[ "${mcp_id}" != "kubernetes-ro" ]]; then
        local files
        mapfile -t files < <(echo "${requirements}" | jq -r '.files[]? // empty' 2>/dev/null)
        for file in "${files[@]}"; do
            local expanded_file
            expanded_file=$(eval echo "${file}")
            if [[ ! -f "${expanded_file}" ]]; then
                wrapper_log "WARNING" "MCP '${mcp_id}' skipped - missing file: ${file}" >/dev/tty
                return 1
            fi
        done
    fi

    return 0
}

# Merge selected MCP configs into a single JSON file
# Only includes MCPs with valid credentials
# Output path is printed to stdout
merge_mcp_configs() {
    local -a selected_mcps=("$@")
    local output_file="/tmp/claude-mcp-$$.json"

    if [[ ${#selected_mcps[@]} -eq 0 ]]; then
        echo ""
        return 0
    fi

    # Start with empty mcpServers object
    local merged='{"mcpServers":{}}'
    local valid_count=0

    for mcp_id in "${selected_mcps[@]}"; do
        # Skip MCPs without credentials
        if ! check_mcp_credentials "${mcp_id}"; then
            continue
        fi

        local config_file="${MCP_PRESETS_DIR}/${mcp_id}.json"

        if [[ ! -f "${config_file}" ]]; then
            wrapper_log "WARNING" "MCP config not found: ${config_file}" >/dev/tty
            continue
        fi

        # Read and expand environment variables in the config
        local config_content
        config_content=$(expand_env_vars "$(cat "${config_file}")")

        # Merge this MCP's servers into the combined config
        merged=$(echo "${merged}" | jq --argjson mcp "${config_content}" '
            .mcpServers += ($mcp.mcpServers // {})
        ' 2>/dev/null)

        valid_count=$((valid_count + 1))
    done

    if [[ ${valid_count} -eq 0 ]]; then
        wrapper_log "WARNING" "No MCPs could be loaded (missing credentials)" >/dev/tty
        echo ""
        return 0
    fi

    echo "${merged}" > "${output_file}"
    echo "${output_file}"
}

# ===== MENU DISPLAY =====
# All menu output goes to /dev/tty to avoid capture by $() subshells

# Clear screen and show header
show_header() {
    clear >/dev/tty
    echo "==========================================" >/dev/tty
    echo "       Claude CLI - Session Options      " >/dev/tty
    echo "==========================================" >/dev/tty
    echo "" >/dev/tty
}

# Show current selections summary
show_selections_summary() {
    echo "Current selections:" >/dev/tty
    if [[ ${#SELECTED_MCPS[@]} -gt 0 ]]; then
        echo "  MCPs: ${SELECTED_MCPS[*]}" >/dev/tty
    else
        echo "  MCPs: (none)" >/dev/tty
    fi
    if [[ ${#SELECTED_SKILLS[@]} -gt 0 ]]; then
        echo "  Skills: ${SELECTED_SKILLS[*]}" >/dev/tty
    else
        echo "  Skills: (none)" >/dev/tty
    fi
    echo "" >/dev/tty
}

# Show main menu
# Returns: selected action (preset, mcp, skill, help, new, resume) via stdout
show_main_menu() {
    while true; do
        show_header
        show_selections_summary

        echo "Options:" >/dev/tty
        echo "  1) Presets (MCPs + Skills bundles)" >/dev/tty
        echo "  2) Connect MCPs" >/dev/tty
        echo "  3) Connect Skills" >/dev/tty
        echo "  4) Help" >/dev/tty
        echo "  5) Start new conversation" >/dev/tty
        echo "  6) Resume from list" >/dev/tty
        echo "" >/dev/tty
        echo -n "Choose an option [1-6]: " >/dev/tty
        read -r choice </dev/tty

        case "${choice}" in
            1) echo "preset"; return 0 ;;
            2) echo "mcp"; return 0 ;;
            3) echo "skill"; return 0 ;;
            4) echo "help"; return 0 ;;
            5) echo "new"; return 0 ;;
            6) echo "resume"; return 0 ;;
            *)
                echo "Invalid choice. Press Enter to continue..." >/dev/tty
                read -r </dev/tty
                ;;
        esac
    done
}

# Generic multi-select menu
# Arguments:
#   $1 - Menu title
#   $2 - Name of array containing item IDs
#   $3 - Name of array containing selected items (will be modified)
#   $4 - Config type for getting info (mcp, skill)
show_multiselect_menu() {
    local title="${1}"
    local -n items_ref="${2}"
    local -n selected_ref="${3}"
    local config_type="${4}"

    while true; do
        show_header
        echo "${title}" >/dev/tty
        echo "----------------------------------------" >/dev/tty
        echo "" >/dev/tty

        local i=1
        for item_id in "${items_ref[@]}"; do
            local name description
            if [[ "${config_type}" == "mcp" ]]; then
                name=$(get_mcp_info "${item_id}" "name")
                description=$(get_mcp_info "${item_id}" "description")
            elif [[ "${config_type}" == "skill" ]]; then
                name=$(get_skill_info "${item_id}" "name")
                description=$(get_skill_info "${item_id}" "description")
            fi

            local marker="[ ]"
            if array_contains "${item_id}" "${selected_ref[@]}"; then
                marker="[x]"
            fi

            printf "  %2d) %s %-20s - %s\n" "${i}" "${marker}" "${name:-${item_id}}" "${description:-}" >/dev/tty
            i=$((i + 1))
        done

        echo "" >/dev/tty
        echo "Commands: [number] toggle, [b]ack, [r]eset, [d]one" >/dev/tty
        echo -n "> " >/dev/tty
        read -r input </dev/tty

        case "${input}" in
            b|back|B|Back)
                return 0
                ;;
            r|reset|R|Reset)
                array_clear selected_ref
                ;;
            d|done|D|Done)
                return 0
                ;;
            [0-9]*)
                local idx=$((input - 1))
                if [[ ${idx} -ge 0 && ${idx} -lt ${#items_ref[@]} ]]; then
                    local item_id="${items_ref[${idx}]}"
                    array_toggle "${item_id}" selected_ref
                else
                    echo "Invalid number. Press Enter to continue..." >/dev/tty
                    read -r </dev/tty
                fi
                ;;
            *)
                echo "Unknown command. Press Enter to continue..." >/dev/tty
                read -r </dev/tty
                ;;
        esac
    done
}

# Show presets menu
show_presets_menu() {
    while true; do
        show_header
        echo "Presets (MCPs + Skills bundles)" >/dev/tty
        echo "----------------------------------------" >/dev/tty
        echo "" >/dev/tty
        echo "Selecting a preset will clear other selections and start immediately." >/dev/tty
        echo "" >/dev/tty

        local i=1
        for preset_id in "${AVAILABLE_PRESETS[@]}"; do
            local name description
            name=$(get_preset_info "${preset_id}" "name")
            description=$(get_preset_info "${preset_id}" "description")
            printf "  %2d) %-20s - %s\n" "${i}" "${name:-${preset_id}}" "${description:-}" >/dev/tty
            i=$((i + 1))
        done

        echo "" >/dev/tty
        echo "Commands: [number] select preset, [b]ack" >/dev/tty
        echo -n "> " >/dev/tty
        read -r input </dev/tty

        case "${input}" in
            b|back|B|Back)
                return 1
                ;;
            [0-9]*)
                local idx=$((input - 1))
                if [[ ${idx} -ge 0 && ${idx} -lt ${#AVAILABLE_PRESETS[@]} ]]; then
                    local preset_id="${AVAILABLE_PRESETS[${idx}]}"

                    # Clear existing selections
                    SELECTED_MCPS=()
                    SELECTED_SKILLS=()

                    # Load preset MCPs
                    mapfile -t SELECTED_MCPS < <(get_preset_mcps "${preset_id}")

                    # Load preset skills
                    mapfile -t SELECTED_SKILLS < <(get_preset_skills "${preset_id}")

                    echo "" >/dev/tty
                    echo "Preset '${preset_id}' loaded:" >/dev/tty
                    echo "  MCPs: ${SELECTED_MCPS[*]:-none}" >/dev/tty
                    echo "  Skills: ${SELECTED_SKILLS[*]:-none}" >/dev/tty
                    echo "" >/dev/tty
                    echo "Starting Claude session..." >/dev/tty
                    sleep 1

                    return 0  # Signal to start session
                else
                    echo "Invalid number. Press Enter to continue..." >/dev/tty
                    read -r </dev/tty
                fi
                ;;
            *)
                echo "Unknown command. Press Enter to continue..." >/dev/tty
                read -r </dev/tty
                ;;
        esac
    done
}

# Display help
display_help() {
    show_header

    if [[ -f "${WRAPPER_HELP}" ]]; then
        # Use less if available, otherwise cat - output to tty
        if command -v less &>/dev/null; then
            less "${WRAPPER_HELP}" </dev/tty >/dev/tty
        else
            cat "${WRAPPER_HELP}" >/dev/tty
        fi
    else
        echo "Help file not found: ${WRAPPER_HELP}" >/dev/tty
        echo "" >/dev/tty
        echo "Available MCPs:" >/dev/tty
        for mcp_id in "${AVAILABLE_MCPS[@]}"; do
            local name description
            name=$(get_mcp_info "${mcp_id}" "name")
            description=$(get_mcp_info "${mcp_id}" "description")
            echo "  - ${name:-${mcp_id}}: ${description:-}" >/dev/tty
        done
        echo "" >/dev/tty
        echo "Available Skills:" >/dev/tty
        for skill_id in "${AVAILABLE_SKILLS[@]}"; do
            local name description
            name=$(get_skill_info "${skill_id}" "name")
            description=$(get_skill_info "${skill_id}" "description")
            echo "  - ${name:-${skill_id}}: ${description:-}" >/dev/tty
        done
        echo "" >/dev/tty
        echo "Press Enter to return to menu..." >/dev/tty
        read -r </dev/tty
    fi
}

# ===== MAIN MENU LOOP =====

# Run the interactive menu system
# Returns selected action and sets SELECTED_MCPS and SELECTED_SKILLS
run_menu_system() {
    # Load configuration
    if ! load_wrapper_config; then
        wrapper_log "ERROR" "Failed to load configuration"
        return 1
    fi

    while true; do
        local action
        action=$(show_main_menu)

        case "${action}" in
            preset)
                if show_presets_menu; then
                    echo "start"
                    return 0
                fi
                ;;
            mcp)
                show_multiselect_menu "Connect MCPs" AVAILABLE_MCPS SELECTED_MCPS "mcp"
                ;;
            skill)
                show_multiselect_menu "Connect Skills" AVAILABLE_SKILLS SELECTED_SKILLS "skill"
                ;;
            help)
                display_help
                ;;
            new)
                echo "start"
                return 0
                ;;
            resume)
                echo "resume"
                return 0
                ;;
        esac
    done
}

# ===== COMMAND BUILDING =====

# Build additional Claude flags based on selections
# Outputs flags to stdout (one per line)
build_claude_flags() {
    local -a flags=()

    # Handle MCP configurations
    if [[ ${#SELECTED_MCPS[@]} -gt 0 ]]; then
        # Merge MCP configs (filters out those missing credentials)
        local mcp_config
        mcp_config=$(merge_mcp_configs "${SELECTED_MCPS[@]}")
        if [[ -n "${mcp_config}" && -f "${mcp_config}" ]]; then
            flags+=(--mcp-config "${mcp_config}")
        fi
    fi

    # Note: Claude Code skills (slash commands) are built-in and always available
    # The SELECTED_SKILLS array is informational only - used for preset descriptions

    # Output flags
    printf '%s\n' "${flags[@]}"
}

# Cleanup temporary files
cleanup_wrapper() {
    # Remove temporary MCP config files
    rm -f /tmp/claude-mcp-$$.json 2>/dev/null
}

# Set trap for cleanup
trap cleanup_wrapper EXIT

# ===== SCRIPT GUARD =====

# Prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is meant to be sourced, not executed directly." >&2
    echo "Usage: source claude_wrapper_lib.bash" >&2
    exit 1
fi

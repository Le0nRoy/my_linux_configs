#!/bin/bash
# Claude Wrapper Library - Menu functions and helpers for claude_wrapper.bash
#
# This library provides an interactive menu for agent orchestration setup
# and plain session management. It is sourced by executable_claude_wrapper.bash.

# ===== CONSTANTS =====

# Configuration paths - WRAPPER_DATA_DIR is set by the wrapper before sourcing
WRAPPER_DATA_DIR="${WRAPPER_DATA_DIR:-$(dirname "${BASH_SOURCE[0]}")}"
WRAPPER_CONFIG="${WRAPPER_DATA_DIR}/wrapper-config.json"
WRAPPER_HELP="${WRAPPER_DATA_DIR}/wrapper-help.md"
MCP_PRESETS_DIR="${WRAPPER_DATA_DIR}/mcp-presets"
ORCHESTRATOR_PROMPT="${WRAPPER_DATA_DIR}/orchestrator-prompt.md"
AGENT_ROLES_CONFIG="${WRAPPER_DATA_DIR}/agent-roles.json"

# Claude runtime directory (for skills, etc.)
CLAUDE_DIR="${HOME}/.claude"

# Local project storage (git-ignored)
LOCAL_STORAGE_DIR=".claude-wrapper"

# ===== GLOBAL STATE =====

# Selected items (arrays)
declare -a SELECTED_MCPS=()

# Available items (loaded from config)
declare -a AVAILABLE_MCPS=()

# Orchestration role assignments (loaded from agent-roles.json, modifiable at runtime)
declare -A ROLE_ASSIGNMENTS=()

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

# ===== CONFIGURATION LOADING =====

# Load available MCPs from config
load_wrapper_config() {
    if [[ ! -f "${WRAPPER_CONFIG}" ]]; then
        wrapper_log "ERROR" "Configuration not found: ${WRAPPER_CONFIG}"
        return 1
    fi

    # Load MCPs
    mapfile -t AVAILABLE_MCPS < <(jq -r '.mcps[].id' "${WRAPPER_CONFIG}" 2>/dev/null)

    return 0
}

# Get MCP info by ID
# Usage: get_mcp_info "mcp-id" "field"
get_mcp_info() {
    local mcp_id="${1}"
    local field="${2}"
    jq -r ".mcps[] | select(.id == \"${mcp_id}\") | .${field}" "${WRAPPER_CONFIG}" 2>/dev/null
}

# ===== AGENT ROLES =====

# Load role assignments from agent-roles.json (defaults)
load_agent_roles() {
    if [[ ! -f "${AGENT_ROLES_CONFIG}" ]]; then
        wrapper_log "ERROR" "Agent roles config not found: ${AGENT_ROLES_CONFIG}"
        return 1
    fi

    local roles
    roles=$(jq -r '.default_roles | to_entries[] | .key + "=" + .value' "${AGENT_ROLES_CONFIG}" 2>/dev/null)
    while IFS='=' read -r role agent; do
        ROLE_ASSIGNMENTS["${role}"]="${agent}"
    done <<< "${roles}"

    return 0
}

# Check if an agent binary is installed
check_agent_installed() {
    local agent_id="${1}"
    local cmd
    cmd=$(jq -r ".agents.\"${agent_id}\".command" "${AGENT_ROLES_CONFIG}" 2>/dev/null)
    command -v "${cmd}" &>/dev/null
}

# Check which required skills are missing
# Prints space-separated list of missing skill names
check_skills_installed() {
    local -a required_skills=(
        "writing-plans"
        "executing-plans"
        "subagent-driven-development"
        "requesting-code-review"
        "using-git-worktrees"
        "finishing-a-development-branch"
    )
    local -a missing=()
    for skill in "${required_skills[@]}"; do
        if [[ ! -d "${HOME}/.agents/skills/${skill}" ]]; then
            missing+=("${skill}")
        fi
    done
    echo "${missing[*]}"
}

# Install a missing skill via npx
install_missing_skill() {
    local skill_name="${1}"
    echo "Installing skill: ${skill_name}..." >/dev/tty
    npx skills add "${skill_name}" </dev/tty >/dev/tty 2>&1
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

# Show agent availability and role assignments for orchestration
show_dependency_status() {
    echo "Agent availability:" >/dev/tty

    local -a agent_ids
    mapfile -t agent_ids < <(jq -r '.agents | keys[]' "${AGENT_ROLES_CONFIG}" 2>/dev/null)

    for agent_id in "${agent_ids[@]}"; do
        local strengths
        strengths=$(jq -r ".agents.\"${agent_id}\".strengths" "${AGENT_ROLES_CONFIG}" 2>/dev/null)
        if check_agent_installed "${agent_id}"; then
            printf "  ✓ %-10s - %s\n" "${agent_id}" "${strengths}" >/dev/tty
        else
            printf "  ✗ %-10s - Not installed (%s not found)\n" "${agent_id}" \
                "$(jq -r ".agents.\"${agent_id}\".command" "${AGENT_ROLES_CONFIG}" 2>/dev/null)" >/dev/tty
        fi
    done

    echo "" >/dev/tty
    echo "Current role assignments:" >/dev/tty

    local -a role_names=("planner" "implementer" "tester" "reviewer" "finisher")
    for role in "${role_names[@]}"; do
        local agent="${ROLE_ASSIGNMENTS[${role}]:-claude}"
        local desc
        desc=$(jq -r ".role_descriptions.\"${role}\"" "${AGENT_ROLES_CONFIG}" 2>/dev/null)
        printf "  %-14s %s  (%s)\n" "${role^}:" "${agent}" "${desc}" >/dev/tty
    done

    echo "" >/dev/tty

    # Skills status
    local missing_skills
    missing_skills=$(check_skills_installed)
    if [[ -z "${missing_skills}" ]]; then
        echo "Skills: All required skills installed ✓" >/dev/tty
    else
        echo "Skills: Missing - ${missing_skills}" >/dev/tty
    fi
    echo "" >/dev/tty
}

# Show role editor submenu - lets user change agent assignment per role
show_role_editor() {
    local -a role_names=("planner" "implementer" "tester" "reviewer" "finisher")
    local -a agent_ids
    mapfile -t agent_ids < <(jq -r '.agents | keys[]' "${AGENT_ROLES_CONFIG}" 2>/dev/null)

    while true; do
        show_header
        echo "Modify Role Assignments" >/dev/tty
        echo "----------------------------------------" >/dev/tty
        echo "" >/dev/tty

        local i=1
        for role in "${role_names[@]}"; do
            local agent="${ROLE_ASSIGNMENTS[${role}]:-claude}"
            local desc
            desc=$(jq -r ".role_descriptions.\"${role}\"" "${AGENT_ROLES_CONFIG}" 2>/dev/null)
            printf "  %d) %-14s %s  (%s)\n" "${i}" "${role^}:" "${agent}" "${desc}" >/dev/tty
            i=$((i + 1))
        done

        echo "" >/dev/tty
        echo "Available agents: ${agent_ids[*]}" >/dev/tty
        echo "" >/dev/tty
        echo "Commands: [number] change role, [b]ack" >/dev/tty
        echo -n "> " >/dev/tty
        read -r input </dev/tty

        case "${input}" in
            b|back|B|Back)
                return 0
                ;;
            [0-9]*)
                local idx=$((input - 1))
                if [[ ${idx} -ge 0 && ${idx} -lt ${#role_names[@]} ]]; then
                    local role="${role_names[${idx}]}"
                    echo "" >/dev/tty
                    echo "Select agent for ${role^}:" >/dev/tty

                    local j=1
                    for agent_id in "${agent_ids[@]}"; do
                        local installed="✓"
                        if ! check_agent_installed "${agent_id}"; then
                            installed="✗"
                        fi
                        printf "  %d) %s %s\n" "${j}" "${installed}" "${agent_id}" >/dev/tty
                        j=$((j + 1))
                    done

                    echo -n "> " >/dev/tty
                    read -r agent_choice </dev/tty

                    local agent_idx=$((agent_choice - 1))
                    if [[ ${agent_idx} -ge 0 && ${agent_idx} -lt ${#agent_ids[@]} ]]; then
                        local chosen_agent="${agent_ids[${agent_idx}]}"
                        if ! check_agent_installed "${chosen_agent}"; then
                            echo "Warning: ${chosen_agent} is not installed." >/dev/tty
                            echo -n "Assign anyway? [y/N]: " >/dev/tty
                            read -r confirm </dev/tty
                            if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
                                continue
                            fi
                        fi
                        ROLE_ASSIGNMENTS["${role}"]="${chosen_agent}"
                        echo "${role^} assigned to ${chosen_agent}." >/dev/tty
                        sleep 0.5
                    else
                        echo "Invalid choice." >/dev/tty
                        sleep 0.5
                    fi
                else
                    echo "Invalid number." >/dev/tty
                    sleep 0.5
                fi
                ;;
            *)
                echo "Unknown command." >/dev/tty
                sleep 0.5
                ;;
        esac
    done
}

# Apply recommended role assignments (from agent-roles.json)
apply_recommended_roles() {
    local roles
    roles=$(jq -r '.recommended_roles | to_entries[] | select(.key != "_comment") | .key + "=" + .value' \
        "${AGENT_ROLES_CONFIG}" 2>/dev/null)
    while IFS='=' read -r role agent; do
        [[ -z "${role}" ]] && continue
        ROLE_ASSIGNMENTS["${role}"]="${agent}"
    done <<< "${roles}"
}

# Install missing dependencies (agents and skills)
install_missing_dependencies() {
    show_header
    echo "Install Missing Dependencies" >/dev/tty
    echo "----------------------------------------" >/dev/tty
    echo "" >/dev/tty

    # Check agents
    local -a agent_ids
    mapfile -t agent_ids < <(jq -r '.agents | keys[]' "${AGENT_ROLES_CONFIG}" 2>/dev/null)

    local has_missing=0
    for agent_id in "${agent_ids[@]}"; do
        if ! check_agent_installed "${agent_id}"; then
            has_missing=1
            local install_cmd
            install_cmd=$(jq -r ".agents.\"${agent_id}\".install_command" "${AGENT_ROLES_CONFIG}" 2>/dev/null)
            echo "Agent '${agent_id}' not installed." >/dev/tty
            echo "  Install: ${install_cmd}" >/dev/tty
            echo -n "  Install now? [y/N]: " >/dev/tty
            read -r confirm </dev/tty
            if [[ "${confirm}" == "y" || "${confirm}" == "Y" ]]; then
                echo "Running: ${install_cmd}" >/dev/tty
                eval "${install_cmd}" </dev/tty >/dev/tty 2>&1
                if check_agent_installed "${agent_id}"; then
                    echo "  ✓ ${agent_id} installed successfully." >/dev/tty
                else
                    echo "  ✗ ${agent_id} installation failed." >/dev/tty
                fi
            fi
            echo "" >/dev/tty
        fi
    done

    # Check skills
    local missing_skills
    missing_skills=$(check_skills_installed)
    if [[ -n "${missing_skills}" ]]; then
        has_missing=1
        echo "Missing skills: ${missing_skills}" >/dev/tty
        echo -n "Install all missing skills? [y/N]: " >/dev/tty
        read -r confirm </dev/tty
        if [[ "${confirm}" == "y" || "${confirm}" == "Y" ]]; then
            for skill in ${missing_skills}; do
                install_missing_skill "${skill}"
            done
        fi
        echo "" >/dev/tty
    fi

    if [[ ${has_missing} -eq 0 ]]; then
        echo "All dependencies are installed. ✓" >/dev/tty
    fi

    echo "" >/dev/tty
    echo "Press Enter to continue..." >/dev/tty
    read -r </dev/tty
}

# Show orchestration submenu
# Returns "orchestrate" via stdout if user wants to start, or returns without output to go back
show_orchestration_menu() {
    # Load role config
    if ! load_agent_roles; then
        echo "Failed to load agent roles. Press Enter to continue..." >/dev/tty
        read -r </dev/tty
        return 1
    fi

    while true; do
        show_header
        echo "Agent Orchestration" >/dev/tty
        echo "----------------------------------------" >/dev/tty
        echo "" >/dev/tty

        show_dependency_status

        echo "Options:" >/dev/tty
        echo "  1) Start orchestration" >/dev/tty
        echo "  2) Modify role assignments" >/dev/tty
        echo "  3) Use recommended roles" >/dev/tty
        echo "  4) Install missing dependencies" >/dev/tty
        echo "  b) Back" >/dev/tty
        echo "" >/dev/tty
        echo -n "> " >/dev/tty
        read -r choice </dev/tty

        case "${choice}" in
            1)
                echo "orchestrate"
                return 0
                ;;
            2)
                show_role_editor
                ;;
            3)
                apply_recommended_roles
                echo "Recommended roles applied." >/dev/tty
                sleep 0.5
                ;;
            4)
                install_missing_dependencies
                ;;
            b|back|B|Back)
                return 1
                ;;
            *)
                echo "Invalid choice." >/dev/tty
                sleep 0.5
                ;;
        esac
    done
}

# Show main menu
# Returns: selected action (orchestrate, help, new, resume) via stdout
show_main_menu() {
    while true; do
        show_header

        echo "Options:" >/dev/tty
        echo "  1) Agent Orchestration" >/dev/tty
        echo "  2) Help" >/dev/tty
        echo "  3) Start new conversation" >/dev/tty
        echo "  4) Resume from list" >/dev/tty
        echo "" >/dev/tty
        echo -n "Choose an option [1-4]: " >/dev/tty
        read -r choice </dev/tty

        case "${choice}" in
            1) echo "orchestrate"; return 0 ;;
            2) echo "help"; return 0 ;;
            3) echo "new"; return 0 ;;
            4) echo "resume"; return 0 ;;
            *)
                echo "Invalid choice. Press Enter to continue..." >/dev/tty
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
        echo "Claude CLI Wrapper" >/dev/tty
        echo "" >/dev/tty
        echo "Options:" >/dev/tty
        echo "  Agent Orchestration - Launch multi-phase dev workflow (plan/implement/test/review/merge)" >/dev/tty
        echo "  Start new conversation - Launch a plain Claude session" >/dev/tty
        echo "  Resume from list - Resume a previous Claude session" >/dev/tty
        echo "" >/dev/tty
        echo "Press Enter to return to menu..." >/dev/tty
        read -r </dev/tty
    fi
}

# ===== MAIN MENU LOOP =====

# Run the interactive menu system
# Returns selected action via stdout: "start", "resume", or "orchestrate"
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
            orchestrate)
                local orch_result
                orch_result=$(show_orchestration_menu)
                if [[ "${orch_result}" == "orchestrate" ]]; then
                    echo "orchestrate"
                    return 0
                fi
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

# ===== ORCHESTRATION =====

# Build the orchestrator system prompt with role assignments substituted
# Outputs the rendered prompt to stdout
build_orchestrator_prompt() {
    if [[ ! -f "${ORCHESTRATOR_PROMPT}" ]]; then
        wrapper_log "ERROR" "Orchestrator prompt not found: ${ORCHESTRATOR_PROMPT}"
        return 1
    fi

    # Build role assignments text
    local role_text=""
    local -a role_names=("planner" "implementer" "tester" "reviewer" "finisher")
    for role in "${role_names[@]}"; do
        local agent="${ROLE_ASSIGNMENTS[${role}]:-claude}"
        role_text+="- ${role^}: ${agent}"$'\n'
    done

    # Read template and substitute {ROLE_ASSIGNMENTS}
    local prompt_content
    prompt_content=$(<"${ORCHESTRATOR_PROMPT}")
    echo "${prompt_content//\{ROLE_ASSIGNMENTS\}/${role_text}}"
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

    # Output flags
    printf '%s\n' "${flags[@]}"
}

# Cleanup temporary files
cleanup_wrapper() {
    # Remove temporary MCP config files
    rm -f /tmp/claude-mcp-$$.json 2>/dev/null
    # Remove temporary orchestrator prompt files
    rm -f /tmp/claude-orchestrator-$$.md 2>/dev/null
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

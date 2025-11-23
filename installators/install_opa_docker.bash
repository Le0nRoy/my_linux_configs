#!/bin/bash
# Install and configure OPA (Open Policy Agent) for Docker authorization
# Purpose: Block --pid=host and other dangerous Docker flags system-wide
# Security: Enforces policies at Docker daemon level (cannot be bypassed)
# Usage: sudo ./install_opa_docker.bash [--uninstall]

set -e

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Configuration
readonly OPA_VERSION="latest"
readonly OPA_BINARY="/usr/local/bin/opa"
readonly OPA_PLUGIN="openpolicyagent/opa-docker-authz-v2:0.8"
readonly POLICY_DIR="/etc/docker/policies"
readonly POLICY_FILE="${POLICY_DIR}/authz.rego"
readonly DAEMON_CONFIG="/etc/docker/daemon.json"
readonly BACKUP_SUFFIX=".backup-$(date +%Y%m%d-%H%M%S)"

# Logging function using echo_log pattern
echo_log() {
    local level="${1}"
    shift
    local color="${NC}"

    case "${level}" in
        "INFO")
            color="${BLUE}"
            ;;
        "SUCCESS")
            color="${GREEN}"
            ;;
        "WARNING")
            color="${YELLOW}"
            ;;
        "ERROR")
            color="${RED}"
            ;;
    esac

    if [[ "${level}" == "ERROR" ]]; then
        echo -e "${color}[${level}]${NC} $*" >&2
    else
        echo -e "${color}[${level}]${NC} $*"
    fi
}

# Convenience wrappers for backward compatibility
log_info() {
    echo_log "INFO" "$@"
}

log_success() {
    echo_log "SUCCESS" "$@"
}

log_warning() {
    echo_log "WARNING" "$@"
}

log_error() {
    echo_log "ERROR" "$@"
}

# Check if running as root
check_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if Docker is installed
    if ! command -v docker &>/dev/null; then
        log_error "Docker is not installed. Please install Docker first."
        exit 1
    fi

    # Check if Docker daemon is running
    if ! systemctl is-active --quiet docker; then
        log_error "Docker daemon is not running. Start it with: sudo systemctl start docker"
        exit 1
    fi

    # Check if curl is installed
    if ! command -v curl &>/dev/null; then
        log_error "curl is not installed. Install it with: sudo pacman -S curl"
        exit 1
    fi

    # Check if jq is installed (for JSON manipulation)
    if ! command -v jq &>/dev/null; then
        log_error "jq is not installed. Please install it first."
        log_info "Installation command:"
        if command -v pacman &>/dev/null; then
            log_info "  sudo pacman -S jq"
        elif command -v apt-get &>/dev/null; then
            log_info "  sudo apt-get install jq"
        else
            log_info "  Install jq from: https://stedolan.github.io/jq/download/"
        fi
        exit 1
    fi

    log_success "Prerequisites check passed"
}

# Install OPA binary
install_opa_binary() {
    echo_log "INFO" "Installing OPA binary..."

    if [[ -f "${OPA_BINARY}" ]]; then
        echo_log "WARNING" "OPA binary already exists at ${OPA_BINARY}"
        local current_version
        current_version=$("${OPA_BINARY}" version 2>/dev/null | head -1 || echo "unknown")
        echo_log "INFO" "Current version: ${current_version}"

        read -p "Overwrite existing OPA binary? [y/N] " -n 1 -r
        echo
        if [[ ! "${REPLY}" =~ ^[Yy]$ ]]; then
            echo_log "INFO" "Skipping OPA binary installation"
            return 0
        fi
    fi

    local opa_download_url="https://openpolicyagent.org/downloads/${OPA_VERSION}/opa_linux_amd64"
    echo_log "INFO" "Downloading OPA binary from: ${opa_download_url}"

    if curl -L -o "${OPA_BINARY}" "${opa_download_url}"; then
        chmod +x "${OPA_BINARY}"
        echo_log "SUCCESS" "OPA binary installed to ${OPA_BINARY}"
        "${OPA_BINARY}" version
    else
        echo_log "ERROR" "Failed to download OPA binary"
        echo ""
        echo_log "ERROR" "Recovery steps:"
        echo_log "INFO" "1. Check internet connection"
        echo_log "INFO" "2. Try manual download:"
        echo_log "INFO" "   curl -L -o /tmp/opa ${opa_download_url}"
        echo_log "INFO" "   sudo mv /tmp/opa ${OPA_BINARY}"
        echo_log "INFO" "   sudo chmod +x ${OPA_BINARY}"
        echo_log "INFO" "3. Or download from: https://www.openpolicyagent.org/docs/latest/#running-opa"
        echo_log "INFO" "4. Then run this script again"
        exit 1
    fi
}

# Create OPA policy
create_opa_policy() {
    log_info "Creating OPA policy directory and policy file..."

    # Create policy directory
    mkdir -p "${POLICY_DIR}"

    # Backup existing policy if present
    if [[ -f "${POLICY_FILE}" ]]; then
        log_warning "Backing up existing policy to ${POLICY_FILE}${BACKUP_SUFFIX}"
        cp "${POLICY_FILE}" "${POLICY_FILE}${BACKUP_SUFFIX}"
    fi

    # Create policy file
    cat > "${POLICY_FILE}" << 'POLICY_EOF'
package docker.authz

import future.keywords.if
import future.keywords.in

# ==============================================================================
# OPA Docker Authorization Policy
# Purpose: Block dangerous Docker flags for security
# Blocks: --pid=host, --pid=container:*
# Allows: All other Docker operations
# ==============================================================================

# Default policy: allow
default allow := true

# Default response for blocked requests
default blocked_message := ""

# ==============================================================================
# BLOCKING RULES
# ==============================================================================

# Block containers with PID namespace sharing
allow := false if {
    is_container_create_or_run
    has_pid_namespace_sharing
}

blocked_message := "SECURITY: --pid flag is blocked. Containers with --pid=host can see and signal host processes. See /docs/SECURITY_MODEL.md for details." if {
    is_container_create_or_run
    has_pid_namespace_sharing
}

# ==============================================================================
# OPTIONAL BLOCKS (commented out by default)
# ==============================================================================

# Uncomment to block privileged containers
# allow := false if {
#     is_container_create_or_run
#     input.Body.HostConfig.Privileged == true
# }

# Uncomment to block host network mode
# allow := false if {
#     is_container_create_or_run
#     input.Body.HostConfig.NetworkMode == "host"
# }

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

# Check if request is creating or running a container
is_container_create_or_run if {
    input.Method == "POST"
    contains(input.Path, "/containers/create")
}

is_container_create_or_run if {
    input.Method == "POST"
    contains(input.Path, "/containers/run")
}

# Check if PID namespace sharing is enabled
has_pid_namespace_sharing if {
    input.Body.HostConfig.PidMode != ""
    input.Body.HostConfig.PidMode != "private"
}

# String contains helper
contains(str, substr) if {
    indexof(str, substr) != -1
}

# ==============================================================================
# AUDIT LOGGING (optional)
# ==============================================================================

# Log blocked requests for audit purposes
# This can be collected by OPA's decision log feature
audit_log := {
    "timestamp": time.now_ns(),
    "action": "blocked",
    "reason": blocked_message,
    "method": input.Method,
    "path": input.Path,
    "user": input.User,
    "pid_mode": input.Body.HostConfig.PidMode
} if {
    not allow
    blocked_message != ""
}
POLICY_EOF

    log_success "OPA policy created at ${POLICY_FILE}"

    # Validate policy syntax
    log_info "Validating policy syntax..."
    if "${OPA_BINARY}" check "${POLICY_FILE}"; then
        log_success "Policy syntax is valid"
    else
        log_error "Policy syntax validation failed"
        exit 1
    fi
}

# Install Docker OPA plugin
install_docker_plugin() {
    log_info "Installing Docker OPA authorization plugin..."

    # Check if plugin is already installed
    if docker plugin ls | grep -q "${OPA_PLUGIN}"; then
        log_warning "OPA Docker plugin already installed"

        # Check if enabled
        if docker plugin ls | grep "${OPA_PLUGIN}" | grep -q "true"; then
            log_info "Plugin is enabled"
        else
            log_info "Enabling plugin..."
            docker plugin enable "${OPA_PLUGIN}"
        fi

        return 0
    fi

    # Install plugin
    log_info "Installing plugin: ${OPA_PLUGIN}"
    if docker plugin install "${OPA_PLUGIN}" \
        opa-args="-policy-file ${POLICY_FILE} -log-level=info" \
        --grant-all-permissions; then
        log_success "Docker OPA plugin installed"
    else
        log_error "Failed to install Docker OPA plugin"
        exit 1
    fi

    # Verify plugin is enabled
    if docker plugin ls | grep "${OPA_PLUGIN}" | grep -q "true"; then
        log_success "Plugin is enabled and ready"
    else
        log_error "Plugin installed but not enabled"
        exit 1
    fi
}

# Configure Docker daemon
configure_docker_daemon() {
    log_info "Configuring Docker daemon to use OPA plugin..."

    # Backup existing daemon.json
    if [[ -f "${DAEMON_CONFIG}" ]]; then
        log_info "Backing up existing daemon config to ${DAEMON_CONFIG}${BACKUP_SUFFIX}"
        cp "${DAEMON_CONFIG}" "${DAEMON_CONFIG}${BACKUP_SUFFIX}"
    fi

    # Read existing config or create empty object
    local existing_config
    if [[ -f "${DAEMON_CONFIG}" ]]; then
        existing_config=$(cat "${DAEMON_CONFIG}")
    else
        existing_config="{}"
    fi

    # Add or update authorization-plugins
    local new_config
    new_config=$(echo "${existing_config}" | jq \
        --arg plugin "${OPA_PLUGIN}" \
        '.["authorization-plugins"] = [$plugin]')

    # Write new config
    echo "${new_config}" | jq '.' > "${DAEMON_CONFIG}"

    log_success "Docker daemon configuration updated"
    log_info "Configuration: ${DAEMON_CONFIG}"
    cat "${DAEMON_CONFIG}"
}

# Restart Docker daemon
restart_docker() {
    log_info "Restarting Docker daemon to apply changes..."

    if systemctl restart docker; then
        log_success "Docker daemon restarted"

        # Wait for Docker to be ready
        log_info "Waiting for Docker to be ready..."
        local count=0
        while ! docker info &>/dev/null && [[ "${count}" -lt 30 ]]; do
            sleep 1
            ((count++))
        done

        if docker info &>/dev/null; then
            log_success "Docker is ready"
        else
            log_error "Docker failed to start properly"
            exit 1
        fi
    else
        log_error "Failed to restart Docker daemon"
        log_warning "You may need to check Docker logs: sudo journalctl -xeu docker"
        exit 1
    fi
}

# Test OPA configuration
test_opa_configuration() {
    log_info "Testing OPA configuration..."

    echo ""
    log_info "TEST 1: Normal container (should work)"
    if docker run --rm alpine echo "Success" &>/dev/null; then
        log_success "✓ Normal containers work"
    else
        log_error "✗ Normal containers failed (configuration problem)"
        return 1
    fi

    echo ""
    log_info "TEST 2: Container with --pid=host (should be BLOCKED)"
    if docker run --rm --pid=host alpine ps aux &>/dev/null; then
        log_error "✗ --pid=host was NOT blocked (policy not working)"
        return 1
    else
        log_success "✓ --pid=host is blocked (policy working correctly)"
    fi

    echo ""
    log_info "TEST 3: Docker ps (should work)"
    if docker ps &>/dev/null; then
        log_success "✓ Docker ps works"
    else
        log_error "✗ Docker ps failed"
        return 1
    fi

    echo ""
    log_success "All tests passed! OPA is working correctly."
    return 0
}

# Show status
show_status() {
    echo ""
    echo "=========================================="
    log_info "OPA Docker Authorization Status"
    echo "=========================================="
    echo ""

    # OPA binary
    if [[ -f "${OPA_BINARY}" ]]; then
        log_success "OPA binary: ${OPA_BINARY}"
        "${OPA_BINARY}" version | head -1
    else
        log_error "OPA binary: Not installed"
    fi

    echo ""

    # OPA policy
    if [[ -f "${POLICY_FILE}" ]]; then
        log_success "OPA policy: ${POLICY_FILE}"
        log_info "Policy size: $(wc -l < "${POLICY_FILE}") lines"
    else
        log_error "OPA policy: Not found"
    fi

    echo ""

    # Docker plugin
    if docker plugin ls | grep -q "${OPA_PLUGIN}"; then
        log_success "Docker plugin: ${OPA_PLUGIN}"
        docker plugin ls | grep "${OPA_PLUGIN}"
    else
        log_error "Docker plugin: Not installed"
    fi

    echo ""

    # Daemon configuration
    if [[ -f "${DAEMON_CONFIG}" ]]; then
        log_success "Daemon config: ${DAEMON_CONFIG}"
        if grep -q "authorization-plugins" "${DAEMON_CONFIG}"; then
            log_info "Authorization plugins configured:"
            jq '.["authorization-plugins"]' "${DAEMON_CONFIG}"
        else
            log_warning "No authorization plugins in config"
        fi
    else
        log_error "Daemon config: Not found"
    fi

    echo ""
}

# Uninstall OPA
uninstall_opa() {
    echo_log "WARNING" "Uninstalling OPA Docker authorization..."

    echo ""
    read -p "Are you sure you want to uninstall OPA? [y/N] " -n 1 -r
    echo
    if [[ ! "${REPLY}" =~ ^[Yy]$ ]]; then
        echo_log "INFO" "Uninstall cancelled"
        exit 0
    fi

    # Disable and remove Docker plugin
    echo_log "INFO" "Removing Docker plugin..."
    if docker plugin ls | grep -q "${OPA_PLUGIN}"; then
        docker plugin disable "${OPA_PLUGIN}" 2>/dev/null || true
        docker plugin rm "${OPA_PLUGIN}" 2>/dev/null || true
        echo_log "SUCCESS" "Docker plugin removed"
    fi

    # Handle daemon config restoration
    echo ""
    echo_log "INFO" "Docker daemon configuration:"
    if [[ -f "${DAEMON_CONFIG}${BACKUP_SUFFIX}" ]]; then
        echo_log "INFO" "Backup found: ${DAEMON_CONFIG}${BACKUP_SUFFIX}"
        echo ""
        echo "Choose daemon config restoration method:"
        echo "  1) Restore from backup (replace entire file)"
        echo "  2) Just remove authorization-plugins from current config"
        read -p "Selection [1-2]: " -n 1 -r
        echo

        case "${REPLY}" in
            1)
                echo_log "INFO" "Restoring daemon config from backup..."
                cp "${DAEMON_CONFIG}${BACKUP_SUFFIX}" "${DAEMON_CONFIG}"
                echo_log "SUCCESS" "Daemon config restored from backup"
                ;;
            2|*)
                echo_log "INFO" "Removing authorization-plugins from current config..."
                if [[ -f "${DAEMON_CONFIG}" ]]; then
                    jq 'del(.["authorization-plugins"])' "${DAEMON_CONFIG}" > "${DAEMON_CONFIG}.tmp"
                    mv "${DAEMON_CONFIG}.tmp" "${DAEMON_CONFIG}"
                    echo_log "SUCCESS" "authorization-plugins removed"
                fi
                ;;
        esac
    else
        echo_log "INFO" "No backup found, removing authorization-plugins from current config..."
        if [[ -f "${DAEMON_CONFIG}" ]]; then
            jq 'del(.["authorization-plugins"])' "${DAEMON_CONFIG}" > "${DAEMON_CONFIG}.tmp"
            mv "${DAEMON_CONFIG}.tmp" "${DAEMON_CONFIG}"
            echo_log "SUCCESS" "authorization-plugins removed"
        fi
    fi

    # Restart Docker
    restart_docker

    # Ask about removing binary and policies
    echo ""
    echo_log "WARNING" "OPA binary and policies are still present on the system"
    echo ""
    read -p "Remove OPA binary (${OPA_BINARY})? [y/N] " -n 1 -r
    echo
    if [[ "${REPLY}" =~ ^[Yy]$ ]]; then
        rm -f "${OPA_BINARY}"
        echo_log "SUCCESS" "OPA binary removed"
    else
        echo_log "INFO" "OPA binary kept at: ${OPA_BINARY}"
    fi

    echo ""
    read -p "Remove OPA policies (${POLICY_DIR})? [y/N] " -n 1 -r
    echo
    if [[ "${REPLY}" =~ ^[Yy]$ ]]; then
        rm -rf "${POLICY_DIR}"
        echo_log "SUCCESS" "OPA policies removed"
    else
        echo_log "INFO" "OPA policies kept at: ${POLICY_DIR}"
    fi

    echo ""
    echo_log "SUCCESS" "OPA uninstalled. Docker is now using default authorization."
}

# Main installation function
main_install() {
    echo ""
    echo "=========================================="
    log_info "OPA Docker Authorization Installer"
    echo "=========================================="
    echo ""

    check_root
    check_prerequisites

    echo ""
    install_opa_binary

    echo ""
    create_opa_policy

    echo ""
    install_docker_plugin

    echo ""
    configure_docker_daemon

    echo ""
    restart_docker

    echo ""
    if test_opa_configuration; then
        echo ""
        echo "=========================================="
        log_success "OPA Installation Complete!"
        echo "=========================================="
        echo ""
        log_info "What's blocked:"
        echo "  - docker run --pid=host ..."
        echo "  - docker run --pid=container:name ..."
        echo ""
        log_info "What still works:"
        echo "  - docker run (normal containers)"
        echo "  - docker run --privileged (if needed)"
        echo "  - docker ps, images, etc. (all read operations)"
        echo ""
        log_info "Documentation:"
        echo "  - Policy file: ${POLICY_FILE}"
        echo "  - Security docs: ~/docs/SECURITY_MODEL.md"
        echo "  - Daemon hardening: ~/docs/docker_daemon_hardening.md"
        echo ""
        log_info "To customize policy, edit: ${POLICY_FILE}"
        log_info "Then restart Docker: sudo systemctl restart docker"
        echo ""
    else
        log_error "Installation completed but tests failed"
        log_warning "Check Docker logs: sudo journalctl -xeu docker"
        exit 1
    fi
}

# Main script
main() {
    # Parse arguments
    if [[ "${1:-}" == "--uninstall" ]]; then
        check_root
        uninstall_opa
        exit 0
    elif [[ "${1:-}" == "--status" ]]; then
        show_status
        exit 0
    elif [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
        echo "Usage: sudo $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  (no args)     Install and configure OPA"
        echo "  --uninstall   Remove OPA and restore default Docker authorization"
        echo "  --status      Show current OPA installation status"
        echo "  --help, -h    Show this help message"
        echo ""
        echo "Examples:"
        echo "  sudo $0                    # Install OPA"
        echo "  sudo $0 --status           # Check status"
        echo "  sudo $0 --uninstall        # Remove OPA"
        exit 0
    fi

    # Default action: install
    main_install
}

# Run main function
main "$@"

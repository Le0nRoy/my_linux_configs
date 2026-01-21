#!/bin/bash
# Purpose: Install Windows game from exe installer using Proton
# Usage: proton_install_game.bash <path_to_installer.exe> [game_name]
#
# This script:
# 1. Creates a Wine prefix for the game
# 2. Runs the installer using Proton
# 3. Outputs instructions for adding the game to Steam
#
# Requirements:
# - Steam with Proton installed
# - The installer .exe file

set -euo pipefail

# Configuration
STEAM_ROOT="${STEAM_ROOT:-${HOME}/.steam/steam}"
GAMES_PREFIX_DIR="${GAMES_PREFIX_DIR:-${HOME}/.local/share/proton_prefixes}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

echo_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

echo_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

show_usage() {
    cat << EOF
Usage: $(basename "$0") <installer.exe> [game_name]

Arguments:
    installer.exe   Path to the Windows installer executable
    game_name       Optional name for the game (used for prefix directory)
                    If not provided, derived from installer filename

Options:
    -p, --proton VERSION    Specify Proton version (e.g., "Proton 9.0", "GE-Proton8-25")
    -l, --list-proton       List available Proton versions
    -i, --info              Show all paths and configuration without installing
    -h, --help              Show this help message

Examples:
    $(basename "$0") ~/Downloads/HeroesSetup.exe "Heroes 3"
    $(basename "$0") -p "Proton 9.0" installer.exe
    $(basename "$0") --list-proton
    $(basename "$0") --info

Environment Variables:
    STEAM_ROOT          Steam installation directory (default: ~/.steam/steam)
    GAMES_PREFIX_DIR    Where to store game prefixes (default: ~/.local/share/proton_prefixes)
EOF
}

find_proton_versions() {
    local -a proton_paths=()

    # Check Steam common directory
    local steam_common="${STEAM_ROOT}/steamapps/common"
    if [[ -d "${steam_common}" ]]; then
        while IFS= read -r -d '' dir; do
            if [[ -f "${dir}/proton" ]]; then
                proton_paths+=("${dir}")
            fi
        done < <(find "${steam_common}" -maxdepth 1 -type d -iname "*proton*" -print0 2>/dev/null)
    fi

    # Check compatibility tools directory
    local compat_tools="${STEAM_ROOT}/compatibilitytools.d"
    if [[ -d "${compat_tools}" ]]; then
        while IFS= read -r -d '' dir; do
            if [[ -f "${dir}/proton" ]]; then
                proton_paths+=("${dir}")
            fi
        done < <(find "${compat_tools}" -maxdepth 1 -type d -print0 2>/dev/null)
    fi

    # Also check ~/.steam/root if different
    local steam_root_alt="${HOME}/.steam/root"
    if [[ -d "${steam_root_alt}/steamapps/common" ]] && [[ "${steam_root_alt}" != "${STEAM_ROOT}" ]]; then
        while IFS= read -r -d '' dir; do
            if [[ -f "${dir}/proton" ]]; then
                proton_paths+=("${dir}")
            fi
        done < <(find "${steam_root_alt}/steamapps/common" -maxdepth 1 -type d -iname "*proton*" -print0 2>/dev/null)
    fi

    printf '%s\n' "${proton_paths[@]}" | sort -u
}

list_proton_versions() {
    echo_info "Searching for Proton versions..."
    echo

    local found=0
    while IFS= read -r proton_path; do
        if [[ -n "${proton_path}" ]]; then
            local version_name="${proton_path##*/}"
            echo "  ${version_name}"
            echo "    Path: ${proton_path}"
            found=1
        fi
    done < <(find_proton_versions)

    if [[ "${found}" -eq 0 ]]; then
        echo_warn "No Proton versions found."
        echo
        echo "Make sure you have Proton installed via Steam:"
        echo "  1. Open Steam"
        echo "  2. Go to Steam > Settings > Compatibility"
        echo "  3. Enable Steam Play for all titles"
        echo "  4. Select a Proton version"
        echo
        echo "Or install GE-Proton from: https://github.com/GloriousEggroll/proton-ge-custom"
        return 1
    fi

    echo
    echo_info "Use -p 'Version Name' to select a specific version"
}

show_info() {
    echo "=============================================="
    echo " Proton Installation Info"
    echo "=============================================="
    echo

    # Resolve Steam root
    local resolved_steam_root="${STEAM_ROOT}"
    if [[ -L "${STEAM_ROOT}" ]]; then
        resolved_steam_root="$(readlink -f "${STEAM_ROOT}")"
    fi
    if [[ ! -d "${resolved_steam_root}/steamapps" ]] && [[ -L "${HOME}/.steam/root" ]]; then
        resolved_steam_root="$(readlink -f "${HOME}/.steam/root")"
    fi

    echo_info "Configuration:"
    echo "  STEAM_ROOT (env):      ${STEAM_ROOT}"
    echo "  STEAM_ROOT (resolved): ${resolved_steam_root}"
    echo "  GAMES_PREFIX_DIR:      ${GAMES_PREFIX_DIR}"
    echo

    echo_info "Steam Directories:"
    echo "  steamapps:             ${resolved_steam_root}/steamapps"
    echo "  common:                ${resolved_steam_root}/steamapps/common"
    echo "  compatdata:            ${resolved_steam_root}/steamapps/compatdata"
    echo "  compatibilitytools.d:  ${resolved_steam_root}/compatibilitytools.d"
    echo

    # Check directory existence
    echo_info "Directory Status:"
    for dir in "${resolved_steam_root}" \
               "${resolved_steam_root}/steamapps" \
               "${resolved_steam_root}/steamapps/common" \
               "${resolved_steam_root}/steamapps/compatdata" \
               "${resolved_steam_root}/compatibilitytools.d" \
               "${GAMES_PREFIX_DIR}"; do
        if [[ -d "${dir}" ]]; then
            echo -e "  ${GREEN}[EXISTS]${NC} ${dir}"
        else
            echo -e "  ${RED}[MISSING]${NC} ${dir}"
        fi
    done
    echo

    echo_info "Available Proton Versions:"
    local found=0
    while IFS= read -r proton_path; do
        if [[ -n "${proton_path}" ]]; then
            local version_name="${proton_path##*/}"
            echo "  ${version_name}"
            echo "    Path: ${proton_path}"
            found=1
        fi
    done < <(find_proton_versions)

    if [[ "${found}" -eq 0 ]]; then
        echo_warn "  No Proton versions found"
    fi
    echo

    # Show existing game prefixes
    echo_info "Existing Game Prefixes:"
    if [[ -d "${GAMES_PREFIX_DIR}" ]]; then
        local prefix_count=0
        for prefix in "${GAMES_PREFIX_DIR}"/*/; do
            if [[ -d "${prefix}" ]]; then
                local prefix_name="${prefix%/}"
                prefix_name="${prefix_name##*/}"
                echo "  ${prefix_name}"
                echo "    Path: ${prefix}"
                if [[ -d "${prefix}/pfx/drive_c" ]]; then
                    echo "    C: drive exists"
                fi
                prefix_count=$((prefix_count + 1))
            fi
        done
        if [[ "${prefix_count}" -eq 0 ]]; then
            echo "  (none)"
        fi
    else
        echo "  (prefix directory does not exist)"
    fi
    echo

    echo "=============================================="
}

select_proton() {
    local requested_version="${1:-}"
    local proton_path=""

    if [[ -n "${requested_version}" ]]; then
        # User specified a version
        while IFS= read -r path; do
            if [[ "${path##*/}" == *"${requested_version}"* ]]; then
                proton_path="${path}"
                break
            fi
        done < <(find_proton_versions)

        if [[ -z "${proton_path}" ]]; then
            echo_error "Proton version '${requested_version}' not found"
            echo "Available versions:"
            list_proton_versions
            exit 1
        fi
    else
        # Auto-select: prefer GE-Proton, then latest Proton
        local -a versions=()
        mapfile -t versions < <(find_proton_versions)

        if [[ ${#versions[@]} -eq 0 ]]; then
            echo_error "No Proton versions found. Install Proton via Steam first."
            exit 1
        fi

        # Prefer GE-Proton
        for path in "${versions[@]}"; do
            if [[ "${path}" == *"GE-Proton"* ]]; then
                proton_path="${path}"
                break
            fi
        done

        # Fall back to any Proton
        if [[ -z "${proton_path}" ]]; then
            proton_path="${versions[0]}"
        fi
    fi

    echo "${proton_path}"
}

sanitize_name() {
    local name="${1}"
    # Remove extension, replace spaces/special chars with underscores
    name="${name%.exe}"
    name="${name%.EXE}"
    name="${name//[^a-zA-Z0-9_-]/_}"
    echo "${name}"
}

run_installer() {
    local installer_path="${1}"
    local game_name="${2}"
    local proton_path="${3}"

    local prefix_dir="${GAMES_PREFIX_DIR}/${game_name}"

    echo_info "Setting up Wine prefix at: ${prefix_dir}"
    mkdir -p "${prefix_dir}"

    # Set up environment for Proton
    export STEAM_COMPAT_CLIENT_INSTALL_PATH="${STEAM_ROOT}"
    export STEAM_COMPAT_DATA_PATH="${prefix_dir}"
    export WINEPREFIX="${prefix_dir}/pfx"

    # Create prefix directory structure
    mkdir -p "${prefix_dir}/pfx"

    echo_info "Using Proton: ${proton_path##*/}"
    echo_info "Running installer: ${installer_path}"
    echo
    echo_warn "The installer window should appear shortly."
    echo_warn "Install the game to the default location (usually C:\\Program Files or similar)"
    echo

    # Run the installer via Proton
    "${proton_path}/proton" run "${installer_path}"

    local exit_code=$?

    if [[ ${exit_code} -eq 0 ]]; then
        echo
        echo_success "Installation completed!"
        echo
        show_steam_instructions "${game_name}" "${prefix_dir}" "${proton_path}"
    else
        echo_error "Installer exited with code ${exit_code}"
        return ${exit_code}
    fi
}

show_steam_instructions() {
    local game_name="${1}"
    local prefix_dir="${2}"
    local proton_path="${3}"

    echo "=============================================="
    echo " Next Steps: Adding the Game to Steam"
    echo "=============================================="
    echo
    echo "1. Find the game executable:"
    echo "   ls -la '${prefix_dir}/pfx/drive_c/Program Files/'"
    echo "   ls -la '${prefix_dir}/pfx/drive_c/Program Files (x86)/'"
    echo "   ls -la '${prefix_dir}/pfx/drive_c/GOG Games/'"
    echo
    echo "2. Add as Non-Steam Game:"
    echo "   - Open Steam"
    echo "   - Games > Add a Non-Steam Game to My Library"
    echo "   - Click 'Browse' and navigate to the .exe file"
    echo "   - Add the game"
    echo
    echo "3. Configure Launch Options:"
    echo "   - Right-click the game > Properties"
    echo "   - Set Launch Options to:"
    echo
    echo "   STEAM_COMPAT_DATA_PATH=\"${prefix_dir}\" %command%"
    echo
    echo "4. Force Proton Compatibility:"
    echo "   - Right-click the game > Properties > Compatibility"
    echo "   - Check 'Force the use of a specific Steam Play compatibility tool'"
    echo "   - Select: ${proton_path##*/}"
    echo
    echo "=============================================="
    echo
    echo_info "Game prefix location: ${prefix_dir}"
    echo_info "Wine prefix (C: drive): ${prefix_dir}/pfx/drive_c/"
}

# Parse arguments
PROTON_VERSION=""
INSTALLER_PATH=""
GAME_NAME=""

while [[ $# -gt 0 ]]; do
    case "${1}" in
        -h|--help)
            show_usage
            exit 0
            ;;
        -l|--list-proton)
            list_proton_versions
            exit 0
            ;;
        -i|--info)
            show_info
            exit 0
            ;;
        -p|--proton)
            PROTON_VERSION="${2:-}"
            if [[ -z "${PROTON_VERSION}" ]]; then
                echo_error "Option -p requires a Proton version name"
                exit 1
            fi
            shift 2
            ;;
        -*)
            echo_error "Unknown option: ${1}"
            show_usage
            exit 1
            ;;
        *)
            if [[ -z "${INSTALLER_PATH}" ]]; then
                INSTALLER_PATH="${1}"
            elif [[ -z "${GAME_NAME}" ]]; then
                GAME_NAME="${1}"
            else
                echo_error "Too many arguments"
                show_usage
                exit 1
            fi
            shift
            ;;
    esac
done

# Validate installer path
if [[ -z "${INSTALLER_PATH}" ]]; then
    echo_error "Installer path is required"
    show_usage
    exit 1
fi

if [[ ! -f "${INSTALLER_PATH}" ]]; then
    echo_error "Installer file not found: ${INSTALLER_PATH}"
    exit 1
fi

# Get absolute path
INSTALLER_PATH="$(realpath "${INSTALLER_PATH}")"

# Derive game name if not provided
if [[ -z "${GAME_NAME}" ]]; then
    GAME_NAME="$(sanitize_name "$(basename "${INSTALLER_PATH}")")"
fi

# Resolve STEAM_ROOT if it's a symlink
if [[ -L "${STEAM_ROOT}" ]]; then
    STEAM_ROOT="$(readlink -f "${STEAM_ROOT}")"
fi

# Also try ~/.steam/root as fallback
if [[ ! -d "${STEAM_ROOT}/steamapps" ]]; then
    if [[ -L "${HOME}/.steam/root" ]]; then
        STEAM_ROOT="$(readlink -f "${HOME}/.steam/root")"
    fi
fi

echo_info "Steam root: ${STEAM_ROOT}"
echo_info "Game name: ${GAME_NAME}"
echo_info "Installer: ${INSTALLER_PATH}"
echo

# Find Proton
PROTON_PATH="$(select_proton "${PROTON_VERSION}")"
if [[ -z "${PROTON_PATH}" ]]; then
    echo_error "Could not find a suitable Proton version"
    exit 1
fi

# Run the installer
run_installer "${INSTALLER_PATH}" "${GAME_NAME}" "${PROTON_PATH}"

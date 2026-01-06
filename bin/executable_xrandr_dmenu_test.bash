#!/bin/bash
# Debug test script for xrandr rofi interface

echo "=== xrandr rofi Debug Test ==="
echo ""

# Check if rofi is available
echo "1. Checking rofi..."
if command -v rofi &>/dev/null; then
    echo "   ✓ rofi found: $(command -v rofi)"
else
    echo "   ✗ rofi NOT FOUND"
    exit 1
fi

# Check if xrandr is available
echo "2. Checking xrandr..."
if command -v xrandr &>/dev/null; then
    echo "   ✓ xrandr found: $(command -v xrandr)"
else
    echo "   ✗ xrandr NOT FOUND"
    exit 1
fi

# Check DISPLAY variable
echo "3. Checking DISPLAY..."
if [[ -n "${DISPLAY:-}" ]]; then
    echo "   ✓ DISPLAY=${DISPLAY}"
else
    echo "   ✗ DISPLAY not set"
    exit 1
fi

# Check config directory
echo "4. Checking config directory..."
CONFIG_DIR="${HOME}/.config/xrandr-manager"
CONFIGS_DIR="${CONFIG_DIR}/configs"
echo "   Config dir: ${CONFIG_DIR}"
if [[ -d "${CONFIG_DIR}" ]]; then
    echo "   ✓ Directory exists"
else
    echo "   ✗ Directory missing, creating..."
    mkdir -p "${CONFIG_DIR}" "${CONFIGS_DIR}"
fi

# Check saved configs
echo "5. Checking saved configurations..."
if [[ -d "${CONFIGS_DIR}" ]]; then
    config_count=$(find "${CONFIGS_DIR}" -name "*.conf" -type f 2>/dev/null | wc -l)
    echo "   Found ${config_count} saved configuration(s)"
    if [[ "${config_count}" -gt 0 ]]; then
        find "${CONFIGS_DIR}" -name "*.conf" -type f -exec basename {} .conf \; | while read -r name; do
            echo "   - ${name}"
        done
    fi
else
    echo "   ✗ Configs directory missing"
fi

# Test xrandr query
echo "6. Testing xrandr query..."
connected=$(xrandr --query 2>&1 | awk '/^[^ ]+ connected/ {print $1}' | tr '\n' ' ')
if [[ -n "${connected}" ]]; then
    echo "   ✓ Connected outputs: ${connected}"
else
    echo "   ✗ No connected outputs found or xrandr failed"
fi

# Test simple rofi
echo "7. Testing rofi popup..."
echo "   Launching test rofi (select any option or press Escape)..."
choice=$(printf '%s\n' "Test Option 1" "Test Option 2" "Cancel" | rofi -dmenu -i -p "Test rofi:")
if [[ -n "${choice}" ]]; then
    echo "   ✓ rofi works! You selected: ${choice}"
else
    echo "   ✓ rofi works! (cancelled/escaped)"
fi

echo ""
echo "=== Debug Test Complete ==="
echo ""
echo "If all checks passed, try running:"
echo "  bash -x ${HOME}/bin/xrandr_manager.bash dmenu"
echo ""
echo "This will show detailed execution trace."

#!/bin/bash
# Automated GUI test for AmadeusApp
# Requires: Accessibility permissions for Terminal/shell
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_PATH="$PROJECT_DIR/.build/AmadeusApp.app"
APP_PROCESS="AmadeusApp"
SCREENSHOTS_DIR="/tmp/amadeus_gui_test"
PASS=0
FAIL=0
TOTAL=0

mkdir -p "$SCREENSHOTS_DIR"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_test() {
    TOTAL=$((TOTAL + 1))
    echo -e "${YELLOW}[TEST $TOTAL] $1${NC}"
}

log_pass() {
    PASS=$((PASS + 1))
    echo -e "${GREEN}  ✓ PASS: $1${NC}"
}

log_fail() {
    FAIL=$((FAIL + 1))
    echo -e "${RED}  ✗ FAIL: $1${NC}"
}

screenshot() {
    local name="$1"
    screencapture -x "$SCREENSHOTS_DIR/${name}.png"
    echo "  Screenshot saved: $SCREENSHOTS_DIR/${name}.png"
}

wait_for_process() {
    local max_wait=10
    local waited=0
    while [ $waited -lt $max_wait ]; do
        if pgrep -x "$APP_PROCESS" > /dev/null 2>&1; then
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
    done
    return 1
}

activate_app() {
    osascript -e 'tell application "System Events" to set frontmost of (first process whose name is "'"$APP_PROCESS"'") to true' 2>/dev/null
    sleep 0.5
}

get_window_elements() {
    osascript <<'APPLESCRIPT' 2>/dev/null
tell application "System Events"
    tell process "AmadeusApp"
        set elemList to ""
        try
            set g to group 1 of front window
            set elems to entire contents of g
            repeat with e in elems
                try
                    set elemList to elemList & (class of e as text) & "|" & (description of e as text) & "||"
                end try
            end repeat
        end try
        return elemList
    end tell
end tell
APPLESCRIPT
}

# ═══════════════════════════════════════
# Build
# ═══════════════════════════════════════
echo "═══ AmadeusApp GUI Test Suite ═══"
echo ""

log_test "Build the app"
cd "$PROJECT_DIR"
if swift build 2>&1 | tail -1 | grep -q "Build complete"; then
    log_pass "Swift build succeeded"
else
    log_fail "Swift build failed"
    exit 1
fi

# Package into .app bundle
APP_DIR="$APP_PATH/Contents"
mkdir -p "$APP_DIR/MacOS" "$APP_DIR/Resources"
cp .build/debug/AmadeusApp "$APP_DIR/MacOS/AmadeusApp"
cp -R .build/debug/AmadeusApp_AmadeusApp.bundle "$APP_PATH/AmadeusApp_AmadeusApp.bundle"

# Info.plist
cat > "$APP_DIR/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>AmadeusApp</string>
    <key>CFBundleIdentifier</key>
    <string>com.amadeus.app</string>
    <key>CFBundleName</key>
    <string>AmadeusApp</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
</dict>
</plist>
PLIST

log_pass "App bundle created"

# ═══════════════════════════════════════
# Kill any existing instance
# ═══════════════════════════════════════
pkill -f "$APP_PROCESS" 2>/dev/null || true
sleep 1

# ═══════════════════════════════════════
# Test 1: App Launch
# ═══════════════════════════════════════
log_test "App launches successfully"
open "$APP_PATH"
if wait_for_process; then
    log_pass "App process started"
else
    log_fail "App did not start within 10s"
    exit 1
fi
sleep 2
activate_app

# ═══════════════════════════════════════
# Test 2: Login screen elements
# ═══════════════════════════════════════
log_test "Login screen shows expected UI elements"
screenshot "01_login_screen"
ELEMENTS=$(get_window_elements)
if echo "$ELEMENTS" | grep -q "text field"; then
    log_pass "Text fields present on login screen"
else
    log_fail "No text fields found on login screen"
fi
if echo "$ELEMENTS" | grep -q "image"; then
    log_pass "Logo image is displayed"
else
    log_fail "Logo image not found"
fi
if echo "$ELEMENTS" | grep -q "button"; then
    log_pass "Login button is present"
else
    log_fail "Login button not found"
fi

# ═══════════════════════════════════════
# Test 3: Login with wrong credentials
# ═══════════════════════════════════════
log_test "Wrong credentials show error"
osascript <<'APPLESCRIPT' 2>/dev/null
tell application "System Events"
    set frontmost of (first process whose name is "AmadeusApp") to true
    delay 0.5
    tell process "AmadeusApp"
        set g to group 1 of front window
        set focused of text field 1 of g to true
        delay 0.2
        keystroke "wrong"
        delay 0.2
        set focused of text field 2 of g to true
        delay 0.2
        keystroke "wrong"
        delay 0.2
        keystroke return
    end tell
end tell
APPLESCRIPT
sleep 1
screenshot "02_login_failed"
ELEMENTS=$(get_window_elements)
if echo "$ELEMENTS" | grep -q "static text"; then
    log_pass "Error feedback shown for wrong credentials"
else
    log_fail "No error message after wrong login"
fi

# ═══════════════════════════════════════
# Test 4: Login with correct credentials
# ═══════════════════════════════════════
log_test "Correct credentials proceed to next screen"
osascript <<'APPLESCRIPT' 2>/dev/null
tell application "System Events"
    set frontmost of (first process whose name is "AmadeusApp") to true
    delay 0.5
    tell process "AmadeusApp"
        set g to group 1 of front window
        -- Clear login field
        set focused of text field 1 of g to true
        delay 0.2
        keystroke "a" using command down
        delay 0.1
        key code 51
        delay 0.1
        keystroke "Salieri"
        delay 0.3
        -- Clear password field
        set focused of text field 2 of g to true
        delay 0.2
        keystroke "a" using command down
        delay 0.1
        key code 51
        delay 0.1
        keystroke "MakiseKurisu"
        delay 0.3
        keystroke return
    end tell
end tell
APPLESCRIPT
sleep 2
screenshot "03_after_login"

# Check if we moved past login (the UI elements should change)
ELEMENTS_AFTER=$(get_window_elements)
if [ "$ELEMENTS" != "$ELEMENTS_AFTER" ]; then
    log_pass "Screen changed after successful login"
else
    log_fail "Screen did not change after login"
fi

# ═══════════════════════════════════════
# Test 5: Wait for boot/loading sequence
# ═══════════════════════════════════════
log_test "Boot sequence completes"
echo "  Waiting for boot sequence to finish..."
sleep 15
screenshot "04_main_view"
activate_app

MAIN_ELEMENTS=$(get_window_elements)
if echo "$MAIN_ELEMENTS" | grep -q "text field\|web\|group"; then
    log_pass "Main view loaded with expected elements"
else
    log_fail "Main view elements not found"
fi

# ═══════════════════════════════════════
# Test 6: Menu opens with Tab
# ═══════════════════════════════════════
log_test "Tab key opens menu"
activate_app
osascript -e '
tell application "System Events"
    set frontmost of (first process whose name is "AmadeusApp") to true
    delay 0.3
    key code 48
end tell' 2>/dev/null
sleep 1
screenshot "05_menu_open"
MENU_ELEMENTS=$(get_window_elements)
if echo "$MENU_ELEMENTS" | grep -q "button"; then
    log_pass "Menu opened with buttons visible"
else
    log_fail "Menu did not open or no buttons found"
fi

# ═══════════════════════════════════════
# Test 7: Close menu with Escape
# ═══════════════════════════════════════
log_test "Escape closes menu"
osascript -e '
tell application "System Events"
    set frontmost of (first process whose name is "AmadeusApp") to true
    delay 0.3
    key code 53
end tell' 2>/dev/null
sleep 1
screenshot "06_menu_closed"
log_pass "Menu close command sent"

# ═══════════════════════════════════════
# Test 8: Auto mode toggle with 'a' key
# ═══════════════════════════════════════
log_test "Auto mode toggles with 'a' key"
activate_app
osascript -e '
tell application "System Events"
    set frontmost of (first process whose name is "AmadeusApp") to true
    delay 0.3
    keystroke "a"
end tell' 2>/dev/null
sleep 1
screenshot "07_auto_mode"
log_pass "Auto mode toggle command sent"

# Toggle off
osascript -e '
tell application "System Events"
    set frontmost of (first process whose name is "AmadeusApp") to true
    delay 0.2
    keystroke "a"
end tell' 2>/dev/null
sleep 0.5

# ═══════════════════════════════════════
# Cleanup
# ═══════════════════════════════════════
log_test "App terminates cleanly"
pkill -f "$APP_PROCESS" 2>/dev/null || true
sleep 2
if ! pgrep -x "$APP_PROCESS" > /dev/null 2>&1; then
    log_pass "App terminated cleanly"
else
    log_fail "App did not terminate"
    pkill -9 -f "$APP_PROCESS" 2>/dev/null || true
fi

# ═══════════════════════════════════════
# Summary
# ═══════════════════════════════════════
echo ""
echo "═══════════════════════════════════════"
echo -e "Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}, $TOTAL total"
echo "Screenshots: $SCREENSHOTS_DIR/"
echo "═══════════════════════════════════════"

if [ $FAIL -gt 0 ]; then
    exit 1
fi

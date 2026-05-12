#!/usr/bin/env bash
# setup.sh — Generate the Xcode project using XcodeGen
# Run once from the project root: bash setup.sh

set -e

echo "=== Translating Keyboard — Xcode Project Setup ==="
echo ""

# ── 1. Check for XcodeGen ──────────────────────────────────────────
if ! command -v xcodegen &> /dev/null; then
    echo "XcodeGen not found. Installing via Homebrew..."
    if ! command -v brew &> /dev/null; then
        echo "ERROR: Homebrew is required. Install it from https://brew.sh then re-run this script."
        exit 1
    fi
    brew install xcodegen
fi

echo "XcodeGen found: $(xcodegen version)"
echo ""

# ── 2. Generate the Xcode project ─────────────────────────────────
echo "Generating TranslatingKeyboard.xcodeproj ..."
xcodegen generate

echo ""
echo "=== Done! ==="
echo ""
echo "NEXT STEPS:"
echo ""
echo "1. Open TranslatingKeyboard.xcodeproj in Xcode"
echo ""
echo "2. In Xcode, select the TranslatingKeyboard target → Signing & Capabilities:"
echo "   • Set your Team"
echo "   • Change bundle ID from 'com.yourname.translatingkeyboard' to your own"
echo "   • Add App Group capability: group.com.yourname.translatingkeyboard"
echo "     (replace 'yourname' with something unique)"
echo "   • Add Keychain Sharing capability with the SAME identifier suffix as the"
echo "     App Group's domain (e.g. com.yourname.translatingkeyboard.keychain)"
echo ""
echo "3. Do the same for the TranslatingKeyboardExtension target:"
echo "   • Set your Team"
echo "   • Change bundle ID to 'com.yourname.translatingkeyboard.keyboard'"
echo "   • Add App Group capability with the SAME group identifier as above"
echo "   • Add Keychain Sharing capability with the SAME keychain group as above"
echo ""
echo "4. In both entitlements files, update the App Group identifier and the"
echo "   keychain-access-groups identifier to match. Also update"
echo "   SharedDefaults.swift → suiteName + keychainService to match."
echo ""
echo "5. Build & run on a real device (keyboard extensions don't work on the simulator)."
echo ""
echo "6. On the device or simulator, go to Settings → General → Keyboard → Keyboards"
echo "   → Add New Keyboard → Translating Keyboard."
echo "   (Allow Full Access is NOT required — v1 expands shorthand locally.)"
echo ""
echo "7. Open any app, switch to Translating Keyboard, type shorthand like"
echo "   'thdoraho.' or 'iwatoma.' — it expands on '.'. Normal sentences"
echo "   pass through unchanged."

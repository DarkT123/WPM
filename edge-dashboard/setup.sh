#!/usr/bin/env bash
# setup.sh — Generate the EdgeDashboard Xcode project using XcodeGen.
# Run from this directory: bash setup.sh
set -e

echo "=== EdgeDashboard — Xcode Project Setup ==="

if ! command -v xcodegen &> /dev/null; then
    echo "XcodeGen not found. Installing via Homebrew..."
    if ! command -v brew &> /dev/null; then
        echo "ERROR: Homebrew is required. Install it from https://brew.sh then re-run this script."
        exit 1
    fi
    brew install xcodegen
fi

echo "XcodeGen: $(xcodegen version)"
echo "Generating EdgeDashboard.xcodeproj ..."
xcodegen generate

echo ""
echo "=== Done ==="
echo ""
echo "Next steps:"
echo "  1. In a separate terminal, start the Edge backend:"
echo "       cd ../edge && npm install && npm run dev"
echo "     (backend on http://localhost:3002)"
echo ""
echo "  2. Open EdgeDashboard.xcodeproj in Xcode."
echo "  3. In the target's Signing & Capabilities, set your Team and"
echo "     adjust the bundle identifier from 'com.yourname.edge.dashboard'."
echo "  4. Build & run (Cmd+R). The app talks to http://localhost:3002 by"
echo "     default — change in Settings → Backend URL if you've remapped it."

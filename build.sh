#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
arch="$(uname -m)"
sdk="$(xcrun --sdk macosx --show-sdk-path)"
app="dist/WeChatSave.app"
work="$(mktemp -d "$PWD/.build.XXXXXXXX")"
trap 'rm -rf "$work"' EXIT
bundle="$work/WeChatSave.app"
extension="$bundle/Contents/PlugIns/WeChatSaveShare.appex"

mkdir -p "$bundle/Contents/MacOS" "$extension/Contents/MacOS" dist
compiler=(xcrun swiftc -O -enable-bare-slash-regex -parse-as-library -sdk "$sdk" -target "$arch-apple-macosx14.0"
    -module-cache-path "$work/module-cache")
"${compiler[@]}" -module-name WeChatSave Sources/WeChatSave.swift \
    -o "$bundle/Contents/MacOS/WeChatSave"
"${compiler[@]}" -module-name WeChatSaveShare -application-extension \
    -Xlinker -e -Xlinker _NSExtensionMain \
    Sources/ExtensionEntry.swift Sources/ShareViewController.swift Sources/ZIPAttachment.swift Sources/ChatExportName.swift \
    -o "$extension/Contents/MacOS/WeChatSaveShare"

cp Resources/App.plist "$bundle/Contents/Info.plist"
cp Resources/Share.plist "$extension/Contents/Info.plist"
identity="${SIGNING_IDENTITY:--}"
codesign --force --sign "$identity" --entitlements Resources/Share.entitlements "$extension"
codesign --force --sign "$identity" --entitlements Resources/Sandbox.entitlements "$bundle"
codesign --verify --deep --strict "$bundle"
if [[ -e "$app" ]]; then
    mv "$app" "$work/Previous.app"
fi
if ! mv "$bundle" "$app"; then
    if [[ -e "$work/Previous.app" ]]; then
        mv "$work/Previous.app" "$app"
    fi
    exit 1
fi
printf '%s\n' "$PWD/$app"

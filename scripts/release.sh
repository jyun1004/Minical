#!/bin/zsh
# Builds Minical for distribution outside the App Store: signed with a Developer ID, notarized by
# Apple and stapled, in a DMG at dist/Minical-<version>.dmg, with the Sparkle feed that offers it
# as an update (dist/appcast.xml, its download signed with the key in the keychain).
#
#   scripts/release.sh [--publish] [version]
#
# version defaults to MARKETING_VERSION in project.yml. The build number is the time of the build.
# --publish uploads both to a GitHub release v<version> of REPO, where the app's feed
# (SUFeedURL in project.yml) finds them; the latest release is the one offered.
#
# Needs, once:
#   - a "Developer ID Application" certificate in the login keychain
#   - notary credentials stored under the profile named by NOTARY_PROFILE (default minical-notary):
#       xcrun notarytool store-credentials minical-notary --apple-id <id> --team-id <team> --password <app-specific password>
#
# Environment:
#   SIGN_IDENTITY   the signing identity (default: the first Developer ID Application one found).
#                   "-" signs ad hoc and skips notarization, to try the packaging alone.
#   NOTARY_PROFILE  the notarytool keychain profile (default minical-notary).
#   REPO            the GitHub repository releases go to (default jyun1004/Minical).
set -euo pipefail

publish=0
if [[ "${1:-}" == "--publish" ]]; then
    publish=1
    shift
fi

cd "${0:a:h}/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

version="${1:-$(sed -n 's/^ *MARKETING_VERSION: *"\(.*\)"/\1/p' project.yml)}"
build="$(date +%Y%m%d%H%M)"
notary_profile="${NOTARY_PROFILE:-minical-notary}"
repo="${REPO:-jyun1004/Minical}"
sparkle_bin="$PWD/build/release/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin"

identity="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)}"
if [[ -z "$identity" ]]; then
    print -u2 "No Developer ID Application certificate in the keychain (see the top of this script)."
    exit 1
fi
adhoc=0
# The hardened runtime notarization needs; signed ad hoc it won't load Sparkle (no team ID to match).
runtime=YES
if [[ "$identity" == "-" ]]; then
    adhoc=1
    runtime=NO
    team=""
    print "Signing ad hoc: the DMG won't be notarized and Gatekeeper will block it on other Macs."
else
    # "Developer ID Application: Name (TEAMID)"
    team="${${identity##*\(}%\)}"
    if [[ $adhoc == 0 ]] && ! xcrun notarytool history --keychain-profile "$notary_profile" >/dev/null 2>&1; then
        print -u2 "No notary credentials under the profile \"$notary_profile\" (see the top of this script)."
        exit 1
    fi
fi

work="build/release"
archive="$work/Minical.xcarchive"
app="$work/Minical.app"
dmg="dist/Minical-$version.dmg"
rm -rf "$work"
mkdir -p "$work" dist

print "==> Minical $version ($build), signed by: $identity"

xcodegen generate --quiet
xcodebuild archive \
    -project Minical.xcodeproj -scheme Minical -configuration Release \
    -destination "generic/platform=macOS" -archivePath "$archive" -derivedDataPath "$work/DerivedData" \
    MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build" \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$identity" DEVELOPMENT_TEAM="$team" \
    ENABLE_HARDENED_RUNTIME="$runtime" \
    OTHER_CODE_SIGN_FLAGS="--timestamp" \
    | grep -E "error:|warning: .*sign|ARCHIVE (SUCCEEDED|FAILED)" || true
[[ -d "$archive/Products/Applications/Minical.app" ]] || { print -u2 "Archive failed."; exit 1; }
ditto "$archive/Products/Applications/Minical.app" "$app"

# Sparkle's helpers (its installer and downloader services, the updater) keep the signature they
# came with: signed again as ours, inside out, then the app over them with its own entitlements.
print "==> Signing Sparkle's helpers"
sparkle="$app/Contents/Frameworks/Sparkle.framework/Versions/B"
codesign -d --entitlements - --xml "$app" > "$work/Minical.entitlements" 2>/dev/null
sign() {
    if [[ $adhoc == 1 ]]; then
        codesign --force --sign - "$@"
    else
        codesign --force --sign "$identity" --options runtime --timestamp "$@"
    fi
}
sign "$sparkle/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$sparkle/XPCServices/Downloader.xpc"
sign "$sparkle/Autoupdate"
sign "$sparkle/Updater.app"
sign "$app/Contents/Frameworks/Sparkle.framework"
sign --entitlements "$work/Minical.entitlements" "$app"

print "==> Checking the signature"
codesign --verify --deep --strict --verbose=2 "$app"
codesign -d --entitlements - "$app" 2>/dev/null | grep -q "com.apple.security.app-sandbox" \
    || { print -u2 "The app lost its sandbox entitlement."; exit 1; }

notarize() {
    print "==> Notarizing $1"
    xcrun notarytool submit "$1" --keychain-profile "$notary_profile" --wait --timeout 30m
    xcrun stapler staple "$2"
}

if [[ $adhoc == 0 ]]; then
    ditto -c -k --keepParent "$app" "$work/Minical.zip"
    notarize "$work/Minical.zip" "$app"
fi

print "==> Packaging $dmg"
stage="$work/dmg"
mkdir -p "$stage"
ditto "$app" "$stage/Minical.app"
ln -s /Applications "$stage/Applications"
rm -f "$dmg"
hdiutil create -volname "Minical" -srcfolder "$stage" -fs HFS+ -format UDZO -ov "$dmg" >/dev/null

if [[ $adhoc == 0 ]]; then
    codesign --sign "$identity" --timestamp "$dmg"
    notarize "$dmg" "$dmg"
    print "==> Gatekeeper"
    spctl --assess --type execute --verbose=2 "$app"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
fi

print "==> Writing dist/appcast.xml"
url="https://github.com/$repo/releases/download/v$version/${dmg:t}"
signature="$("$sparkle_bin/sign_update" "$dmg")"
minimum="$(/usr/libexec/PlistBuddy -c "Print LSMinimumSystemVersion" "$app/Contents/Info.plist")"
cat > dist/appcast.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Minical</title>
    <item>
      <title>Minical $version</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$minimum</sparkle:minimumSystemVersion>
      <enclosure url="$url" type="application/octet-stream" $signature />
    </item>
  </channel>
</rss>
XML

if [[ $publish == 1 ]]; then
    if [[ $adhoc == 1 ]]; then
        print -u2 "Not publishing an ad hoc build."
        exit 1
    fi
    print "==> Publishing v$version to $repo"
    # Tagged at the commit built, which must be pushed.
    gh release create "v$version" "$dmg" dist/appcast.xml --repo "$repo" --target "$(git rev-parse HEAD)" \
        --title "Minical $version" --notes ""
fi

print "==> Done: $dmg"

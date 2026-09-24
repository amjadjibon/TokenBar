#!/bin/bash
#
# Build, sign, notarise and package TokenBar for distribution.
#
#   ./scripts/release.sh 1.1.0                 build + notarise a DMG
#   ./scripts/release.sh 1.1.0 --publish       …and create the GitHub release
#   ./scripts/release.sh 1.1.0 --publish --tap amjadjibon/homebrew-tap
#   ./scripts/release.sh 1.1.0 --skip-notarize local check only, NOT shippable
#
# Versions are passed to xcodebuild rather than written into the project, so a
# release never leaves the working tree dirty and the same commit can be rebuilt
# byte-for-byte.
set -euo pipefail

readonly SCHEME="TokenBar"
readonly APP="TokenBar.app"
readonly TEAM_ID="PPQFDGVAM2"
readonly BUNDLE_ID="com.amjadjibon.TokenBar"
# Created once, by you, with:
#   xcrun notarytool store-credentials tokenbar-notary \
#     --apple-id <your-apple-id> --team-id PPQFDGVAM2
readonly NOTARY_PROFILE="tokenbar-notary"

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly BUILD="$ROOT/build"

VERSION=""
PUBLISH=false
SKIP_NOTARIZE=false
ALLOW_DIRTY=false
TAP=""

die() { printf '\nerror: %s\n' "$*" >&2; exit 1; }
step() { printf '\n==> %s\n' "$*"; }

usage() {
    sed -n '3,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit "${1:-1}"
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --publish)        PUBLISH=true ;;
            --skip-notarize)  SKIP_NOTARIZE=true ;;
            --allow-dirty)    ALLOW_DIRTY=true ;;
            --tap)
                [ $# -ge 2 ] || die "--tap needs an owner/repo argument"
                TAP="$2"
                shift ;;
            -h|--help)        usage 0 ;;
            -*)               die "unknown option: $1" ;;
            *)                [ -z "$VERSION" ] || die "version given twice"; VERSION="$1" ;;
        esac
        shift
    done

    [ -n "$VERSION" ] || usage
    # Semver keeps the git tag, the DMG name and any Homebrew cask agreeing.
    [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must look like 1.2.3, got '$VERSION'"
    if [ -n "$TAP" ]; then
        $PUBLISH || die "--tap requires --publish"
        [[ "$TAP" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "--tap must look like owner/repo"
    fi
}

preflight() {
    step "Preflight"

    command -v xcodebuild >/dev/null || die "xcodebuild not found — install Xcode"

    if ! $ALLOW_DIRTY && [ -n "$(git -C "$ROOT" status --porcelain)" ]; then
        die "working tree is dirty; commit first or pass --allow-dirty"
    fi

    if git -C "$ROOT" rev-parse "v$VERSION" >/dev/null 2>&1; then
        die "tag v$VERSION already exists"
    fi

    if $SKIP_NOTARIZE; then
        printf '  ! --skip-notarize: Gatekeeper will block this build until quarantine is removed\n'
        return
    fi

    # A Developer ID Application certificate is the one thing that cannot be
    # worked around: without it Gatekeeper rejects the app everywhere but here.
    if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
        die "no 'Developer ID Application' certificate in the keychain.
   It needs a paid Apple Developer Program membership; create it in
   Xcode > Settings > Accounts > Manage Certificates > + Developer ID Application."
    fi

    xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 ||
        die "notary profile '$NOTARY_PROFILE' not set up. Run:
   xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <you> --team-id $TEAM_ID"

    printf '  signing identity and notary profile present\n'
}

archive() {
    step "Archiving $SCHEME $VERSION (build $BUILD_NUMBER)"
    rm -rf "$BUILD"
    mkdir -p "$BUILD"

    xcodebuild -project "$ROOT/$SCHEME.xcodeproj" -scheme "$SCHEME" \
        -configuration Release -destination 'generic/platform=macOS' \
        -archivePath "$BUILD/$SCHEME.xcarchive" \
        MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
        archive
}

export_app() {
    step "Exporting"

    # Written here rather than committed: every value is derived, and the export
    # method is the difference between a local build and a shippable one.
    local method="developer-id"
    $SKIP_NOTARIZE && method="mac-application"

    cat > "$BUILD/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>$method</string>
    <key>teamID</key><string>$TEAM_ID</string>
    <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
PLIST

    xcodebuild -exportArchive -archivePath "$BUILD/$SCHEME.xcarchive" \
        -exportOptionsPlist "$BUILD/ExportOptions.plist" \
        -exportPath "$BUILD/export"
}

verify_signature() {
    step "Verifying the signature"
    local app="$BUILD/export/$APP"

    codesign --verify --strict --verbose=2 "$app"
    codesign -dvv "$app" 2>&1 | grep -E "^(Authority|TeamIdentifier|Identifier)=" | sed 's/^/  /'

    # Hardened runtime is required for notarisation, and easy to lose in a
    # settings change, so fail here rather than at Apple's end.
    if ! codesign -dvvv "$app" 2>&1 | grep -q "flags=.*runtime"; then
        $SKIP_NOTARIZE || die "hardened runtime is not enabled — notarisation would reject this"
    fi
}

notarize_app() {
    step "Notarising the app"
    local app="$BUILD/export/$APP"

    # The app is stapled in its own right, not just the DMG, so that a copy
    # dragged out of the DMG still launches on a machine that is offline.
    ditto -c -k --keepParent "$app" "$BUILD/$SCHEME-app.zip"
    xcrun notarytool submit "$BUILD/$SCHEME-app.zip" \
        --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$app"
}

make_dmg() {
    step "Building the DMG"
    local dmg="$BUILD/$SCHEME-$VERSION.dmg"
    local stage="$BUILD/dmg"

    # A symlink to /Applications makes the window a drag-and-drop install.
    rm -rf "$stage"; mkdir -p "$stage"
    cp -R "$BUILD/export/$APP" "$stage/"
    ln -s /Applications "$stage/Applications"

    hdiutil create -volname "$SCHEME" -srcfolder "$stage" \
        -ov -format UDZO "$dmg" >/dev/null

    if ! $SKIP_NOTARIZE; then
        step "Notarising the DMG"
        xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$dmg"
        xcrun stapler validate "$dmg"
    fi

    DMG="$dmg"
}

verify_gatekeeper() {
    $SKIP_NOTARIZE && return 0
    step "Checking it the way Gatekeeper will"
    spctl -a -vvv -t install "$BUILD/export/$APP"
}

publish() {
    step "Publishing v$VERSION"
    command -v gh >/dev/null || die "gh not found — install the GitHub CLI or upload $DMG by hand"

    local args=(--title "TokenBar $VERSION" --generate-notes)

    if $SKIP_NOTARIZE; then
        # Gatekeeper rejects an un-notarised build on every Mac but the one that
        # produced it. Say so in the release itself, rather than letting people
        # find out after downloading, and mark it a prerelease so it is never
        # served as "latest".
        local notes="$BUILD/notes.md"
        cat > "$notes" <<'NOTE'
> **Not notarised.** This build is signed with a development certificate, so
> macOS Gatekeeper will block it on another machine. After installing, remove
> the quarantine attribute to open it:
>
> ```sh
> xattr -dr com.apple.quarantine /Applications/TokenBar.app
> ```

NOTE
        args+=(--prerelease --notes-file "$notes")
    fi

    git -C "$ROOT" push origin HEAD:main
    git -C "$ROOT" tag -a "v$VERSION" -m "TokenBar $VERSION"
    git -C "$ROOT" push origin "v$VERSION"
    gh release create "v$VERSION" "$DMG" "${args[@]}"
}

update_tap() {
    [ -n "$TAP" ] || return 0
    step "Updating Homebrew tap $TAP"

    local checkout cask
    checkout="$(mktemp -d "${TMPDIR:-/tmp}/tokenbar-tap.XXXXXX")"
    cask="$checkout/Casks/tokenbar.rb"
    gh repo clone "$TAP" "$checkout" -- --depth 1 --quiet
    mkdir -p "$checkout/Casks"
    cat > "$cask" <<CASK
# Generated by scripts/release.sh for v$VERSION. Do not edit by hand.
cask "tokenbar" do
  version "$VERSION"
  sha256 "$(shasum -a 256 "$DMG" | awk '{print $1}')"

  url "https://github.com/amjadjibon/TokenBar/releases/download/v#{version}/TokenBar-#{version}.dmg"
  name "TokenBar"
  desc "Menu bar app for AI subscription quota usage"
  homepage "https://github.com/amjadjibon/TokenBar"

  depends_on macos: :tahoe

  app "TokenBar.app"

  uninstall quit: "$BUNDLE_ID"

  zap trash: [
    "~/Library/Application Support/TokenBar",
    "~/Library/Preferences/$BUNDLE_ID.plist",
  ]

CASK

    if $SKIP_NOTARIZE; then
        cat >> "$cask" <<'CASK'
  caveats <<~EOS
    Requires macOS 26.5 or later.
    This prerelease is not notarized. After installation, run:
      xattr -dr com.apple.quarantine /Applications/TokenBar.app
  EOS
CASK
    else
        cat >> "$cask" <<'CASK'
  caveats "Requires macOS 26.5 or later."
CASK
    fi
    printf 'end\n' >> "$cask"

    ruby -c "$cask"
    git -C "$checkout" add Casks/tokenbar.rb
    git -C "$checkout" commit -m "tokenbar $VERSION"
    git -C "$checkout" push origin HEAD
    rm -rf "$checkout"
}

main() {
    parse_args "$@"
    # Monotonic without any state to keep, and reproducible from the commit.
    BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD)"

    preflight
    archive
    export_app
    verify_signature
    $SKIP_NOTARIZE || notarize_app
    make_dmg
    verify_gatekeeper

    step "Done"
    printf '  %s\n' "$DMG"
    printf '  sha256 %s\n' "$(shasum -a 256 "$DMG" | awk '{print $1}')"

    if $PUBLISH; then
        publish
        update_tap
    else
        printf '\n  Not published. Re-run with --publish, or:\n'
        printf '    gh release create v%s "%s" --generate-notes\n' "$VERSION" "$DMG"
    fi
}

main "$@"

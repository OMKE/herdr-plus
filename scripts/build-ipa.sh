#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${HERDR_IOS_BUILD:-/tmp/hcios}"
OUT="$ROOT/build"
REPO="$OUT/repo"
BUNDLE_ID="io.github.herdr-ios.app"

mkdir -p "$OUT" "$REPO"
BUILD_FILE="$OUT/BUILD_NUMBER"
BUILD=$(( $(cat "$BUILD_FILE" 2>/dev/null || echo 1) + 1 ))
BASE_VERSION=$(grep -E '^\s*MARKETING_VERSION:' "$ROOT/App/project.yml" | head -1 | sed -E 's/.*"([0-9]+\.[0-9]+).*/\1/')
VERSION="$BASE_VERSION.$BUILD"

cd "$ROOT/App"
xcodegen generate

rm -rf "$WORK/archive.xcarchive" "$WORK/ipa"
xcodebuild archive \
  -project HerdrIOS.xcodeproj \
  -scheme HerdrIOS \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$WORK/archive.xcarchive" \
  -clonedSourcePackagesDirPath "$WORK/spm" \
  -derivedDataPath "$WORK/dd-release" \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD"

echo "$BUILD" > "$BUILD_FILE"

mkdir -p "$WORK/ipa/Payload"
cp -R "$WORK/archive.xcarchive/Products/Applications/HerdrIOS.app" "$WORK/ipa/Payload/"
cd "$WORK/ipa"
rm -f "$OUT/HerdrIOS.ipa"
zip -qry "$OUT/HerdrIOS.ipa" Payload

IPA_NAME="HerdrIOS-$VERSION.ipa"

if [ -n "${HERDR_GITHUB_REPO:-}" ]; then
  mkdir -p "$ROOT/feather"
  cp "$OUT/HerdrIOS.ipa" "$OUT/$IPA_NAME"
  SIZE=$(stat -f %z "$OUT/$IPA_NAME")
  python3 -I - "$ROOT/feather/source.json" "$HERDR_GITHUB_REPO" "$IPA_NAME" "$VERSION" "$BUILD" "$SIZE" "$BUNDLE_ID" <<'PY'
import json, os, sys, datetime
path, repo, ipa, version, build, size, bundle = sys.argv[1:]
date = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
url = f"https://github.com/{repo}/releases/download/v{version}/{ipa}"
old = []
if os.path.exists(path):
    with open(path) as f:
        old = [v for v in json.load(f)["apps"][0].get("versions", []) if v.get("version") != version]
entry = {"version": version, "buildVersion": build, "date": date, "downloadURL": url, "size": int(size), "minOSVersion": "17.0"}
app = {
    "name": "Herdr",
    "bundleIdentifier": bundle,
    "developerName": repo.split("/")[0],
    "subtitle": "Your agents, in your pocket",
    "localizedDescription": "Unofficial iPhone client for herdr-core. Connects to your Mac over Tailscale and SSH.",
    "iconURL": f"https://raw.githubusercontent.com/{repo}/main/App/Resources/Assets.xcassets/AppIcon.appiconset/icon.png",
    "tintColor": "F5A524",
    "version": version,
    "versionDate": date,
    "downloadURL": url,
    "size": int(size),
    "versions": ([entry] + old)[:10],
}
source = {"name": "herdr-plus", "identifier": bundle + ".source", "apps": [app], "news": []}
with open(path, "w") as f:
    json.dump(source, f, indent=2)
    f.write("\n")
PY
  echo "$OUT/$IPA_NAME"
  echo "version $VERSION (build $BUILD)"
  echo "tag v$VERSION"
  exit 0
fi

if [ -n "${HERDR_REPO_URL:-}" ]; then
  BASE_URL="${HERDR_REPO_URL%/}"
else
  DNS=$(tailscale status --json 2>/dev/null | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))' || true)
  BASE_URL="https://${DNS:-localhost}/herdr"
fi

find "$REPO" -maxdepth 1 -name 'HerdrIOS-*.ipa' -delete
cp "$OUT/HerdrIOS.ipa" "$REPO/$IPA_NAME"
cp "$ROOT/App/Resources/Assets.xcassets/AppIcon.appiconset/icon.png" "$REPO/icon.png"
SIZE=$(stat -f %z "$REPO/$IPA_NAME")

python3 -I - "$REPO/source.json" "$BASE_URL" "$IPA_NAME" "$VERSION" "$BUILD" "$SIZE" "$BUNDLE_ID" <<'PY'
import json, sys, datetime
path, base, ipa, version, build, size, bundle = sys.argv[1:]
date = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
url = f"{base}/{ipa}"
app = {
    "name": "Herdr",
    "bundleIdentifier": bundle,
    "developerName": "herdr-ios",
    "subtitle": "Your agents, in your pocket",
    "localizedDescription": "herdr-core on your Mac over Tailscale and SSH.",
    "iconURL": f"{base}/icon.png",
    "tintColor": "F5A524",
    "version": version,
    "versionDate": date,
    "downloadURL": url,
    "size": int(size),
    "versions": [{
        "version": version,
        "buildVersion": build,
        "date": date,
        "downloadURL": url,
        "size": int(size),
        "minOSVersion": "17.0",
    }],
}
source = {"name": "Herdr iOS", "identifier": bundle + ".source", "apps": [app], "news": []}
with open(path, "w") as f:
    json.dump(source, f, indent=2)
PY

echo "$OUT/HerdrIOS.ipa"
echo "version $VERSION (build $BUILD)"
echo "source: $BASE_URL/source.json"

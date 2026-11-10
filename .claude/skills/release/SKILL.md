---
name: release
description: Build a new herdr-plus IPA, publish it as a GitHub Release on OMKE/herdr-plus and update the Feather source (feather/source.json). Use when the user asks for a new version, a new IPA, a release, or to update Feather.
---

# Release herdr-plus

Run from the repo root (`~/Code/herdr-ios`). Pushing and creating a release are outward-facing: the user's request for a release in the current message is the go-ahead; otherwise ask first.

1. Check the tree is clean except for intended changes: `git status --short`. Commit pending work first only if the user asked for it.
2. Run the tests:
   - `cd Packages/HerdrKit && swift test`
   - UI tests are optional; run them if UI changed.
3. Build:
   ```sh
   HERDR_GITHUB_REPO=OMKE/herdr-plus scripts/build-ipa.sh
   ```
   It prints the IPA path (`build/HerdrIOS-<version>.ipa`), the version and the tag (`v<version>`), and rewrites `feather/source.json` with the release download URL. The build number lives in `build/BUILD_NUMBER` (not in git).
4. Publish the release (the asset must exist before the source points at it):
   ```sh
   gh release create v<version> build/HerdrIOS-<version>.ipa --repo OMKE/herdr-plus --title "v<version>" --notes "<one line per user-visible change>"
   ```
5. Commit and push the source:
   ```sh
   git add feather/source.json
   git commit -m "Release v<version>"
   git push
   ```
6. Verify:
   - `curl -sI -L https://github.com/OMKE/herdr-plus/releases/download/v<version>/HerdrIOS-<version>.ipa | grep -i "^HTTP"` ends with 200.
   - `curl -s https://raw.githubusercontent.com/OMKE/herdr-plus/main/feather/source.json | grep -m1 '"version"'` shows the new version (raw.githubusercontent can cache for a few minutes).
7. Tell the user the version, the release URL and that Feather picks it up from `https://raw.githubusercontent.com/OMKE/herdr-plus/main/feather/source.json`.

If `gh release create` fails, do not push `feather/source.json`; restore it with `git checkout feather/source.json`.

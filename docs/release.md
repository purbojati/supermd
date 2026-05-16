# Release process

Canonical reference for cutting a SuperMD release. The full setup story (Developer ID
cert, notarytool profile, Sparkle key) lives in the README under "Releasing & auto-update";
this doc is the focused checklist for actually performing a release and the failure modes
to watch for.

## Mental model

A SuperMD release is **four artifacts in lockstep**, all on the same version number:

1. A `Release vX.Y.Z` commit that bumps `Resources/Info.plist`
   (`CFBundleShortVersionString` + `CFBundleVersion`) and `Sources/SuperMD/SuperMDApp.swift`
   (`.applicationVersion` / `.version` in `AboutPanel.show()`).
2. The regenerated `appcast.xml` (written by `scripts/release.sh`) — this is what Sparkle
   reads to find new versions.
3. A git tag `vX.Y.Z` on that commit, pushed to `origin`.
4. A GitHub release `vX.Y.Z` titled `SuperMD X.Y.Z` with **both** assets attached:
   - `SuperMD-X.Y.Z.dmg` (human download)
   - `SuperMD-X.Y.Z.zip` (Sparkle's update payload — referenced by `appcast.xml`)

If any of these is missing or stale, auto-update breaks. The empty/broken-tag failure mode
is real: see the "Failure modes" section.

## Happy path

```sh
# 1. Bump versions in tracked files (Info.plist + SuperMDApp.swift).
#    CFBundleShortVersionString = "X.Y.Z"
#    CFBundleVersion            = monotonically-increasing integer (we use the same value)

# 2. Run the pipeline. Refuses to start if the tag already exists locally.
./scripts/release.sh
# ~5–20 min: build → notarize .app → staple → sign Sparkle zip → DMG → notarize DMG → staple → regenerate appcast.xml

# 3. Commit, tag, push.
git add Resources/Info.plist Sources/SuperMD/SuperMDApp.swift appcast.xml
git commit -m "Release vX.Y.Z"
git tag vX.Y.Z
git push origin main vX.Y.Z

# 4. Publish the GitHub release with BOTH assets.
gh release create vX.Y.Z \
  .build/SuperMD-X.Y.Z.dmg \
  .build/SuperMD-X.Y.Z.zip \
  --title "SuperMD X.Y.Z" \
  --generate-notes
```

## Prerequisites (verify before touching anything)

```sh
gh auth status                                                              # gh logged in
xcrun notarytool history --keychain-profile supermd-notary >/dev/null       # notary profile installed
security find-identity -v -p codesigning | grep "Developer ID Application"  # signing cert in keychain
command -v create-dmg                                                       # DMG tool (auto-installed otherwise)
security find-generic-password -s 'https://sparkle-project.org' >/dev/null  # Sparkle EdDSA key
```

Missing any of these → stop and consult the README's "One-time setup" section. Don't
proceed with a partial release.

## Failure modes & recovery

### "I created the tag but the release is empty / auto-update doesn't see the new version"

Symptoms:
- GitHub release exists but has no `.dmg` / `.zip` assets.
- `appcast.xml` still advertises the previous version.
- `Resources/Info.plist` still shows the previous `CFBundleShortVersionString`.
- No `Release vX.Y.Z` commit in `git log`.

Root cause: a tag was pushed without running `./scripts/release.sh`. The pipeline is what
builds the artifacts, signs them, notarizes them, and regenerates the appcast. A bare tag
does none of that.

Recovery — redo the release in place on the same version number:

```sh
# 1. Delete the empty GH release and its tag (local + remote).
gh release delete vX.Y.Z --yes --cleanup-tag
git tag -d vX.Y.Z 2>/dev/null || true

# 2. Bump Info.plist + SuperMDApp.swift if they weren't bumped.

# 3. Run the full happy path above (release.sh → commit → tag → push → gh release create).
```

If real users have already pulled the broken tag, prefer skipping to `vX.Y.(Z+1)` instead
of moving the tag — moved tags confuse anyone who fetched the old one.

### Notarization rejected (`status: Invalid`)

The script aborts; submission ID is in the script output. Re-fetch the log any time:

```sh
xcrun notarytool log <submission-id> --keychain-profile supermd-notary
```

See README "Troubleshooting notarization" for common causes (most often a Sparkle helper
binary that lost its hardened-runtime flag during a re-sign).

### Sparkle EdDSA key missing or rotated

Do not regenerate without understanding the consequence: rotating the key **breaks
auto-update for every existing installed copy** until users manually reinstall a build that
bundles the new `SUPublicEDKey`. README §"Sparkle EdDSA signing key" has the procedure.

## Verification after publishing

```sh
# Both should print "accepted" and "source=Notarized Developer ID"
spctl --assess --type open --context context:primary-signature -v .build/SuperMD-X.Y.Z.dmg
spctl --assess --type execute -v .build/SuperMD.app

# appcast must serve from main with the new <sparkle:version> and a valid edSignature
curl -s https://raw.githubusercontent.com/purbojati/supermd/main/appcast.xml
```

Then trigger **SuperMD → Check for Updates…** on a copy of the previous version to confirm
Sparkle sees and installs the update end-to-end.

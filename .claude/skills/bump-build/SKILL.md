---
name: bump-build
description: Increment the Mac Overflow build number before building or releasing. Use whenever building a new version of Mac Overflow, packaging with `make app`, cutting a release, or when the user says "bump the build". Mac Overflow is an SPM project (no Xcode project) — the version lives in scripts/generate-info-plist.sh, so update BUILD_NUMBER there.
---

# Bump the Mac Overflow build number

Mac Overflow is a **Swift Package Manager** project — there is **no `.xcodeproj`**.
The app version is defined in `scripts/generate-info-plist.sh`, which generates the
bundle's `Info.plist` during `make app`:

- `MARKETING_VERSION` → `CFBundleShortVersionString` (e.g. `1.0`) — the
  human-facing version. Bump this **manually** only for real releases.
- `BUILD_NUMBER` → `CFBundleVersion` — increment by **1 for every build**.

Both feed the About panel ("Version X (build Y)") and Finder's Get Info.

## Steps

1. From the repo root, increment `BUILD_NUMBER`:

   ```sh
   cur=$(grep -oE 'BUILD_NUMBER:-[0-9]+' scripts/generate-info-plist.sh | grep -oE '[0-9]+')
   next=$((cur + 1))
   sed -i '' "s/BUILD_NUMBER:-${cur}/BUILD_NUMBER:-${next}/" scripts/generate-info-plist.sh
   echo "build number: $cur -> $next"
   ```

2. Build/package/sign/install as usual (see the repo's `Makefile` — typically
   `make app` then codesign + copy to `/Applications`).

3. Verify the built bundle picked it up:

   ```sh
   /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
     -c 'Print :CFBundleVersion' build/MacOverflow.app/Contents/Info.plist
   ```

## Notes
- Do this **before** each build so no two builds share a `CFBundleVersion`.
- Commit the `scripts/generate-info-plist.sh` change together with the code it
  builds, so the build number is traceable in git history.
- Only touch `MARKETING_VERSION` when the user asks for a new release version.

# ScriptureStudy_RSEngineV2 Identifier and Capability Checklist

## Purpose

This checklist defines how the parallel `ScriptureStudy_RSEngineV2` project should be identified and sandboxed so it can be developed safely alongside the current `ScriptureStudy` app.

The objective is isolation:

- separate app identity
- separate app container
- separate defaults/cache space
- no accidental CloudKit/iCloud overlap unless explicitly chosen

## Recommended Project Identity

### Human-readable name

- `ScriptureStudy Reading/Search Engine V2`

### Project / repository shorthand

- `ScriptureStudy_RSEngineV2`

### Recommended app bundle identifier

- `com.scripturetstudy.rsenginev2`

### Recommended help bundle identifier

- `com.scripturetstudy.rsenginev2.help`

## Current Identifiers in the Existing App

These are present in the current codebase and should not simply be copied unchanged into the new project:

- app bundle ID: `com.scripturetstudy.app`
- help bundle ID: `com.scriptures.ScriptureStudy.help`
- iCloud container: `iCloud.com.graphe.scripturystudy`

## Recommended Rule

For `ScriptureStudy_RSEngineV2`:

- change the bundle identifier
- change the help bundle identifier
- do not reuse the current iCloud container unless shared cloud data is explicitly desired

## Best Initial Setup

For the new project, the safest first configuration is:

1. new bundle identifier
2. new help bundle identifier
3. iCloud / CloudKit capability disabled initially
4. app-sandbox data isolated automatically by the new bundle ID

This keeps the rebuild focused on the reading/search engine instead of cloud provisioning complexity.

## Capability Recommendation

### Recommended for V2 initially

- Keep file bookmark entitlement if module-folder access still depends on it
- Remove iCloud/CloudKit entitlements until the new app stabilizes
- Keep push notification entitlements removed unless they are actually required

### Why

The parallel build is an engine-focused rebuild, not yet a release identity. Removing cloud coupling reduces:

- signing friction
- provisioning mismatches
- accidental shared data behavior
- confusion when running both apps side by side

## Specific Entitlement Guidance

The current app entitlements include:

- `com.apple.developer.icloud-container-identifiers`
- `com.apple.developer.icloud-services`
- `com.apple.developer.ubiquity-container-identifiers`
- `com.apple.developer.ubiquity-kvstore-identifier`
- push notification environment keys
- app-scope file bookmarks

### For `ScriptureStudy_RSEngineV2`, recommended initial action:

- keep:
  - `com.apple.security.files.bookmarks.app-scope`
- remove initially:
  - `aps-environment`
  - `com.apple.developer.aps-environment`
  - `com.apple.developer.icloud-container-identifiers`
  - `com.apple.developer.icloud-services`
  - `com.apple.developer.ubiquity-container-identifiers`
  - `com.apple.developer.ubiquity-kvstore-identifier`

If cloud support is later required, add it back with a separate dedicated V2 container.

## If Cloud Support Is Needed Later

Use a separate container such as:

- `iCloud.com.scripturetstudy.rsenginev2`

Do not attach V2 to `iCloud.com.graphe.scripturystudy` unless the intention is explicit shared cloud state with the live app.

## Xcode Changes the Team Should Make

### In target build settings

Update:

- `PRODUCT_BUNDLE_IDENTIFIER`

Recommended value:

- `com.scripturetstudy.rsenginev2`

### In help bundle plist

Update:

- `CFBundleIdentifier`

Recommended value:

- `com.scripturetstudy.rsenginev2.help`

### In entitlements

Create a V2-specific entitlements file or trim the copied one so it starts minimal.

Recommended filename:

- `ScriptureStudy_RSEngineV2.entitlements`

## Operational Expectations

With a distinct bundle ID and reduced entitlements, the new app will:

- install alongside the current app
- keep separate sandbox data
- keep separate user defaults
- avoid polluting the current app’s cloud identity

That is the intended behavior.

## Recommendation Summary

Use this for the new project:

- App name: `ScriptureStudy_RSEngineV2`
- Bundle ID: `com.scripturetstudy.rsenginev2`
- Help bundle ID: `com.scripturetstudy.rsenginev2.help`
- Initial iCloud policy: disabled
- Initial push policy: disabled
- Bookmark entitlement: keep if module folder access still depends on it

This is the safest starting point for a side-by-side rebuild.

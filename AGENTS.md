# Repository Guidelines

## Project Structure & Module Organization

TwinFiles is a dependency-free Swift/AppKit dual-pane file manager targeting macOS 13+, using Swift tools 5.10.

- `Sources/TwinFiles/`: application entry point, app/window/pane controllers, filesystem operations, listing filters, and shared directory favorites.
- `Tests/TwinFilesTests/`: XCTest suites for file actions and listing behavior.
- `scripts/build-app.sh`: release build, app bundle assembly, icon generation, and ad-hoc signing.
- `scripts/make-icon.swift` and `Info.plist`: generated icon source and bundle metadata.
- `.build/` and `dist/`: ignored build outputs; do not commit them.

## Build, Test, and Development Commands

Use macOS with an installed Xcode/Swift toolchain. Open `Package.swift` in Xcode for development.

- `swift build`: compile a development executable.
- `zsh scripts/build-app.sh`: produce the signed release bundle at `dist/TwinFiles.app`.
- `open dist/TwinFiles.app`: launch the bundled app.

Run the tests with repository-local caches, as documented in `README.md`:

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" \
swift test --disable-sandbox --cache-path "$PWD/.build/cache" \
  --config-path "$PWD/.build/config" --security-path "$PWD/.build/security"
```

## Coding Style & Naming Conventions

Use four-space indentation, `UpperCamelCase` for types, and `lowerCamelCase` for methods and properties. Match existing Swift formatting; no formatter or linter configuration is present. Name files after their primary type or responsibility. Keep filesystem/listing logic separate from AppKit controllers. Preserve the existing Chinese user-facing terminology. Keep directory enumeration and batch operations off the main thread; update AppKit views on the main thread.

## Testing Guidelines

Use XCTest, with `*Tests.swift` files and descriptive `test...` methods. Filesystem tests must create isolated temporary directories and remove them during teardown. Add regression cases for collisions, recursive transfers, symlinks, filtering, and sorting when changing those behaviors. No numeric coverage threshold is configured. Manually verify UI changes in both panes, including relevant keyboard shortcuts.

## Commit & Pull Request Guidelines

Use concise, imperative commit subjects describing one focused change, matching existing history. PRs should explain the behavior change, link relevant issues, report validation commands and results, and include screenshots for UI changes. Preserve collision handling that retains existing files and guards against recursive transfers.

## Required Delivery Workflow

The user has authorized GitHub synchronization and App packaging for future feature improvements and bug fixes. Complete these steps without asking for the same authorization again:

1. Validate the change with appropriate tests and manual UI checks, then build `dist/TwinFiles.app` with `zsh scripts/build-app.sh`.
2. Commit the task changes and push `main` to `git@github.com:fangqi179/TwinFiles.git`. Preserve unrelated work and remote history.
3. Monitor `.github/workflows/release.yml` through completion. It tests and packages Apple Silicon and Intel apps, then publishes version `1.0.<run_number>` with ZIP downloads and SHA-256 checksums.
4. Verify the Release and both architecture assets; fix failures before reporting completion. Include the Release link in the final response. If blocked, report what remains unpublished.

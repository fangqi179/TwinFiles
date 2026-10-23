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

Git history is unavailable in this checkout, so no established commit convention can be verified. Use concise, imperative subjects describing one focused change. PRs should explain the behavior change, link relevant issues, report validation commands and results, and include screenshots for UI changes. Preserve collision handling that retains existing files and guards against recursive transfers.

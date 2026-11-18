# Follow-ups for upstream PR #192 (`--api-scope`)

PR: [Adyen/adyen-swift-public-api-diff#192](https://github.com/Adyen/adyen-swift-public-api-diff/pull/192), branch `feature/exclude-non-public-declarations` on the upstream repo, fixes [#187](https://github.com/Adyen/adyen-swift-public-api-diff/issues/187).

**Review state (2026-11-18):** the branch is up to date with upstream `main` (after #193 and #194). Built and tested on a reproduction module (Swift 6.4.2, Xcode 27.2):

- `--api-scope all`: 11 changes, including `internal let hidden`, `private let secret`, `fileprivate var fp`, `private var c`.
- `--api-scope public`: 8 changes. All internal/fileprivate/private stored properties are gone, including `private var s` inside a printed `@frozen` struct. Enum cases, protocol requirements, `public private(set) var` and `@usableFromInline internal` are kept, as documented.

The filter itself is ready. Three things are missing before it helps the people who reported #187.

---

## 1. The GitHub Action doesn't pass `--api-scope` (must fix)

`action.yml` has no input for it, and the "Run Diff" step calls:

```bash
"$BINARY_PATH" project --new "$NEW" --old "$OLD" --platform "$PLATFORM" --output … --log-output …
```

The CLI default is `all`, so after merging, Action users (including the reporter of #187, who uses the Action) see no difference.

**Change:**

- Add an input:
  ```yaml
  api_scope:
      description: 'Which declarations are part of the API: public, package or all (default: all)'
      required: false
      default: 'all'
  ```
- Pass it in "Run Diff": `--api-scope "$API_SCOPE"` with `API_SCOPE: ${{ inputs.api_scope }}` in `env`.
- Document the input in the README's Action section and in `Examples/github-workflow.yml` (commented, e.g. `# api_scope: public`).
- Decision for the maintainers: keep `all` as the Action default (no behavior change) or default to `public` (what most Action users want; the Action builds public interfaces anyway). Suggest keeping `all` in this PR and discussing the default separately.

## 2. `--swift-interface-type public` reads the package interface (bug, one line)

`Sources/ExecutableTargets/CommandLineTool/CommandLineTool+ExpressibleByArgument.swift`:

```swift
let mapping: [String: Self] = [
    "public": .package,   // ← should be .public
    "private": .private,
    "package": .package
]
```

Passing `--swift-interface-type public` explicitly makes `project` and `framework` look for `*.package.swiftinterface`. It only works today when the option is left out, because the property default is `.public` and the mapping isn't used. Present on upstream `main` and on the PR branch. Unrelated to #187, so it can be its own small PR (or a separate commit in #192 with a note in the description).

## 3. Tests that would have caught both

There are no tests for the command-line layer today: no test imports the `public-api-diff` executable target (the `UnitTests` target already depends on it, so `@testable import public_api_diff` works). And `test-action.yml` only runs when `action.yml` changes; #192 doesn't touch `action.yml`, so the Action test never ran for it, and the test only runs the Action without checking its output.

### 3a. Argument mapping round trip (catches #2)

New `Tests/UnitTests/CommandLineArgumentTests.swift`:

- Make `SwiftInterfaceType`, `APIScope`, `LogLevel` and `ProjectPlatform` `CaseIterable` (or list the cases in the test).
- For every case, `Type(argument: <its name>) == case`. For `SwiftInterfaceType` use `name`. That fails today for `.public`.
- Case-insensitive input (`"PUBLIC"`, `"Package"`) maps the same way; unknown input returns `nil`.
- Command parsing end to end, e.g.
  ```swift
  let command = try ProjectToOutputCommand.parse(["--new", "a", "--old", "b", "--platform", "iOS", "--swift-interface-type", "public", "--api-scope", "public"])
  #expect(command.swiftInterfaceType == .public)
  #expect(command.apiScope == .public)
  ```
  The same for `framework` and `swift-interface` (`--api-scope`), and that leaving the options out gives the defaults.

### 3b. Action and CLI stay in sync (catches #1)

A check that every option of `public-api-diff project` is either passed by the Action or explicitly excluded:

- Get the options from the CLI: `public-api-diff project --experimental-dump-help` (ArgumentParser's JSON tool info) → the option names.
- Get what the Action passes: parse the `--…` flags in the "Run Diff" step of `action.yml`.
- Allowlist for options the Action deliberately doesn't expose (e.g. `--scheme`, `--swift-interface-type`, `--log-level`), with a comment why.
- Fail if an option is neither passed nor allowlisted, so adding a CLI option forces a decision about the Action.

This can be a step in `run-tests.yml` (a small script, `jq` + `grep`), or a unit test that reads `action.yml` via `#filePath` and compares it with a hard-coded list of the command's option names (cheaper, but the list has to be updated by hand).

### 3c. Run the Action test when the CLI changes

In `test-action.yml`, add the CLI sources to the trigger paths:

```yaml
paths:
  - 'action.yml'
  - 'Sources/ExecutableTargets/CommandLineTool/**'
```

Optional, larger: let the job pass `api_scope: public` and check `api_comparison.md` for an expected line, so the Action test asserts something instead of only running.

---

## 4. README: how to get reliable results

Add a short section to the README, e.g. "Getting reliable results", next to the new "API Scope" section (or under "Usage"), and link it from the `swift-interface` and `framework` usage sections, where users bring their own files:

- **Generate both interfaces fresh, with the same Xcode and the same build settings.** Don't reuse `.swiftinterface` files from an earlier build, a different machine or another Xcode version. Newer compilers print interfaces differently and add new language features (attributes, module selectors like `Swift::String`, feature checks in `#if`), which shows up as changes that aren't API changes. The `project` command and the GitHub Action already do this: they build old and new in one run.
- **Build with library evolution** (`BUILD_LIBRARY_FOR_DISTRIBUTION = YES`, which the `project` command sets). Interfaces built without it contain private and internal storage and compiler details (`@_hasStorage`, `@_hasInitialValue`, generated `__derived_enum_equals`). If library evolution isn't possible (e.g. a dependency that doesn't support it), use `--api-scope public` and expect some remaining noise.
- **Compare the same interface type** on both sides (`.swiftinterface` with `.swiftinterface`, `.private.swiftinterface` with `.private.swiftinterface`).

## Smaller notes for the PR description

- The PR also changes how resource paths are made relative (`SwiftPackageFileAnalyzer+Targets.swift`, commit "showing correct path for resources"). It's unrelated to access levels; mention it in the description or move it to its own PR.
- Interfaces built without library evolution contain compiler-generated details that `--api-scope` doesn't remove: `@_hasStorage` / `@_hasInitialValue` attributes and the generated `__derived_enum_equals` method in `Equatable` enums. They show up in the text of added and removed declarations. Low priority: old and new are built in the same run with the same Xcode and settings, so they don't cause false modifications. Comparing interfaces built by different Xcode versions or with different settings is out of scope for the tool.
- `xcodebuild` warns "module interfaces are only supported with -enable-library-evolution" in this setup. The tool could pass that warning into the report's warnings, so users know why `--api-scope` matters for them.

## Done when

- [ ] `action.yml` has an `api_scope` input that is passed to the CLI; README and example workflow document it.
- [ ] `"public"` maps to `.public` for `--swift-interface-type`.
- [ ] `CommandLineArgumentTests` cover all argument mappings and the three commands' parsing.
- [ ] A check (3b) fails when a CLI option is neither passed by the Action nor allowlisted.
- [ ] `test-action.yml` runs on changes to the CLI sources.
- [ ] The README explains how to get reliable results: fresh interfaces from the same Xcode and settings, library evolution, same interface type.

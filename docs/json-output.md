# Spec: JSON output for `public-api-diff`

**Roadmap ID:** R5 (report) · **Priority:** P1 · **State:** new, ready to implement

## Summary

Add a `--format` option to every `public-api-diff` subcommand. `markdown` stays the default, so existing users and the GitHub Action see no change. `json` writes the same results as a documented, versioned JSON document that other tools can turn into anything: an HTML review page, a Mac app, a CI check, an RSS feed.

## Motivation

The Markdown report is made for reading in a pull request. It is hard to process further:

- Changes, parent paths, "Changes:" notes and `#if` conditions are mixed into Markdown text, emoji headings and HTML tables, so a consumer has to parse them back out.
- The `#if` conditions of a change (`Change.conditions`) are not in the Markdown at all.
- Any wording change in the report breaks consumers.

Today, [apple-sdk-api-watch](https://github.com/goergisn/apple-sdk-api-watch) works around this with its own small Swift executable (`poc/Sources/SDKInterfaceDiff`) that links the `SwiftInterfaceDiff` library and encodes `Change` values as JSON. That executable also has to redirect stdout to stderr while the engine runs, because the engine prints a debug line to stdout (see "Clean stdout" below). Built-in JSON output would let that project, and anyone else, use the released tool instead.

## Command line

New option on `project`, `swift-interface` and `framework`:

```
--format <markdown|json>   Output format (default: markdown)
```

- Parsed case-insensitively, like `--log-level` (add `OutputFormat: ExpressibleByArgument` in `CommandLineTool+ExpressibleByArgument.swift`).
- Works with `--output <path>` (write the file) and without it (print to stdout), exactly like Markdown today.
- No other options change.

Examples:

```bash
public-api-diff swift-interface --old old.swiftinterface --new new.swiftinterface --target-name MyModule --format json
public-api-diff project --old main --new develop --platform iOS --format json --output report.json
```

### Clean stdout

When JSON is printed to stdout, stdout must contain only the JSON document followed by one newline, so `public-api-diff … --format json | jq` always works.

- `SwiftInterfaceChangeConsolidator.swift` has a bare `print("⚠ We should not end up here - investigate how this happened")`. Route it through the logger (or write it to stderr) and add the message to `warnings` in the output.
- Audit the targets for any other `print` calls on the analysis path. The existing logging (`SystemLogger` via `os.Logger`, `LogFileLogger`) doesn't write to stdout and can stay.

### Exit status

Today all three commands catch errors, log `💥 …` and still exit with status 0. In JSON mode a consumer can't tell a failure from "no changes".

- In JSON mode, on any error: write nothing to stdout or `--output`, log the error as today, and exit with a non-zero status (rethrow, or `throw ExitCode.failure`).
- Don't change Markdown mode. Changing its exit status would affect the GitHub Action and existing scripts; that is a separate decision.

## JSON format

One JSON object (UTF-8, pretty-printed, keys sorted). Example for `swift-interface` with one module:

```json
{
  "formatVersion": 1,
  "tool": { "name": "public-api-diff", "version": null },
  "oldVersionName": "v1.0",
  "newVersionName": "v2.0",
  "platform": "iOS",
  "analyzedTargets": ["MyModule"],
  "warnings": [],
  "summary": { "added": 1, "modified": 1, "removed": 0, "total": 2 },
  "targets": {
    "MyModule": [
      {
        "kind": "added",
        "parentPath": "MyType",
        "before": null,
        "after": "public func reload(animated: Swift.Bool)",
        "details": [],
        "conditions": []
      },
      {
        "kind": "modified",
        "parentPath": null,
        "before": "public struct MyType",
        "after": "public struct MyType : Swift.Sendable",
        "details": ["Added inheritance `Swift.Sendable`"],
        "conditions": []
      }
    ]
  }
}
```

### Fields

| Field | Type | Source | Notes |
|---|---|---|---|
| `formatVersion` | integer | constant `1` | Bump only for breaking changes (field removed, renamed or changed in meaning). New optional fields don't bump it; consumers must ignore unknown fields. |
| `tool.name` | string | constant | `"public-api-diff"` |
| `tool.version` | string or null | build info | The tool has no version constant today, so this is `null` until one is added (for example a `--version` flag fed from the release tag). |
| `oldVersionName`, `newVersionName` | string or null | `generate(...)` parameters | `null` when not given. |
| `platform` | string or null | `generate(...)` parameter | e.g. `"iOS"`; `null` for `swift-interface`/`framework`. |
| `analyzedTargets` | array of strings or null | `allTargets` | Sorted. `null` when not provided. An empty array means "targets were expected but none were found" (Markdown: "‼️ No analyzable targets detected"). |
| `warnings` | array of strings | `warnings` | Same text as the Markdown `> [!WARNING]` blocks. |
| `summary` | object | computed | Counts of `added`, `modified`, `removed` and `total` over all targets. Saves consumers from counting. |
| `targets` | object | `changesPerTarget` | Key: target/module name (may be `""` when `swift-interface` runs without `--target-name`). Value: array of change records. Targets without changes are left out, as in Markdown. |

Change record:

| Field | Type | From `PADCore.Change` |
|---|---|---|
| `kind` | `"added"`, `"modified"` or `"removed"` | `changeType` case |
| `parentPath` | string or null | `parentPath` (`null`, not `""`, when there is none) |
| `before` | string or null | removal description, or old description of a modification; `null` for additions |
| `after` | string or null | addition description, or new description of a modification; `null` for removals |
| `details` | array of strings | `listOfChanges` (already sorted by `Change.init`) |
| `conditions` | array of strings | `conditions`, outermost first; empty when declared unconditionally |

`before` and `after` are the declaration text the engine produces, the same text the Markdown shows in its code blocks. For a declaration inside `#if` clauses that text already includes the `#if … #endif` lines; `conditions` lists the same conditions separately so consumers can filter or group by them without parsing.

### Ordering (deterministic output)

The same input must always give byte-identical output, so reports can be diffed and cached:

- `JSONEncoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]`.
- `targets` keys are sorted (by `sortedKeys`).
- Records within a target are sorted by `parentPath` (null first), then `kind` (added, modified, removed, matching the Markdown sections), then `after ?? before`, then `before`, then `details` and `conditions` joined. This follows the Markdown grouping, and the tie-breakers make the order total.

### Schema

Ship a JSON Schema (draft 2020-12) for format version 1 at `Sources/PublicModules/PADOutputGenerator/Resources/public-api-diff.schema.json` (or under `docs/`) and link it from the README. Tests validate the reference output against it.

## Implementation

1. **`PADOutputGenerator`:** add `public struct JSONOutputGenerator: OutputGenerating` with `OutputType == String` (the encoded document), so the commands can treat both generators alike. Keep the `Codable` model types (`JSONReport`, `JSONReport.ChangeRecord`) public, so library users can also decode a report (useful for the Mac app and the HTML renderer).
2. **`PADCore`:** no changes needed. If it's preferred, `Change.ChangeType` can get a `kind` string helper, but the mapping can stay inside the generator.
3. **Command line:** add `OutputFormat` (`markdown`, `json`) and the `--format` option to the three commands. Each command's `generateOutput` picks the generator from the format. A small shared helper avoids repeating the switch three times.
4. **Clean stdout and exit status:** as described above.
5. **README:** document `--format json`, show one example, link the schema and describe the versioning rule.
6. **GitHub Action (`action.yml`):** unchanged. Optionally add a `format` input later, defaulting to `markdown`.

## Tests

- **Unit (`OutputGeneratorTests`):** for the cases the Markdown tests already cover (no changes, no analyzable targets, warnings, one target, several targets, empty target name), check the decoded JSON; and check:
  - every change kind maps to the right `kind`, `before` and `after`;
  - `parentPath` becomes `null`, not `""`;
  - `conditions` and `details` are passed through;
  - output is byte-identical when the input changes are shuffled.
- **Reference (`IntegrationTests`):** add `expected-reference-changes-swift-interface-public.json` and `…-private.json` next to the Markdown references and compare them byte for byte. This avoids the problem in C8 (reference tests that ignore extra lines).
- **Schema:** validate both reference files against the schema.
- **Command line:** `--format json` without `--output` prints valid JSON only (decode stdout); `--format JSON` is accepted; an unreadable input file exits non-zero in JSON mode and leaves stdout empty.

## Acceptance criteria

- [ ] `--format json` works on `project`, `swift-interface` and `framework`, with and without `--output`; the default output is unchanged byte for byte.
- [ ] The JSON matches the format above and the schema; output is deterministic.
- [ ] Stdout holds only JSON in JSON mode; no stray `print` remains on the analysis path.
- [ ] JSON mode exits non-zero on errors and writes no partial output.
- [ ] Unit, reference and schema tests pass, with the existing tests.
- [ ] README documents the option, the schema and the versioning rule.

## Out of scope (possible follow-ups)

- More data per record, such as the element kind (`func`, `struct`, …), its name, or the breaking/non-breaking classification from R1. These can be added later as optional fields without bumping `formatVersion`.
- Other formats (HTML, SARIF, JUnit). They can be built from the JSON outside the tool.
- Changing the exit status in Markdown mode.

## Consumer: apple-sdk-api-watch

When this lands, `compare-poc.py` can call `public-api-diff swift-interface --format json` per module instead of the custom `SDKInterfaceDiff` executable. The record fields above match what that executable writes today (`kind`, `parentPath`, `before`, `after`, `details`, `conditions`), so the review page and documentation links keep working; only the per-module wrapper changes from a bare array to the report object (`targets[<module>]`).

# Upstream PRs for the diff engine

Paste-ready PR descriptions for contributing the fork's work ([goergisn/adyen-swift-public-api-diff](https://github.com/goergisn/adyen-swift-public-api-diff)) back to [Adyen/adyen-swift-public-api-diff](https://github.com/Adyen/adyen-swift-public-api-diff). Background, numbers and open issues are in [engine-roadmap.md](engine-roadmap.md); the IDs (A1, C2, …) refer to it.

State as of 2026-11-15: Adyen `main` is at `4fb709e`. Fork `main` is Adyen `main` plus one commit (A1). All branches below and `projected-main` are pushed to the fork; PR 1 uses the branch `swift-syntax-604`, which points at fork `main`.

## Overview

| PR | Branch | Base | Contains | Size | Tests |
|---|---|---|---|---|---|
| 1 | `swift-syntax-604` (= fork `main`, 712a8fa) | Adyen `main` | A1 | 9 files, +293 −68 | `ModuleSelectorTests`, `RepeatedParameterLabelTests` |
| 2 | `normalize-api-diff-ordering` | PR 1 | A2 | 3 files, +99 −7 | `OrderingTests` |
| 3 | `ignore-internal-parameter-names` | PR 1 | A3 | 8 files, +70 −27 | `ParameterNameTests` |
| 4 | `normalize-overlay-module-selectors` | PR 1 | A4 | 2 files, +32 −1 | `ModuleSelectorTests` |
| 5 | `pair-extensions-by-conformance` | PR 1 | A8 | 2 files, +105 −9 | `ExtensionPairingTests` |
| 6 | `parse-macro-declarations` | PR 1 | C2, C5 | 12 files, +605 −31 | `MacroDeclarationTests`, `OverloadPairingTests`, reference packages |
| 7 | `order-independent-extension-merging` | PR 1 | A5 | 16 files, +331 −18 | `ExtensionMergeTests` |
| 8 | `conformance-availability` | PR 7 | A6 | 11 files, +230 −13 | `ExtensionMergeTests` |
| 9 | `describe-availability-changes` | PR 8 | A7 | 11 files, +366 −20 | `AvailabilityChangeTests`, reference output |
| 10 | `combine-standalone-extensions` | PR 8 | C9, C10, C11 | 14 files, +1284 −62 | `ExtensionCombiningTests`, `ConditionalCompilationTests` |

`projected-main` merges all of them: 131 unit tests and 2 reference tests pass.

**Order:** PR 1 first, as every other PR needs swift-syntax 604. PRs 2–7 are independent of each other. PRs 7 → 8 → 9 and 7 → 8 → 10 are stacked.

**Pushing:** done. PR 1 is opened from `swift-syntax-604` (same commit as fork `main`) rather than from `main`.

**Known conflicts** when the later PR is rebased onto an earlier one (all resolved in `projected-main`, which can serve as the reference resolution):
- PR 6 ↔ PR 3: macro parameters also ignore internal parameter names.
- PR 6 ↔ PR 5: overload pairing (C5) and extension pairing (A8) both change `SwiftInterfaceAnalyzer.recursiveCompare`; extensions keep A8's `findBestExtensionMatch`, other elements use C5's ranked pairing.
- PR 10 ↔ PR 2: `AttributeListSyntax.sanitizedList` keeps both the availability normalization and the per-clause `#if` attributes.
- PR 10 ↔ PR 9: attribute diff wording; conditions are described next to the per-platform availability wording. Test expectations in `ExtensionCombiningTests` use A7's wording.
- PR 10 ↔ PR 6: the same `#if` conditions rank first in C5's pairing; macros carry their conditions.

**History cleanup before PR 10:** the branch has 8 commits of its own, including back-and-forth on how conditional attributes are rendered (block → comment → block). Squashing into three commits (C9, C10, C11) would make review easier; splitting C9 into its own PR is also possible, since `1772a56` is a self-contained C9 commit.

---

## PR 1: Update SwiftSyntax to 604 and normalize module selectors

**Branch:** `swift-syntax-604` (712a8fa, same as fork `main`) → Adyen `main`

````markdown
## Summary

Xcode 27 `.swiftinterface` files spell types with module selectors (`Swift::String`) instead of the dot spelling (`Swift.String`). SwiftSyntax 603 can't parse them, and when comparing an interface from an older Xcode with a newer one, almost every declaration was reported as changed.

## Changes

- Updates swift-syntax to 604 (parses `::`) and swift-testing to 6.4.1.
- Adds `ModuleSelectorNormalizer`, which rewrites module selectors of imported modules to the dot spelling before comparing, so interfaces from different Xcode versions compare cleanly.
- Fixes a missed change when a declaration has two unlabeled parameters (`_ first: Int, _ second: Int` → `_ first: Int, _ second: String`).
- Caches recursive descriptions during one analysis (large SDK interfaces were dominated by recomputing them).

## Tests

- `ModuleSelectorTests`: selector spellings of imported modules compare equal to the dot spelling.
- `RepeatedParameterLabelTests`: a change to the second unlabeled parameter is reported.
````

## PR 2: Normalize availability ordering and detect reordered parameters

**Branch:** `normalize-api-diff-ordering` (0683c34) → PR 1

````markdown
## Summary

The same `@available` platforms listed in a different order (`@available(iOS 17, macOS 14, *)` vs. `@available(macOS 14, iOS 17, *)`) were reported as a change, and parameters that only moved position were not reported at all.

## Changes

- Shorthand `@available` platform lists are sorted before comparing (the wildcard stays last), and `@available` attributes are sorted among themselves.
- Parameters that only moved position are reported as "Reordered parameters".

## Tests

- `OrderingTests`: reordered availability platforms and attributes are not a change; version changes and reordered parameters are.
````

## PR 3: Ignore internal parameter names when comparing declarations

**Branch:** `ignore-internal-parameter-names` (471cdac) → PR 1

````markdown
## Summary

Renaming an internal parameter name (`func move(to oldName: Point)` → `func move(to newName: Point)`) doesn't change how a declaration is called, but it was reported as a modification. SDK interfaces rename internal names frequently between builds.

## Changes

- Functions, initializers and subscripts are compared without internal parameter names.
- The output still shows the declarations as written, and changes to external labels are still reported.

## Tests

- `ParameterNameTests`: internal renames are not a change; label changes are.
````

## PR 4: Resolve module selectors of transitively imported modules in overlays

**Branch:** `normalize-overlay-module-selectors` (654cb88) → PR 1

````markdown
## Summary

SDK overlays (`@_exported import Framework`) refer to modules the framework imports transitively (e.g. `Input::Value`). Those selectors weren't normalized by the module selector normalizer, so every such declaration showed up as changed when comparing with an older interface.

## Changes

- If a module re-exports itself (an overlay), all modules used in selectors are treated as known and normalized.

## Tests

- `ModuleSelectorTests`: selectors of transitively imported modules in an overlay are normalized.
````

## PR 5: Pair standalone extensions by conformance and members

**Branch:** `pair-extensions-by-conformance` (542ad33) → PR 1

````markdown
## Summary

Extensions that can't be merged into their extended type (e.g. extensions of `Swift.Never` or of types from other modules) were paired with the first extension of the same type once their header changed. This produced fake changes such as "Added inheritance `DynamicInstructions`" for `extension Never: Generable`, and could cancel out a real change.

## Changes

- Standalone extensions are paired by the same conformances first, then shared conformances, then the most matching members.
- An extension that has an exact counterpart is never paired with another one.

## Tests

- `ExtensionPairingTests`: extensions of the same type with different conformances are paired with their own counterpart.
````

## PR 6: Parse macro declarations and pair overloads with their own counterpart

**Branch:** `parse-macro-declarations` (6132c24, 8a03982) → PR 1

````markdown
## Summary

Macro declarations weren't parsed, so added, removed or changed macros never appeared in a diff (e.g. 12 new public macros in the iOS 27.3 SDK). While adding them, overloads with the same name (`@Guide<RegexOutput>(description:_:)` / `@Guide<T>(description:_:)`) turned out to be paired with the wrong counterpart, which also affected functions and initializers.

## Changes

**Macros**
- New `SwiftInterfaceMacro` element: attributes such as `@attached(…)` / `@freestanding(…)`, name, generic parameters, parameters, return type, `where` clause and the `#externalMacro(module:type:)` definition.
- Changes to the role attribute and to the definition are described (a different implementation module is an observable change).

**Overload pairing**
- Elements are paired globally instead of first-come-first-served: same description first, then elements that only differ in attributes/modifiers (e.g. availability), then other comparable elements. Within each group the most similar pairs (fewest differences, most matching children) win, so the result no longer depends on declaration order.
- The consolidator combines a removal with the addition it was actually paired with.

In the iOS 27.2 → 27.3 SDK this removes 54 fake parameter type changes in FoundationModels and fake `@nonexhaustive` / `@_disfavoredOverload` changes, and surfaces a new `buildLimitedAvailability` overload.

## Tests

- `MacroDeclarationTests`: added, removed and modified macros, role attribute and definition changes.
- `OverloadPairingTests`: overloads keep their own counterpart regardless of order.
- Reference packages include macros; expected reference output updated.
````

## PR 7: Make extension merging independent of declaration order

**Branch:** `order-independent-extension-merging` (c1bc42f) → PR 1

````markdown
## Summary

Merging extensions into their extended type depended on declaration order, so when declarations were reordered between two SDK builds, many members were reported as removed and added again. In iOS 27.2 → 27.3 this hit SwiftUI `TabContent`, `Table`, `WindowGroup`, Foundation `Locale.Components` and all of TipKit.

## Changes

- The extended type is matched on whole path components and every candidate is tried. Before, a plain `hasPrefix` sent `extension M.TabContent` into `struct M.Tab`.
- Shallower extensions are merged first, so `extension M.A.B` finds `B` even if `extension M.A { struct B }` comes later in the file.
- An extension's `@available` is carried onto its merged members; a member's own `@available` for a platform takes precedence. Availability changes of an extension stay visible after merging.

Removals in iOS 27.2 → 27.3 went from 271 to 6, with every record accounted for; "⚠ We should not end up here" warnings went from 169 to 0.

## Tests

- `ExtensionMergeTests`: merging regardless of order, prefix-sharing sibling types, availability inheritance and precedence.
````

## PR 8: Keep and render the availability of conformances declared in extensions

**Branch:** `conformance-availability` (60d6613, 0e36d2c) → PR 7

````markdown
## Summary

A conformance added by an `@available` extension lost its availability when the extension was merged into its type, so availability changes of conformances were invisible (e.g. `extension Sentiment: Hashable` arriving on tvOS 27.0, `ActivityStyle: Hashable` on macOS 27.3).

## Changes

- A conformance declared in an extension with its own availability keeps it.
- Such conformances are rendered the way the interface declares them, as an extension after the type:

```swift
@available(iOS 16.1, *)
public enum ActivityStyle

@available(iOS 16.1, macOS 27.3, *)
extension ActivityStyle: Swift.Equatable
```

- A conformance whose only change is its availability is reported as "Changed availability of conformance …" instead of a removal plus an addition.

## Tests

- `ExtensionMergeTests`: conformance availability is kept, rendered and compared.
````

## PR 9: Describe availability changes per platform

**Branch:** `describe-availability-changes` (56e4d73) → PR 8

````markdown
## Summary

An availability change showed up as several added/removed `@available` attribute lines, which is hard to read in SDK diffs where availability changes are the most common change.

## Changes

Availability changes are described per platform, e.g. `Availability added: macOS 27.3, Mac Catalyst 27.3`. Covered:
- added, changed and no longer declared versions;
- marked / no longer unavailable;
- deprecation, including messages and renames;
- obsoletion;
- availability of conformances (see the previous PR).

Arguments that aren't understood fall back to the previous added/removed attribute wording.

## Tests

- `AvailabilityChangeTests`: each kind of change.
- Expected reference output updated.
````

## PR 10: Combine standalone extensions and compare every `#if` clause

**Branch:** `combine-standalone-extensions` → PR 8 (squash suggestion: one commit each for C9, C10, C11)

````markdown
## Summary

Two related problems with extensions and conditional compilation:

1. **Standalone extensions** (of types from other modules, or with a `where` clause) were compared block by block. Interfaces split and merge these blocks between versions (e.g. one block per availability), so members that only moved to another block were reported as removed and added.
2. **`#if` clauses** were all parsed as if they were unconditional. Interfaces spell the same declaration again in an `#else` clause for older compilers (`~Sendable` behind `$TildeSendable`, `@lifetime` vs. `@_lifetime`, `@abi` vs. `@_silgen_name`). Variants of different clauses were compared with each other, which produced fake changes, and changes were counted twice.

## Changes

**Combining standalone extensions**
- Extensions that can't be merged into their type are combined into one extension per extended type, `where` clause and (non-availability) attributes. Each block's `@available` moves onto its members and conformances, as for merged extensions.

**Conditional compilation**
- Every clause of an `#if` is parsed. Each declaration is tagged with the condition of its clause (`#if $X`, `#else` → `!$X`, `#elseif` → `!$X && Y`); members inherit the conditions of their enclosing declarations.
- A declaration is compared with the variant under the same conditions in the other version. A declaration moving into or out of an `#if` is reported as `Added condition #if …` / `Removed condition #if …`.
- Every change in every clause is reported. A change made in both clauses is two changes, as it's two pieces of code.
- An extension is merged into the variant of its type whose conditions match; if none matches, it applies to every variant and is merged into each of them.
- Attributes inside an `#if` in an attribute list are kept per clause.
- `Change` gets a `conditions` property (all conditions including the enclosing declarations', empty for unconditional declarations), so consumers can filter.
- Output renders conditions as valid Swift:

```swift
#if compiler(>=5.3) && $TildeSendable
public struct Shape: ~Swift.Sendable {
  #if !$Embedded
  public func area() -> Swift.Double
  public func describe() -> Swift.String
  #endif
}
#endif
```

## Results (iOS 27.2 → 27.3 SDK)

- No fake changes from comparing `#if` and `#else` variants.
- A real change that the duplicates hid is reported: SwiftUICore `ArrangementViewStyleConfiguration.Primary`/`.Secondary` lost their `Swift.Sendable` conformance.
- Changes in fallback clauses are reported separately and tagged (e.g. AVFAudio span properties in both the `@lifetime` and `@_lifetime` variant).

## Tests

- `ExtensionCombiningTests`: splitting and merging extension blocks is not a change; availability moves onto members; extensions with other attributes or `where` clauses stay apart.
- `ConditionalCompilationTests`: tagging (including `#elseif`, nested `#if`, attribute lists, macros), pairing within the same conditions, gate changes, a type split into variants, extensions merged into every variant, and rendering.
````

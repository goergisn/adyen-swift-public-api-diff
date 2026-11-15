# Upstream PRs for the diff engine

Paste-ready PR descriptions for contributing the fork's work ([goergisn/adyen-swift-public-api-diff](https://github.com/goergisn/adyen-swift-public-api-diff)) back to [Adyen/adyen-swift-public-api-diff](https://github.com/Adyen/adyen-swift-public-api-diff). Background, numbers and open issues are in [engine-roadmap.md](engine-roadmap.md); the IDs (A1, C2, …) refer to it.

State as of 2026-11-15: Adyen `main` is at `4fb709e`. The work is bundled into 5 themed PRs, stacked so that each branch is based on the previous one. All conflicts between the items are resolved inside the stack, and the last branch has the same code as `projected-main` (apart from `docs/`). All branches are pushed to the fork.

## Overview

| PR | Branch | Base | Contains | Size | Tests |
|---|---|---|---|---|---|
| 1 | `xcode-27-interfaces` | Adyen `main` | A1, A4 | 9 files, +324 −68 | `ModuleSelectorTests`, `RepeatedParameterLabelTests` |
| 2 | `normalize-declaration-comparison` | PR 1 | A2, A3 | 11 files, +169 −34 | `OrderingTests`, `ParameterNameTests` |
| 3 | `macros-and-pairing` | PR 2 | A8, C2, C5 | 13 files, +720 −38 | `ExtensionPairingTests`, `MacroDeclarationTests`, `OverloadPairingTests`, reference packages |
| 4 | `extension-merging-and-availability` | PR 3 | A5, A6, A7 | 23 files, +913 −37 | `ExtensionMergeTests`, `AvailabilityChangeTests`, reference output |
| 5 | `conditional-compilation` | PR 4 | C9, C10, C11 | 16 files, +1292 −60 | `ExtensionCombiningTests`, `ConditionalCompilationTests` |

Unit and reference tests pass on every branch of the stack (131 unit + 2 reference tests on PR 5).

**Opening the PRs:** open PR 1 against Adyen `main`. The later PRs can only target the previous branch once it exists in the Adyen repo, so either open them one at a time after the previous one is merged, or open them against Adyen `main` with a note that they include the previous PR's commits ("Depends on #…; review only the last N commits").

**Superseded branches:** the earlier per-item branches were deleted. `normalize-api-diff-ordering` (A2) is kept until the PoC in apple-sdk-api-watch, which pins it, is moved to another branch.

---

## PR 1: Support Xcode 27 interfaces (SwiftSyntax 604, module selectors)

**Branch:** `xcode-27-interfaces` → Adyen `main` (2 commits: A1, A4)

````markdown
## Summary

Xcode 27 `.swiftinterface` files spell types with module selectors (`Swift::String`) instead of the dot spelling (`Swift.String`). SwiftSyntax 603 can't parse them, and when comparing an interface from an older Xcode with a newer one, almost every declaration was reported as changed.

## Changes

- Updates swift-syntax to 604 (parses `::`) and swift-testing to 6.4.1.
- Adds `ModuleSelectorNormalizer`, which rewrites module selectors of imported modules to the dot spelling before comparing, so interfaces from different Xcode versions compare cleanly.
- SDK overlays (`@_exported import Framework`) refer to modules the framework imports transitively (e.g. `Input::Value`). If a module re-exports itself, all modules used in selectors are treated as known and normalized.
- Fixes a missed change when a declaration has two unlabeled parameters (`_ first: Int, _ second: Int` → `_ first: Int, _ second: String`).
- Caches recursive descriptions during one analysis (large SDK interfaces were dominated by recomputing them).

## Tests

- `ModuleSelectorTests`: selector spellings of imported and transitively imported modules compare equal to the dot spelling.
- `RepeatedParameterLabelTests`: a change to the second unlabeled parameter is reported.
````

## PR 2: Fewer false changes when comparing declarations

**Branch:** `normalize-declaration-comparison` → PR 1 (2 commits: A2, A3)

````markdown
## Summary

Some differences between two interfaces don't change the API but were reported as changes, while one real change wasn't reported:

- The same `@available` platforms listed in a different order (`@available(iOS 17, macOS 14, *)` vs. `@available(macOS 14, iOS 17, *)`).
- A renamed internal parameter name (`func move(to oldName: Point)` → `func move(to newName: Point)`), which doesn't change how a declaration is called. SDK interfaces rename internal names frequently between builds.
- Parameters that only moved position were not reported at all.

## Changes

- Shorthand `@available` platform lists are sorted before comparing (the wildcard stays last), and `@available` attributes are sorted among themselves.
- Parameters that only moved position are reported as "Reordered parameters".
- Functions, initializers and subscripts are compared without internal parameter names. The output still shows the declarations as written, and changes to external labels are still reported.

## Tests

- `OrderingTests`: reordered availability platforms and attributes are not a change; version changes and reordered parameters are.
- `ParameterNameTests`: internal renames are not a change; label changes are.
````

## PR 3: Parse macros and pair declarations with their own counterpart

**Branch:** `macros-and-pairing` → PR 2 (3 commits: A8, C2, C5)

````markdown
## Summary

- **Macros** weren't parsed, so added, removed or changed macros never appeared in a diff (e.g. 12 new public macros in the iOS 27.3 SDK).
- **Pairing:** to find what changed, each declaration of the old interface is paired with its counterpart in the new one. Two cases picked the wrong counterpart and produced fake changes:
  - Overloads with the same name (`@Guide<RegexOutput>(description:_:)` / `@Guide<T>(description:_:)`, functions, initializers) were paired first-come-first-served, so the result depended on declaration order.
  - Extensions that can't be merged into their type (e.g. of `Swift.Never`) were paired with the first extension of the same type once their header changed, e.g. "Added inheritance `DynamicInstructions`" for `extension Never: Generable`. This could also cancel out a real change.

## Changes

**Macros**
- New `SwiftInterfaceMacro` element: attributes such as `@attached(…)` / `@freestanding(…)`, name, generic parameters, parameters (compared without internal names), return type, `where` clause and the `#externalMacro(module:type:)` definition.
- Changes to the role attribute and to the definition are described (a different implementation module is an observable change).

**Pairing**
- Non-extension elements are paired globally: same description first, then elements that only differ in attributes/modifiers (e.g. availability), then other comparable elements. Within each group the most similar pairs (fewest differences, most matching children) win, so the result doesn't depend on declaration order.
- Standalone extensions are paired by the same conformances first, then shared conformances, then the most matching members.
- An element that has an exact counterpart is never paired with another one.
- The consolidator combines a removal with the addition it was actually paired with.

In the iOS 27.2 → 27.3 SDK this removes 54 fake parameter type changes in FoundationModels and fake `@nonexhaustive` / `@_disfavoredOverload` changes, and surfaces a new `buildLimitedAvailability` overload.

## Tests

- `MacroDeclarationTests`: added, removed and modified macros, role attribute and definition changes, renamed internal parameter names.
- `OverloadPairingTests`: overloads keep their own counterpart regardless of order.
- `ExtensionPairingTests`: extensions of the same type with different conformances are paired with their own counterpart.
- Reference packages include macros; expected reference output updated.
````

## PR 4: Order-independent extension merging and availability changes

**Branch:** `extension-merging-and-availability` → PR 3 (4 commits: A5, A6 ×2, A7)

````markdown
## Summary

Extensions are merged into the type they extend before comparing. Three problems around that and around availability:

- **Order dependence:** merging depended on declaration order, so when declarations were reordered between two SDK builds, many members were reported as removed and added again (in iOS 27.2 → 27.3: SwiftUI `TabContent`, `Table`, `WindowGroup`, Foundation `Locale.Components` and all of TipKit).
- **Lost conformance availability:** a conformance added by an `@available` extension lost its availability when merged, so availability changes of conformances were invisible (e.g. `extension Sentiment: Hashable` arriving on tvOS 27.0, `ActivityStyle: Hashable` on macOS 27.3).
- **Hard to read availability changes:** a change showed up as several added/removed `@available` attribute lines, although availability changes are the most common change in SDK diffs.

## Changes

**Extension merging**
- The extended type is matched on whole path components and every candidate is tried. Before, a plain `hasPrefix` sent `extension M.TabContent` into `struct M.Tab`.
- Shallower extensions are merged first, so `extension M.A.B` finds `B` even if `extension M.A { struct B }` comes later in the file.
- An extension's `@available` is carried onto its merged members; a member's own `@available` for a platform takes precedence.

**Conformance availability**
- A conformance declared in an extension with its own availability keeps it and is rendered the way the interface declares it:

```swift
@available(iOS 16.1, *)
public enum ActivityStyle

@available(iOS 16.1, macOS 27.3, *)
extension ActivityStyle: Swift.Equatable
```

**Availability wording**
- Availability changes are described per platform, e.g. `Availability added: macOS 27.3, Mac Catalyst 27.3`: added, changed and no longer declared versions, marked / no longer unavailable, deprecation (including messages and renames), obsoletion, and availability of conformances. Arguments that aren't understood fall back to the previous wording.

In iOS 27.2 → 27.3, removals went from 271 to 6, with every record accounted for, and "⚠ We should not end up here" warnings went from 169 to 0.

## Tests

- `ExtensionMergeTests`: merging regardless of order, prefix-sharing sibling types, availability inheritance and precedence, conformance availability.
- `AvailabilityChangeTests`: each kind of availability change.
- Expected reference output updated.
````

## PR 5: Combine standalone extensions and compare every `#if` clause

**Branch:** `conditional-compilation` → PR 4 (3 commits: C9, C10, C11)

````markdown
## Summary

- **Standalone extensions** (of types from other modules, or with a `where` clause) were compared block by block. Interfaces split and merge these blocks between versions (e.g. one block per availability), so members that only moved to another block were reported as removed and added.
- **`#if` clauses** were all parsed as if they were unconditional. Interfaces spell the same declaration again in an `#else` clause for older compilers (`~Sendable` behind `$TildeSendable`, `@lifetime` vs. `@_lifetime`, `@abi` vs. `@_silgen_name`). Variants of different clauses were compared with each other, which produced fake changes, and changes were counted twice.

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
- A real change that the duplicates hid is reported: SwiftUICore `ArrangementViewStyleConfiguration.Primary`/`.Secondary` lost their `Swift.Sendable` conformance (in both variants).
- Changes in fallback clauses are reported separately and tagged (e.g. AVFAudio span properties in both the `@lifetime` and `@_lifetime` variant).

## Tests

- `ExtensionCombiningTests`: splitting and merging extension blocks is not a change; availability moves onto members; extensions with other attributes or `where` clauses stay apart.
- `ConditionalCompilationTests`: tagging (including `#elseif`, nested `#if`, attribute lists, macros), pairing within the same conditions, gate changes, a type split into variants, extensions merged into every variant, and rendering.
````

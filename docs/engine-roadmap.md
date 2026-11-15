# Diff engine roadmap

Issue drafts for the engine fork [goergisn/adyen-swift-public-api-diff](https://github.com/goergisn/adyen-swift-public-api-diff) (forked from Adyen/adyen-swift-public-api-diff). Each section below can be copied into a GitHub issue as is. The numbers come from comparing iOS 27.2 (Xcode 27.2, 24B8118) with iOS 27.3 (Xcode 27.3 beta, 24C5037e).

Priority proposal: **correctness and coverage first**, then report quality, then performance.

| Prio | ID | Title | Kind | State |
|---|---|---|---|---|
| — | A1 | Update SwiftSyntax to 604 and normalize module selectors | existing | on fork `main` |
| — | A2 | Normalize availability ordering, detect reordered parameters | existing | branch, pushed |
| — | A3 | Ignore internal parameter names | existing | branch, pushed |
| — | A4 | Resolve module selectors of transitively imported modules | existing | branch, pushed |
| — | A5 | Make extension merging independent of declaration order | existing | branch, origin outdated |
| — | A6 | Keep and render availability of conformances declared in extensions | existing | branch, pushed (on A5) |
| — | A7 | Describe availability changes per platform | existing | branch, pushed (on A6) |
| — | A8 | Pair standalone extensions by conformance and members | existing | branch, pushed |
| P1 | C1 | Duplicate declarations from `#if` feature-check clauses | correctness | superseded by C10 (branch `evaluate-conditional-compilation` obsolete) |
| P1 | C2 | Macro declarations are not parsed | coverage | branch `parse-macro-declarations`, pushed |
| P1 | C3 | Consolidator drops paired changes without differences | correctness | new |
| P2 | C4 | Import and `@_exported import` changes are not reported | coverage | new |
| P2 | C5 | Description fallback pairs with already-matched elements | correctness | branch `parse-macro-declarations`, pushed |
| P3 | C6 | Operator and `precedencegroup` declarations are not parsed | coverage | new |
| P3 | C7 | `deinit` declarations are not parsed | coverage | new |
| P2 | C10 | Report changes in all `#if` branches, tagged with their conditions (replaces C1's evaluation) | coverage | implemented on `combine-standalone-extensions`, pushed |
| P1 | C11 | Extension members falsely reported as removed when a type is split into `#if` variants | correctness | implemented on `combine-standalone-extensions`, pushed |
| P2 | C8 | Reference tests ignore extra output lines | test correctness | new |
| P2 | C9 | Merged standalone extensions report false additions | correctness | branch `combine-standalone-extensions`, pushed (on A6) |
| P1 | D1 | Document the comparison behavior | docs | new |
| P2 | R1 | Classify changes as breaking / non-breaking | report | new |
| P2 | R2 | Summarize bulk availability changes | report | new |
| P3 | R3 | Compare exported symbols (`.tbd`) for binary breaks | coverage (ABI) | new |
| P3 | F1 | Module-selector normalizer rebuilds the syntax tree | performance | new |
| P3 | F2 | Parse old and new interface concurrently | performance | new |
| P3 | F3 | Cache descriptions and index children in the analyzer | performance | new |

Suggested labels: `correctness`, `coverage`, `report`, `performance`, `existing-work`.

---

## Part A: Work already done (for PRs and release notes)

These describe changes that already exist. Open one issue per item and link the PR, so the release notes can be generated from closed issues.

For upstream PRs, the A- and C-items are bundled into 5 stacked PRs: `xcode-27-interfaces` (A1, A4) → `normalize-declaration-comparison` (A2, A3) → `macros-and-pairing` (A8, C2, C5) → `extension-merging-and-availability` (A5–A7) → `conditional-compilation` (C9–C11). The last one has the same code as `projected-main` (131 unit + 2 reference tests pass). Paste-ready PR descriptions are in [upstream-prs.md](upstream-prs.md). The per-item branches named below were deleted after bundling, except `normalize-api-diff-ordering`, which the PoC pins.

### A1: Update SwiftSyntax to 604 and normalize module selectors

**Status:** on fork `main` (712a8fa), not upstream.

Xcode 27 interfaces spell types with module selectors (`Swift::String`) instead of `Swift.String`. Comparing an older interface with a newer one reported almost every declaration as changed.

- Updates swift-syntax to 604 (parses `::`) and swift-testing to 6.4.1.
- Adds `ModuleSelectorNormalizer`, which rewrites selectors of imported modules to the legacy dot spelling.
- Fixes a missed change when two unlabeled parameters exist (`_ first: Int, _ second: Int` → `String`).
- Caches recursive descriptions during one analysis.

### A2: Normalize availability ordering and detect reordered parameters

**Branch:** `normalize-api-diff-ordering` (0683c34, pushed, pinned by the PoC).

The same `@available` platforms listed in a different order were reported as a change. Parameters that moved position weren't reported.

### A3: Ignore internal parameter names when comparing declarations

**Branch:** `ignore-internal-parameter-names` (471cdac).

Renaming an internal parameter name (`label oldName:` → `label newName:`) doesn't change the call signature, but was reported as a modification. Declarations are now compared without internal names. Output still shows them, and external label changes are still reported.

### A4: Resolve module selectors of transitively imported modules in overlays

**Branch:** `normalize-overlay-module-selectors` (654cb88).

SDK overlays (`@_exported import Framework`) refer to modules the framework imports transitively (`Input::Value`). They weren't normalized, so every such declaration showed up as changed. If the module re-exports itself, all modules used in selectors are treated as known.

### A5: Make extension merging independent of declaration order

**Branch:** `order-independent-extension-merging` (c1bc42f, pushed).

Merging extensions into their type depended on declaration order, so reordering between SDK builds produced many false removals and additions. In 27.2 → 27.3 this hit SwiftUI `TabContent`, `Table`, `WindowGroup`, Foundation `Locale.Components` and all of TipKit.

- The extended type is matched on whole path components, trying every candidate. Before, `extension M.TabContent` went into `struct M.Tab` because of a plain `hasPrefix`.
- Shallower extensions are merged first.
- An extension's `@available` is carried onto its merged members, while a member's own `@available` for a platform takes precedence.

**Result:** removals in 27.2 → 27.3 went from 271 to 6, with every original record accounted for. "⚠ We should not end up here" warnings went from 169 to 0.

### A6: Keep and render the availability of conformances declared in extensions

**Branch:** `conformance-availability` (60d6613, 0e36d2c, on A5).

A conformance added by an `@available` extension lost its availability when merged, so availability changes of conformances were invisible. Examples: `extension Sentiment: Hashable` arriving on tvOS 27.0, and `ActivityStyle: Hashable` on macOS 27.3. These conformances are now rendered the way the interface declares them:

```swift
@available(iOS 16.1, *)
public enum ActivityStyle

@available(iOS 16.1, macOS 27.3, *)
extension ActivityStyle: Swift.Equatable
```

### A7: Describe availability changes per platform

**Branch:** `describe-availability-changes` (56e4d73, on A6).

Before, a change showed as four added/removed attribute lines. Now it reads `Availability added: macOS 27.3, Mac Catalyst 27.3`. Also covered: changed and no longer declared versions, marked or no longer unavailable, deprecation (including messages and renames), obsoletion, and conformance availability. Unknown arguments fall back to the old wording.

### A8: Pair standalone extensions by conformance and members

**Branch:** `pair-extensions-by-conformance` (542ad33).

Extensions that can't be merged (e.g. of `Swift.Never`) were paired with the first extension of the same type once their header changed. That produced "Added inheritance `DynamicInstructions`" for `extension Never: Generable`, and could cancel out a real change. Pairing now prefers the same conformances, then shared conformances, then the most matching members, and never reuses an exact counterpart.

---

## Part B: Correctness and coverage

### C1: Duplicate declarations from `#if` feature-check clauses (P1)

**Problem:** The parser walks every clause of an `#if`, so a declaration that the interface spells twice (once for current compilers, once as a fallback for older ones) exists twice in the diff.

```swift
#if compiler(>=5.3) && $TildeSendable
public struct UIShape: UIKit.UIShapeProvider, ~Swift.Sendable { … }
#else
public struct UIShape: UIKit.UIShapeProvider { … }
#endif
```

**What's in the 27.3 SDK** (24 interfaces, about 2,050 `#if`s, 2 `#elseif`s):

None of the conditions check a platform or architecture. All of them check the compiler or a language feature, so the `#else` clause is the same declaration written for an older compiler, not a different API.

| Condition | Count | `#if` clause vs. `#else` |
|---|---|---|
| `$TildeSendable` | 751 | adds `~Swift.Sendable` to the inheritance clause |
| `$Lifetimes` | 368 | e.g. `@_lifetime(…)` (active) vs. `@lifetime(…)` (fallback) |
| `$LifetimeDependence` (+ `Inout…`, `…MutableAccessors`) | 353 | no `#else`: only declared for compilers with the feature |
| `$InlineAlways` | 148 | `@inline(always)` vs. `@inline(__always) @inlinable` |
| `$AsyncExecutionBehaviorAttributes` | 124 | no `#else` |
| `$ABIAttributeSE0479` | 65 | `@abi(…)` vs. `@_silgen_name(…)` |
| `$Builtin…` | ~95 | differences in inlinable bodies only (not parsed) |
| `$NonexhaustiveAttribute` | 14 | adds `@nonexhaustive` |
| `hasAttribute(c)` | 7 | `@c(…)` vs. `@_cdecl(…)` |
| `!$Embedded` | 27 | mostly no `#else` |

**Impact:** 725 duplicated types. In 27.2 → 27.3 the duplicates caused:
- AVFAudio `@lifetime` noise;
- double-counted FoundationModels records;
- fake changes when variants were paired across clauses (mostly fixed by C5).

**Proposed fix:** evaluate `#if` the way the compiler that consumes the interface would.

1. **Evaluate conditions with `SwiftIfConfig`** (part of swift-syntax, already a dependency). Use a build configuration for a current toolchain:
   - true: `compiler(…)`, `swift(…)`, `$Feature`, `hasFeature`, `hasAttribute`;
   - false: `$Embedded`;
   - throws "unknown": platform, architecture, `targetEnvironment` and `canImport`.
2. **Parse only the active clause.** If a condition can't be evaluated, keep today's behavior (walk all clauses) and log it once per interface.
3. **Use the same configuration for the old and new interface,** so both are compared as the same current compiler sees them. Declarations without an `#else` stay, because the current compiler sees them.

**How changes are communicated:**
- **Per change:** nothing special. A declaration is shown and compared as the current compiler sees it. If a type moves behind `#if $TildeSendable` with `~Sendable`, the report says "Added inheritance `~Swift.Sendable`", which is the actual API change. Fallback spellings (`@_lifetime`, `@_silgen_name`, `@inline(__always)`) never appear.
- **In the report:** one line in the summary saying which configuration was used, e.g. "Conditional compilation evaluated for a current compiler (all language features enabled)". It also lists any `#if` conditions that couldn't be evaluated and were included in full.
- **In the docs:** a section in D1.
- **Feature gates and fallback clauses:** see C10, which replaces the active-clause evaluation with condition tagging.

**Tests:**
- `$TildeSendable` with `#else` (the active clause wins, no duplicate);
- `@lifetime` vs. `@_lifetime`;
- a declaration without `#else` (kept);
- nested `#if` inside a member list;
- `!$Embedded`;
- `#elseif`;
- an `os(…)` condition (all clauses kept);
- the same declaration moving into a gated clause between versions.

**Regression check:** records should only disappear when they are artifacts of the duplicates. Each lost record has to be traced back to a variant pairing or a double count.

**Branch:** `evaluate-conditional-compilation` off `main`, since the parser change is independent. Then merge it into `projected-main`.

**Status:** superseded by C10. It was implemented on `evaluate-conditional-compilation` (cb94c79), but `projected-main` no longer contains it: C10 compares every clause instead of evaluating for a current compiler. The branch is kept for reference only (`backup/projected-main-with-c1` points at the old `projected-main`). What follows describes the C1 implementation.
- `#if` conditions are evaluated with `SwiftIfConfig` (`CurrentCompilerBuildConfiguration`), and only the active clause is parsed. This also applies to `#if`s inside attribute lists.
- Conditions that can't be evaluated keep all clauses and are logged through the logger.
- The Markdown report states how `#if`s were evaluated (one line under "Analyzed targets").
- The merge combines this with A2's availability normalization in `AttributeListSyntax.sanitizedList`.

**Result for 27.2 → 27.3:** 21 fewer modifications (925 → 904), none of them real.
- **AVFAudio:** 7 duplicate span properties.
- **FoundationModels:** 6 duplicate enums without `@nonexhaustive`, plus `SessionState` is now shown with `@abi` instead of the `@_silgen_name` fallback.
- **One real change surfaced:** SwiftUICore `ArrangementViewStyleConfiguration.Primary`/`.Secondary` lost their `Swift.Sendable` conformance (27.2 declares `extension …Primary: Swift.Sendable {}`, 27.3 doesn't). The duplicates had hidden it.

**Not covered yet:** the PoC's JSON adapter doesn't pass a logger, so conditions that can't be evaluated aren't visible there. None exist in the 27.2/27.3 SDKs.

### C10: Report changes in other `#if` configurations (P2, follow-up of C1)

**Problem:** Since C1, an interface is compared the way a current compiler sees it. Changes that only affect other configurations go unreported:
- **Fallback clauses:** a change that only exists in the `#else` (older compiler) branch.
- **Feature gates:** a declaration that only exists inside an `#if $Feature` clause without `#else`. Examples in the 27.3 SDK are about 350 `$LifetimeDependence` and 124 `$AsyncExecutionBehaviorAttributes` declarations.
- **Gate changes:** a declaration moving behind a feature gate, or out of one.

For Apple SDKs this is a secondary concern, because each Xcode ships its own compiler. For libraries distributed as binaries with `.swiftinterface` files (library evolution), consumers can use other compiler versions. A change in a fallback clause can then break those consumers, which matters for breaking-change evaluation (R1). The same applies to a website comparing SDK versions, where viewers may want to see these changes too.

**Proposed fix:** compare every clause, report every change, and tag each change with its conditions. There is no "current compiler" view anymore: a change in any branch is a change.

1. **Parse all clauses again, and tag every element with its conditions.** A declaration in `#if $TildeSendable` gets `$TildeSendable`, and its `#else` counterpart gets `!$TildeSendable`. `#elseif` clauses get the negation of the earlier conditions plus their own. Members inherit the conditions of their enclosing declarations. The tags are metadata, not part of the description.
2. **Pair within the same conditions.** The `#if` variant of a declaration is only compared with the `#if` variant in the other version, so variants are never mixed. This replaces C1's active-clause evaluation: no fake changes from mixing variants, and changes in fallback clauses are found too.
3. **Pair across conditions as a fallback.** If no counterpart with the same conditions exists, pairing across conditions turns a gate change into one change instead of a removal plus an addition: "Now requires compiler feature `$LifetimeDependence`" / "No longer requires compiler feature …".
4. **`#if` inside attribute lists** (e.g. `@nonexhaustive` behind `$NonexhaustiveAttribute`, `@abi` vs. `@_silgen_name`): keep every clause's attributes, each annotated with its condition, so a change in any clause shows up as an attribute change.
5. **Output:**
   - **Markdown:** every change, with its conditions shown next to it when it has any (e.g. "`#if $TildeSendable`"). Unconditional changes look as they do today.
   - **JSON:** every change gets a `conditions` field (empty for unconditional ones). A top-level `conditions` section lists every condition found with its count, so a website can filter on demand.
   - Conditions of any kind (`os(…)`, `canImport(…)`, custom flags) are treated the same way, so nothing has to be evaluated and nothing is "unknown".

**What this removes:** `CurrentCompilerBuildConfiguration`, the `SwiftIfConfig` dependency, the unevaluated-conditions logging and the "Conditional compilation evaluated for a current compiler" line from C1. The C1 tests stay and change their expectations (both variants kept, tagged, never paired with each other).

**Trade-off:** a declaration that changes in both variants is reported twice, once per condition set, because the spellings differ (`@lifetime` vs. `@_lifetime`). This is accepted: `#if` branches in interfaces change rarely, and in 27.2 → 27.3 C1 removed only ~21 such records. The duplicates are visibly tagged, so they don't read as noise.

**Effort and risks:**
- Extension merging (A5) has to merge an extension into every variant of a type whose conditions are compatible. Today it only merges into the first variant, which is how the SwiftUICore `Primary: Sendable` removal was hidden.
- Combining standalone extensions (C9) has to group by conditions as well.
- Overload pairing (C5) ranks same-condition candidates before cross-condition ones.

**Regression check (27.2 → 27.3, against `pm7`):** every C1 result stays (no fake variant changes, the `Primary`/`Secondary` `Sendable` removal is still found); new records must be changes in fallback or gated clauses, each tagged.

**Status:** implemented on `combine-standalone-extensions` together with C9 (0c88b71, 1bbfd99) and merged into `projected-main` (1935e82), replacing C1.
- The condition is stored as the first attribute(s) of a declaration (`#if $X`), so variants have different descriptions, standalone extensions are combined per condition (C9) and a gate change shows up as "Added condition `#if $X`" / "Removed condition …".
- Pairing (C5) ranks the same conditions first, also when matching extensions.
- **Deviation from the plan:** an extension is merged into one variant of a type, not into all of them: the variant whose conditions are a subset of the extension's (most shared first), otherwise the first variant. This is the same in both versions, so changes are found once and nothing has to be copied.
- `#if` inside attribute lists keeps every clause as `#if $X @attr #endif`.
- `Change.conditions` carries all conditions including the enclosing declarations'. The Markdown output prints `// Conditions: …` above a change. The PoC adapter emits `conditions` per record. The top-level `conditions` summary for a website isn't built yet; it can be derived from the records.

**Result for 27.2 → 27.3** (`pm8` vs. `pm7`): modifications 904 → 925, additions and removals unchanged. All 22 new records are fallback twins of a change that was already reported, each tagged with its condition. The 22 include `SessionState`, now reported with both its `@abi` and `@_silgen_name` spellings.
- AVFAudio: 7 span properties (`@lifetime` variant next to `@_lifetime`).
- FoundationModels: 13 declarations without `@nonexhaustive`, plus `SessionState`.
- SwiftUICore: `ArrangementViewStyleConfiguration.Primary`/`.Secondary`.

C1's real finding (`Primary`/`Secondary` lost `Swift.Sendable`) is still reported, and no record was lost. 104 records carry conditions. No gate changes occur in this SDK pair.

### C11: Extension members falsely reported as removed when a type is split into `#if` variants (P1, found with C10)

**Problem:** An extension is merged into one variant of a type. When none of the variants matches the extension's conditions, it goes into the first variant. If a type is declared once in the old version and split into `#if`/`#else` variants in the new one, the old declaration is paired with the `#else` variant, but the extension's members end up in the `#if` variant.

**Example** (`docs/examples/conditions`): `Shape` becomes `#if $TildeSendable … #else … #endif`, and `#if !$Embedded extension Shape { describe(); area() }` is merged into the `$TildeSendable` variant. The report shows a false "Removed `describe()`", and the new `area()` is hidden inside the added `Shape` variant.

**Proposed fix:** merge an extension into every variant of the type when none of them matches its conditions (copying its members, e.g. by parsing the extension again for each variant). A change to such a member is then reported once per variant, which is accepted for C10.

**Acceptance criteria:**
- The example reports `area()` as added for the `#else` variant and no removal of `describe()`.
- 27.2 → 27.3 loses no records.

**Status:** implemented on `combine-standalone-extensions` (13b990f) and merged into `projected-main` (436c0da). The parser keeps the syntax of every extension and parses it again for each extra variant.
- **Example:** the false "Removed `describe()`" is gone. `area()` is reported as added for the `#else` variant (`#if !(compiler(>=5.3) && $TildeSendable) && !$Embedded`).
- **Result for 27.2 → 27.3** (`pm9` vs. `pm8`): modifications 925 → 957, no record lost.
  - **SwiftUICore:** the record count is unchanged. The `#else` variants of `ArrangementViewStyleConfiguration.Primary`/`.Secondary` now report "Removed inheritance `Swift.Sendable`" too. That extension is unconditional, so it applies to both variants; before, only the `#if` variant showed it.
  - **FoundationModels:** 32 more records. Extension members of the enums declared with and without `@nonexhaustive` (`$NonexhaustiveAttribute`) now exist in both variants, so each "Availability added: tvOS 27.0" is reported per variant: 44 records under each condition, all exact twins.
- **Decision:** twins stay separate records. Each `#if` branch is its own code, so a change in each branch is a separate change.

### C2: Macro declarations are not parsed (P1)

**Problem:** `SwiftInterfaceParser` has no visitor for `MacroDeclSyntax`, so macros never show up in a diff.

**Impact in 27.2 → 27.3:** 12 new public macros are missing from the report:
- **AppIntents:** `@AppEntity(_:)`, `@AppIntent(_:)`, 3× `@ComputedProperty`, 2× `@DeferredProperty`.
- **FoundationModels:** 3× `@Guide` overloads.

The 27.3 SDK has 57 macro declarations in 11 modules.

**Proposed fix:** Add a `SwiftInterfaceMacro` element: attributes such as `@attached(...)`/`@freestanding(...)`, name, generic parameters, signature and `where` clause. The diffable signature works like a function's. Compare the `#externalMacro(module:type:)` definition too, because a different implementation module is an observable change.

**Acceptance criteria:**
- Added, removed and modified macros are reported.
- Changes to the role attribute (`@attached(peer)` → `@attached(peer, names: …)`) are described.
- Reference package tests include a macro.

**Status:** implemented on `parse-macro-declarations` (6132c24) and merged into `projected-main`. In the merge, macros also ignore internal parameter names (A3). Result for 27.2 → 27.3: 12 macros added, 8 macro availability changes, 0 records lost.

**Known limitations (follow-ups):**
- Module selectors inside attribute arguments (`@attached(extension, conformances: FoundationModels::Generable)`) aren't normalized, because the normalizer only rewrites type syntax. This is consistent between two Xcode 27 SDKs but would show up as a change against older interfaces.
- `@Guide<RegexOutput>(description:_:)` and `@Guide<T>(description:_:)` share the diffable signature `Guide(description:_:)`, so they can be mis-paired (see C5).

### C3: Consolidator drops paired changes without differences (P1)

**Problem:** `SwiftInterfaceChangeConsolidator.consolidate` pairs a removal with an addition. If `listOfChanges` comes back empty, it prints "⚠ We should not end up here" and `continue`s, so **both changes are lost**.

**Impact:** 0 cases since A5 (169 before), but any future regression would lose changes silently instead of showing them.

**Proposed fix:**
- Emit both as a plain removal and addition, or as a modification with a generic "Declaration changed" detail.
- Log the warning through the logger instead of `print`.
- Add a test that forces this path.

**Acceptance criteria:**
- No code path drops an independent change.
- A test proves it.

### C4: Import and `@_exported import` changes are not reported (P2)

**Problem:** Imports are only used to normalize selectors. They aren't part of the diff.

**Impact:**
- Dropping an `@_exported import` breaks callers that rely on the re-export.
- A new `@_exported import` widens the API.
- 27.3 SDK: 190 `@_exported import`s in 160 modules. QuickLook now imports `Photos` and `_PhotosUI_SwiftUI`.

**Proposed fix:** Add an import element at the root, with kind (`@_exported`, `@_implementationOnly`, `@preconcurrency`, plain) and path. Report changes to `@_exported` imports by default, and plain imports optionally.

**Acceptance criteria:**
- An added or removed `@_exported import` shows up as an addition or removal on the module.

### C5: Description fallback pairs with already-matched elements (P2)

**Problem:** In `SwiftInterfaceAnalyzer.recursiveCompare`, non-extension elements use `rhs.children.first(where:)` for the description match and for the `isDiffable` fallback. Neither excludes elements that are already the exact counterpart of another element. A8 fixed this for extensions only.

**Impact:** With duplicate declarations (C1) or overloads that share a description, a changed element can be compared against the wrong counterpart. Its change is then reported against the wrong element or cancels out.

**Proposed fix:** Apply the same `excluding: exactCounterparts` logic and best-match scoring to all element kinds.

**Acceptance criteria:**
- A test with two same-description declarations, one changed, reports exactly that change.
- Overloads with the same labels but different parameter types pair with their own counterpart.

**Status:** implemented on `parse-macro-declarations` (8a03982) and merged into `projected-main` (c994385). Non-extension elements are paired once per scope:
- Elements that are the exact counterpart of another element are excluded.
- Each element is paired at most once.
- Same description is preferred first, then "only attributes or modifiers differ", then other comparable elements. Within each group, fewest differences and most matching children win.
- The consolidator keeps compared pairs together.

Extensions keep their many-to-one pairing, because blocks can be split or merged (see C9).

**Result for 27.2 → 27.3:** 72 records re-paired, 1 new addition, 0 lost.
- **FoundationModels:** 59 records now only report "Availability added". The removed details were all mis-pairings: 54 parameter type changes, a fake `@nonexhaustive` added (27.2 already declares it in an `#if` branch), `@_disfavoredOverload` changes, and generic parameter changes.
- **AVFAudio:** the `@lifetime` vs. `@_lifetime` noise is gone.
- **HomeExtensions** and **AccessoryTransportExtension:** default implementations are no longer compared with protocol requirements.
- **IdentityDocumentServicesUI:** the new `buildLimitedAvailability(_: any …)` overload was hidden before and is now reported.

**Evidence (27.2 → 27.3, with C2):** both FoundationModels `@Guide(description:_:)` overloads gained tvOS availability. The `Regex` overload was paired with the `GenerationGuide<T>` overload and reported as "Modified generic parameter description from `<RegexOutput>` to `<T>`" plus a parameter type change. The same applies to functions that are overloaded only by type.

### C6: Operator and `precedencegroup` declarations are not parsed (P3)

**Problem:** `OperatorDeclSyntax` and `PrecedenceGroupDeclSyntax` are ignored.

**Impact:** The 27.3 SDK has 79 operator declarations in 10 modules and 13 precedence groups in 1 module. Nothing changed in 27.3, but a change in associativity or precedence would go unreported.

**Proposed fix:** Add elements for both and compare their attributes (`higherThan`, `lowerThan`, `associativity`, `assignment`).

### C7: `deinit` declarations are not parsed (P3)

**Problem:** `DeinitializerDeclSyntax` is ignored.

**Impact:** The 27.3 SDK has 818 of them. They rarely matter for clients, but `isolated deinit` and availability attributes are observable.

**Proposed fix:** Add a minimal element (attributes, modifiers).

### C8: Reference tests ignore extra output lines (P2)

**Problem:** `ReferencePackageTests` only compares lines up to the expected line count, and only reports the first mismatch. Output that adds changes after the last expected line passes.

**Proposed fix:** Compare the line counts too, and report a unified diff on failure.

Also, `setUp` skips rebuilding the reference packages if `.build/Build` exists, so a stale build can hide source changes locally.

### C9: Merged standalone extensions report false additions (P2)

**Problem:** Extensions that can't be merged into their type (e.g. `extension SwiftUICore.View` in SwiftUI) are compared block by block. If two blocks are merged into one, the new-to-old pass compares the merged block with only one of the old blocks. The members of the other block are reported as added. The same happens the other way round for split blocks.

**Example (unit test, already fails on `main`):** old `extension Other.View { first() }` and `extension Other.View { second() }`, new `extension Other.View { first(); second() }`. This reports `second()` as added.

**Proposed fix:** Compare standalone extensions of the same type (and the same generic `where` clause) as one combined set of members, keeping per-extension attributes on the members. This is similar to how A5 carries extension availability onto merged members.

**Acceptance criteria:**
- Splitting or merging extension blocks reports no changes.
- Moving a member between blocks with different availability reports the availability change.

**Status:** implemented on `combine-standalone-extensions` (1772a56, on A6) and merged into `projected-main` (e02ae52).
- Standalone extensions are combined into one per extended type, generic `where` clause and non-availability attributes/modifiers.
- Each block's `@available` moves onto its members.
- Conformances keep their own availability and are rendered as `@available(…) extension X: P`.
- The merge adapts one A8 test: the three `Swift.Never` conformances now form one combined extension with three conformance availability changes.

**Result for 27.2 → 27.3:** 82 records changed shape, none lost (each was checked against the new records). Modifications went from 838 to 925, because a header availability change on an extension block is now reported on each member, the same as for extensions merged into their type (A5). R2 grouping will summarize these. Added (158) and removed (6) are unchanged.

---

## Part D: Documentation

### D1: Document the comparison behavior (P1)

**Problem:** How the engine normalizes and pairs declarations is only documented in commit messages, code comments and tests. Readers of a report can't tell why something shows up the way it does, e.g. why a member carries an `@available` it doesn't declare, or why a conformance is rendered as an extension.

**Proposed fix:** Add `Docs/ComparisonBehavior.md` to the engine, linked from the README. Each rule gets a short before/after example and a link to its test:
- **Parsing:** which declarations are covered (and which are not yet: operators, `deinit`, imports), and how all `#if` clauses are walked (until C1).
- **Normalization:**
  - module selectors (A1, A4)
  - availability ordering (A2)
  - internal parameter names (A3)
  - whitespace in macro definitions (C2)
- **Extensions:**
  - merging into the extended type (A5)
  - combining standalone extensions (C9)
  - inherited availability, with member precedence per platform
  - conformance availability rendered as extensions (A6)
- **Pairing:**
  - exact match, then same description, then signature (C5)
  - overloads
  - extension pairing (A8)
  - consolidation of removal + addition into a modification
- **Change descriptions:** per-platform availability wording (A7) and attribute, parameter and inheritance changes.
- **Known limitations:** C1, C4, C6–C8, R1–R3.

**Acceptance criteria:**
- Every normalization and pairing rule has an example and a linked test.
- The release notes can link to the relevant sections.

---

## Part C: Report quality

### R1: Classify changes as breaking / non-breaking (P2)

**Problem:** All changes look the same. Source-breaking changes get lost among hundreds of availability changes.

**Example:** In 27.3, `IdentityDocumentWebPresentmentRawRequest.RequestType` gained a case with an associated value. That silently drops the implicit `Equatable`/`Hashable` synthesis, which is a source break and a binary break. The report lists it, but nothing marks it as breaking.

**Proposed fix:** Add a `severity` field (`breaking`, `potentially breaking`, `additive`, `informational`) to `Change`. Initial rules:
- **Breaking:** removed declaration, removed conformance, added protocol requirement without a default, new `unavailable` platform, narrowed access, changed parameter type or label.
- **Potentially breaking:** a new case on a non-frozen public enum that clients may switch over, and changes to `throws`/`async`.
- **Additive:** additions, availability added.
- **Informational:** deprecations, attribute changes.

**Acceptance criteria:**
- The JSON output includes a severity.
- Tests cover each rule.
- The PoC renders breaking changes first.

### R2: Summarize bulk availability changes (P2)

**Problem:** 726 of 830 modifications in 27.2 → 27.3 only change availability: 545× "Availability added: tvOS 27.0", 93× "macOS 27.3, Mac Catalyst 27.3", 60× "iOS 27.0 → 27.2".

**Proposed fix:** Keep the per-declaration records, but tag them as `availabilityOnly` so the output generator (and the PoC renderer) can group them under one summary line per platform and version, with the list collapsed.

**Acceptance criteria:**
- The Markdown and HTML outputs show one group per distinct availability change.
- Other modifications stay listed individually.

### R3: Compare exported symbols (`.tbd`) for binary breaks (P3)

**Problem:** The interface diff only shows source-level changes. Binary breaks (symbols removed from the dylib) are only visible in the SDK's `.tbd` stubs.

**Example:** The `RequestType` case dropped 3 conformance descriptors, plus `==`, `hash(into:)` and `hashValue`, from the `.tbd`.

**Proposed fix:** This probably belongs in apple-sdk-api-watch rather than the engine. Diff the exported symbol lists per framework, demangle them with `swift-demangle`, and attach removed symbols to the matching declaration where possible.

---

## Part D: Performance

Measured with a release build of `projected-main`:

| Module | Now | Without normalizer |
|---|---|---|
| Swift stdlib | 12.0 s, 1.6 GB peak | 3.1 s |
| SwiftUICore | 6.7 s | 2.9 s |
| Foundation | 6.1 s | 2.1 s |
| AppIntents | 4.8 s | 1.9 s |

### F1: Module-selector normalizer rebuilds the syntax tree (P3)

**Problem:** `ModuleSelectorNormalizer` is a `SyntaxRewriter`. Every replaced type rebuilds its ancestors (`Syntax.replacingSelf`), which takes 60–75% of run time on large modules and drives the 1.6 GB peak.

**Proposed fix:** Normalize when an element's description strings are created, by rewriting `Module::Name` in the type strings while keeping the collected `modules` set, instead of rewriting the tree.

**Acceptance criteria:**
- Identical JSON output for the 27.2 → 27.3 snapshots.
- Swift stdlib runs in ≤ 4 s.

### F2: Parse old and new interface concurrently (P3)

**Problem:** `SwiftInterfaceDiff.run` parses the new and then the old file one after the other. Parsing is about 75% of the remaining time.

**Proposed fix:** Parse both files concurrently with `async let`.

### F3: Cache descriptions and index children in the analyzer (P3)

**Problem:**
- `description(incl:)` isn't cached. It is rebuilt inside the scans that compare every old child against every new child, and inside sort comparators.
- The consolidator is quadratic (`removeFirst` plus linear search).
- Parsing copies syntax nodes to strip trivia (`.trimmed`, `.with(\.leadingTrivia…)`) where `trimmedDescription` would do.

**Proposed fix:**
- Cache descriptions per element and token set.
- Build dictionaries of children by description and by `diffableSignature` for each scope.
- Group the consolidator's changes by `consolidatableName` and parent path.

**Acceptance criteria:**
- Identical output.
- Measurable speedup on the Swift stdlib.

---

## Notes

- Every fix must keep the 27.2 → 27.3 regression check green: each record in the previous report is either kept or explained.
- Upstreaming to Adyen is a separate decision. A1–A8 are generic improvements and would all be candidates.

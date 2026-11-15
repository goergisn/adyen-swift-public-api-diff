//
// Copyright (c) 2026 Adyen N.V.
//
// This file is open source and available under the MIT license. See the LICENSE file for more info.
//

import Foundation
import PADCore

struct SwiftInterfaceAnalyzer: SwiftInterfaceAnalyzing {

    let changeConsolidator: SwiftInterfaceChangeConsolidating

    init(changeConsolidator: SwiftInterfaceChangeConsolidating = SwiftInterfaceChangeConsolidator()) {
        self.changeConsolidator = changeConsolidator
    }

    func analyze(
        old: some SwiftInterfaceElement,
        new: some SwiftInterfaceElement
    ) -> [Change] {

        RecursiveDescriptionCache.withCache {
            // Very naive diff from both sides
            // There is room for improvement here but it's "performant enough" for now

            let individualChanges = Self.recursiveCompare(
                element: old,
                to: new,
                oldFirst: true,
                isRoot: true
            ) + Self.recursiveCompare(
                element: new,
                to: old,
                oldFirst: false,
                isRoot: true
            )

            // Matching removals/additions to changes when applicable
            return changeConsolidator.consolidate(individualChanges)
        }
    }

    private static func recursiveCompare(
        element lhs: some SwiftInterfaceElement,
        to rhs: some SwiftInterfaceElement,
        oldFirst: Bool,
        isRoot: Bool = false
    ) -> [IndependentSwiftInterfaceChange] {

        var changes = [IndependentSwiftInterfaceChange]()

        if lhs.recursiveDescription() == rhs.recursiveDescription() { return changes }

        if !isRoot, oldFirst, lhs.description != rhs.description {
            changes += independentChanges(from: lhs, and: rhs, oldFirst: oldFirst)
        }

        let exactMatches = Set(rhs.children.map { $0.recursiveDescription() })
        // Elements of `rhs` that are an exact counterpart of an element of `lhs` are accounted for
        // and must not be paired with another element as well
        let exactCounterparts = Set(lhs.children.map { $0.recursiveDescription() })
        let unmatchedElements = lhs.children.filter { !exactMatches.contains($0.recursiveDescription()) }
        let availableElements = rhs.children.filter { !exactCounterparts.contains($0.recursiveDescription()) }

        // Overloads can share a description or diffable signature (e.g. `guide(_:)`),
        // so (non-extension) elements are paired with their most similar counterpart
        let pairs = pairElements(
            unmatchedElements.filter { !($0 is SwiftInterfaceExtension) },
            with: availableElements.filter { !($0 is SwiftInterfaceExtension) }
        )

        for lhsElement in unmatchedElements {

            // Trying to find a matching element
            //
            // Elements with an exact match based on the recursive description are skipped above
            // as we don't want to match a non-change with a change
            //
            // This is especially important for extensions where the description might
            // be the same for a lot of different extensions but the body might be completely different

            let match: (any SwiftInterfaceElement)? = if lhsElement is SwiftInterfaceExtension {
                // First checking if we found a match based on the description
                // For extensions, we need special handling to find the best match based on child similarity
                // (Extensions can be split or merged, so several extensions can be compared with the same one)
                findBestExtensionMatch(for: lhsElement, among: rhs.children.filter { $0.description == lhsElement.description })
                    // ... then losening the criteria to find a comparable element
                    ?? rhs.children.first(where: { $0.isDiffable(with: lhsElement) })
            } else {
                pairs[ObjectIdentifier(lhsElement)]
            }

            if let match {
                // We found a comparable element so we check if the children changed
                changes += Self.recursiveCompare(element: lhsElement, to: match, oldFirst: oldFirst)
                continue
            }

            // No matching element was found so either it was removed or added
            let changeType: IndependentSwiftInterfaceChange.ChangeType = oldFirst ?
                .removal(lhsElement.recursiveDescription()) :
                .addition(lhsElement.recursiveDescription())

            changes.append(
                .from(
                    changeType: changeType,
                    element: lhsElement,
                    oldFirst: oldFirst
                )
            )
        }

        return changes
    }

    private static func independentChanges(
        from lhs: any SwiftInterfaceElement,
        and rhs: any SwiftInterfaceElement,
        oldFirst: Bool
    ) -> [IndependentSwiftInterfaceChange] {
        [
            .from(
                changeType: .removal(lhs.description),
                element: lhs,
                oldFirst: oldFirst,
                counterpart: rhs
            ),
            .from(
                changeType: .addition(rhs.recursiveDescription()),
                element: rhs,
                oldFirst: oldFirst,
                counterpart: lhs
            )
        ]
    }
    
    /// Pairs each element of `lhsElements` with at most one comparable element of `rhsElements`
    ///
    /// Elements with the same description are paired first, then elements that only differ in their attributes
    /// or modifiers (e.g. availability), then other comparable elements (see `isDiffable(with:)`).
    /// Within each group the most similar pairs (fewest differences, most matching children) are formed first,
    /// so the result does not depend on the order of declarations. Remaining ties keep the declaration order.
    private static func pairElements(
        _ lhsElements: [any SwiftInterfaceElement],
        with rhsElements: [any SwiftInterfaceElement]
    ) -> [ObjectIdentifier: any SwiftInterfaceElement] {

        var candidatePairs = [(lhsIndex: Int, rhsIndex: Int, rank: [Int])]()
        for (lhsIndex, lhsElement) in lhsElements.enumerated() {
            let lhsDescription = lhsElement.description
            let lhsSignature = lhsElement.description(incl: [])
            for (rhsIndex, rhsElement) in rhsElements.enumerated() {
                let group: Int
                if rhsElement.description == lhsDescription {
                    group = 0
                } else if !rhsElement.isDiffable(with: lhsElement) {
                    continue
                } else if rhsElement.description(incl: []) == lhsSignature {
                    group = 1
                } else {
                    group = 2
                }
                let rank = [group] + similarityScore(of: lhsElement, to: rhsElement) + [lhsIndex, rhsIndex]
                candidatePairs.append((lhsIndex, rhsIndex, rank))
            }
        }

        var pairedLhsIndices = Set<Int>()
        var pairedRhsIndices = Set<Int>()
        var pairs = [ObjectIdentifier: any SwiftInterfaceElement]()
        for candidatePair in candidatePairs.sorted(by: { $0.rank.lexicographicallyPrecedes($1.rank) }) {
            guard !pairedLhsIndices.contains(candidatePair.lhsIndex),
                  !pairedRhsIndices.contains(candidatePair.rhsIndex) else { continue }
            pairedLhsIndices.insert(candidatePair.lhsIndex)
            pairedRhsIndices.insert(candidatePair.rhsIndex)
            pairs[ObjectIdentifier(lhsElements[candidatePair.lhsIndex])] = rhsElements[candidatePair.rhsIndex]
        }
        return pairs
    }

    /// Fewer differences first, then more matching children
    private static func similarityScore(
        of lhsElement: any SwiftInterfaceElement,
        to candidate: any SwiftInterfaceElement
    ) -> [Int] {
        let matchingChildren = lhsElement.children.filter { lhsChild in
            candidate.children.contains { $0.isDiffable(with: lhsChild) }
        }
        return [
            lhsElement.differences(to: candidate).count,
            -matchingChildren.count
        ]
    }

    /// Finds the best matching extension from a list of candidates based on child similarity
    /// Returns nil if no good match is found
    private static func findBestExtensionMatch(
        for lhsElement: any SwiftInterfaceElement,
        among candidates: [any SwiftInterfaceElement]
    ) -> (any SwiftInterfaceElement)? {
        guard !candidates.isEmpty else { return nil }
        
        // If only one candidate, return it
        if candidates.count == 1 {
            return candidates.first
        }
        
        // Calculate similarity score for each candidate based on matching children
        let candidatesWithScores = candidates.map { candidate -> (element: any SwiftInterfaceElement, score: Int) in
            let matchingChildren = lhsElement.children.filter { lhsChild in
                candidate.children.contains { rhsChild in
                    // Check if children match by diffableSignature
                    rhsChild.diffableSignature == lhsChild.diffableSignature &&
                    type(of: rhsChild) == type(of: lhsChild)
                }
            }
            return (element: candidate, score: matchingChildren.count)
        }
        
        // Return the candidate with the highest score
        // If all scores are 0 (no matching children), return the first candidate as fallback
        return candidatesWithScores.max(by: { $0.score < $1.score })?.element
    }
}

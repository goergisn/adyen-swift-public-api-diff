//
// Copyright (c) 2024 Adyen N.V.
//
// This file is open source and available under the MIT license. See the LICENSE file for more info.
//

import SwiftSyntax

extension SyntaxCollection {

    /// Produces a description where all elements in the list are mapped to their `trimmedDescription`
    var sanitizedList: [String] {
        self.map(\.trimmedDescription)
    }
}

extension AttributeListSyntax {

    private var translationTable: [String: String] {
        [
            "@_functionBuilder": "@resultBuilder"
        ]
    }
    
    private var excludedAttributes: Set<String> {
        [
            "@_hasMissingDesignatedInitializers",
            "@_inheritsConvenienceInitializers"
        ]
    }

    /// Produces a description where all elements in the list are mapped to their `trimmedDescription`
    ///
    /// Attributes inside an `#if` are kept per clause together with the clause's condition
    /// (e.g. `#if $NonexhaustiveAttribute @nonexhaustive #endif`, see ``ConditionalCompilation``)
    var sanitizedList: [String] {
        self.flatMap { element -> [String] in
            guard case let .ifConfigDecl(ifConfig) = element else { return sanitized(element).map { [$0] } ?? [] }
            return ConditionalCompilation.clauses(of: ifConfig).flatMap { clause, condition -> [String] in
                guard case let .attributes(attributes) = clause.elements else { return [] }
                return attributes.sanitizedList.map {
                    ConditionalCompilation.conditionalAttribute($0.sanitizingNewlinesAndSpaces, condition: condition)
                }
            }
        }
    }

    private func sanitized(_ element: Element) -> String? {
        var description = element.trimmedDescription
        if let translation = translationTable[description] {
            description = translation
        }
        if excludedAttributes.contains(description) { return nil }
        return description
    }
}

extension InheritedTypeListSyntax {

    /// Produces a description where all elements in the list are mapped to their type's `trimmedDescription`
    var sanitizedList: [String] {
        self.map(\.type.trimmedDescription)
    }
}

extension AccessorBlockSyntax {

    /// Produces a description where all newlines and spaces are replaced by a single space
    ///
    /// e.g. "get\n set\n" -> "get set"
    var sanitizedDescription: String {
        accessors.trimmedDescription.sanitizingNewlinesAndSpaces
    }
}

extension String {

    /// Produces a string where all newlines and spaces are replaced by a single space
    ///
    /// e.g. "get\n set\n" -> "get set"
    var sanitizingNewlinesAndSpaces: String {
        self.replacingOccurrences(of: "[\n ]+", with: " ", options: .regularExpression)
    }
}

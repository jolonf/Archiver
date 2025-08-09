import Foundation
import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Implementation of the `@Archivable` macro. When attached to a class, it:
/// - Synthesizes a `decode(from:schema:)` method that decodes the object's properties from a dictionary.
public struct ArchivableMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf decl: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // Synthesize decode(from:schema:)
        guard let classDecl = decl.as(ClassDeclSyntax.self) else { return [] }
        let propertyNamesAndTypes: [(String, String)] = classDecl.memberBlock.members.compactMap { (member) -> (String, String)? in
            guard let varDecl = member.decl.as(VariableDeclSyntax.self),
                  let binding = varDecl.bindings.first,
                  let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
                  let type = binding.typeAnnotation?.type else {
                return nil
            }
            // Only synthesize for stored instance vars (not static/let)
            if varDecl.bindingSpecifier.tokenKind == .keyword(.var), !varDecl.modifiers.contains(where: { $0.name.tokenKind == .keyword(.static) }) {
                return (pattern.identifier.text, type.description.trimmingCharacters(in: CharacterSet.whitespaces))
            }
            return nil
        }
        let assignments = propertyNamesAndTypes.map { (name, type) in
            "if let value = archive[\"\(name)\"] as? \(type) { self.\(name) = value }"
        }.joined(separator: "\n        ")
        let decodeFunc = """
        public func decode(from archive: [String: Any], schema: ArchivableSchema) throws {
            \(assignments)
        }
        """
        return [DeclSyntax(stringLiteral: decodeFunc)]
    }
    
//    public static func expansion(
//        of node: AttributeSyntax,
//        providingConformancesOf decl: some DeclGroupSyntax,
//        in context: some MacroExpansionContext
//    ) throws -> [TypeSyntax] {
//        return [TypeSyntax(stringLiteral: "Archivable")]
//    }
}


/// Implementation of the `stringify` macro, which takes an expression
/// of any type and produces a tuple containing the value of that expression
/// and the source code that produced the value. For example
///
///     #stringify(x + y)
///
///  will expand to
///
///     (x + y, "x + y")
public struct StringifyMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) -> ExprSyntax {
        guard let argument = node.arguments.first?.expression else {
            fatalError("compiler bug: the macro does not have any arguments")
        }

        return "(\(argument), \(literal: argument.description))"
    }
}

@main
struct ArchiverPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        ArchivableMacro.self,
        StringifyMacro.self,
    ]
}

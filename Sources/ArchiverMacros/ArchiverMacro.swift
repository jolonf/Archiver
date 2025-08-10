import Foundation
import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Implementation of the `@Archivable` macro. When attached to a class, it:
/// - Synthesizes a `decode(from:schema:)` method that decodes the object's properties from a dictionary.
public struct ArchivableMacro: MemberMacro, ExtensionMacro {
    
    public static func expansion(of node: SwiftSyntax.AttributeSyntax,
                                 attachedTo declaration: some SwiftSyntax.DeclGroupSyntax,
                                 providingExtensionsOf type: some SwiftSyntax.TypeSyntaxProtocol,
                                 conformingTo protocols: [SwiftSyntax.TypeSyntax], in context: some SwiftSyntaxMacros.MacroExpansionContext) throws -> [SwiftSyntax.ExtensionDeclSyntax] {
        // Get the type's name from `type`
        let typeName = type.description
        let extensionDecl = ExtensionDeclSyntax(
            extensionKeyword: .keyword(.extension),
            extendedType: TypeSyntax(stringLiteral: typeName),
            inheritanceClause: InheritanceClauseSyntax(
                colon: .colonToken(),
                inheritedTypes: InheritedTypeListSyntax {
                    InheritedTypeSyntax(type: TypeSyntax(stringLiteral: "Archivable"))
                }
            ),
            memberBlock: MemberBlockSyntax(
                leftBrace: .leftBraceToken(),
                members: MemberBlockItemListSyntax([]),
                rightBrace: .rightBraceToken()
            )
        )
        return [extensionDecl]
    }
    
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
            return """
            if let value = archive["\(name)"] {
                self.\(name) = try Archiver.decode(type: \(type).self, from: value, schema: schema)
            }
            """
        }.joined(separator: "\n")
        let decodeFunc = """
        public func decode(from archive: [String: Any], schema: ArchivableSchema) throws {
            \(assignments)
        }
        """
        return [DeclSyntax(stringLiteral: decodeFunc)]
    }
}

@main
struct ArchiverPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        ArchivableMacro.self,
    ]
}


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
        let needsArchivableConformance = protocols.contains { $0.description.trimmingCharacters(in: .whitespaces) == "Archivable" }
        guard needsArchivableConformance else { return [] }
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
    
    /// Synthesize decode(from:schema:)
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf decl: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        var superCall = ""   // added for subclasses of already conforming Archivables
        var overrideStr = "" // added for subclasses of already conforming Archivables
        var mutatingStr = "" // added for structs
        
        let assignments: String
        
        if let classDecl = decl.as(ClassDeclSyntax.self) {
            // Superclass detection (simple version)
            let superclassType: String? = {
                guard let inheritance = classDecl.inheritanceClause else { return nil }
                for inheritedType in inheritance.inheritedTypes {
                    let supertype = inheritedType.type.description.trimmingCharacters(in: .whitespaces)
                    if supertype != "Archivable" {
                        return supertype
                    }
                }
                return nil
            }()
            // Assume superclass conforms to Archivable if present and not NSObject
            let hasArchivableSuper: Bool = (superclassType != nil && superclassType != "NSObject")
            superCall = hasArchivableSuper ? "try super.decode(from: archive, schema: schema)\n" : ""
            overrideStr = hasArchivableSuper ? "override " : ""
            assignments = propertyAssignments(memberBlock: classDecl.memberBlock)
        } else if let structDecl = decl.as(StructDeclSyntax.self) {
            mutatingStr = "mutating "
            assignments = propertyAssignments(memberBlock: structDecl.memberBlock)
        } else if let enumDecl = decl.as(EnumDeclSyntax.self) {
            mutatingStr = "mutating "
            let typeName = enumDecl.name.text
            assignments = """
            if let rawArchive = archive["rawValue"] {
                let raw = try Archiver.decode(type: RawValue.self, from: rawArchive, schema: schema)
                if let type = \(typeName)(rawValue: raw) {
                    self = type
                }
            }
            """
        } else {
            return []
        }

        let decodeFunc = """
        public \(mutatingStr)\(overrideStr)func decode(from archive: [String: Any], schema: ArchivableSchema) throws {
            \(superCall)\(assignments)
        }
        """
        return [DeclSyntax(stringLiteral: decodeFunc)]
    }
    
    /// Generates code to decode and assign dictionary values to property members.
    public static func propertyAssignments(memberBlock: MemberBlockSyntax) -> String {
        let propertyNamesAndTypes: [(String, String)] = memberBlock.members.compactMap { (member) -> (String, String)? in
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
        
        return assignments
    }
}

@main
struct ArchiverPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        ArchivableMacro.self,
    ]
}


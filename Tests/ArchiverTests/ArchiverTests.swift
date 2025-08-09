import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest
import Archiver

// Macro implementations build for the host, so the corresponding module is not available when cross-compiling. Cross-compiled tests may still make use of the macro itself in end-to-end tests.
#if canImport(ArchiverMacros)
import ArchiverMacros

let testMacros: [String: Macro.Type] = [
    "stringify": StringifyMacro.self,
    "Archivable": ArchivableMacro.self
]
#endif

final class ArchiverTests: XCTestCase {
    func testMacro() throws {
        #if canImport(ArchiverMacros)
        assertMacroExpansion(
            """
            #stringify(a + b)
            """,
            expandedSource: """
            (a + b, "a + b")
            """,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testMacroWithStringLiteral() throws {
        #if canImport(ArchiverMacros)
        assertMacroExpansion(
            #"""
            #stringify("Hello, \(name)")
            """#,
            expandedSource: #"""
            ("Hello, \(name)", #""Hello, \(name)""#)
            """#,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
    
    func testArchivableMacroExpansion() throws {
        #if canImport(ArchiverMacros)
        assertMacroExpansion(
            """
            @Archivable
            class TestModel {
                var name: String = ""
                var count: Int = 0
            }
            """,
            expandedSource: """
            class TestModel {
                var name: String = ""
                var count: Int = 0
                public func decode(from archive: [String: Any], schema: ArchivableSchema) throws {
                    if let value = archive[\"name\"] as? String { self.name = value }
                    if let value = archive[\"count\"] as? Int { self.count = value }
                }
            }
            extension TestModel: Archivable {}
            """,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    // MARK: - Schema tests
    func testCreateSchema() {
        let types: [ArchivableClass] = [Container.self, Component.self, Button.self, Field.self]
        let schema = Archiver.createSchema(from: types)
//        print("Inheritance Schema:")
//        for (superId, subclasses) in schema {
//            let subclassNames = subclasses.map { String(describing: $0) }
//            print("Superclass: \(superId) => Subclasses: \(subclassNames)")
//        }
        // Example assertion: Check that Component's subclasses include Component, Button, Field
        let componentSubclasses = schema["Component"]?.map { String(describing: $0) } ?? []
        XCTAssertTrue(componentSubclasses.contains("Component"), "Component should be its own subclass")
        XCTAssertTrue(componentSubclasses.contains("Button"), "Button should be a subclass of Component")
        XCTAssertTrue(componentSubclasses.contains("Field"), "Field should be a subclass of Component")
    }
}

// MARK: - Test Models

class Container: Archivable {
    var title: String? = nil
    var components: [Component] = []
    
    required init() {
    }
    
    func decode(from archive: [String: Any], schema: ArchivableSchema) throws {
        if let componentsProp = archive["components"] {
            if let componentsArray = componentsProp as? [[String: Any]] {
                for compJSON in componentsArray {
                    let component = try Archiver.decode(objType: Component.self, from: compJSON, schema: schema)
                    self.components.append(component)
                }
            }
        }
    }
}

class Component: Archivable {
    var x: Double = 0
    var y: Double = 0
    
    required init() {
    }

    func decode(from archive: [String : Any], schema: ArchivableSchema) throws {
        self.x = archive["x"] as! Double
        self.y = archive["y"] as! Double
    }
}

enum ButtonType {
    case push
    case toggle
}

class Button: Component {
    var type: ButtonType = .push
    var label: String = ""
    
    required init() {
    }

    override func decode(from archive: [String : Any], schema: ArchivableSchema) throws {
        try super.decode(from: archive, schema: schema)
        self.label = archive["label"] as! String
    }
}

class Field: Component {
    var placeholder: String = ""
    
    required init() {
    }

    override func decode(from json: [String : Any], schema: ArchivableSchema) throws {
        try super.decode(from: json, schema: schema)
        self.placeholder = json["placeholder"] as! String
    }
}


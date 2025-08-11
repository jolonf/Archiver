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
    "Archivable": ArchivableMacro.self
]
#endif

final class ArchiverTests: XCTestCase {
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
                    if let value = archive[\"name\"] as? String { 
                        self.name = value 
                    }
                    if let value = archive[\"count\"] as? Int { 
                        self.count = value 
                    }
                }
            }
            extension TestModel: Archivable {
            }
            """,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
    
    func testArchivableRoundTripEncodeDecode() throws {
        // Create and set up the objects
        let button = Button()
        //button.type = .toggle
        button.label = "Test Button"
        button.x = 10.5
        button.y = 20.5
        
        let field = Field()
        field.placeholder = "Enter name"
        field.x = 1.5
        field.y = 3.5
        
        let container = Container()
        container.title = "Test Container"
        container.components = [button, field]

        // JSON encode
        let json = try Archiver.jsonEncode(container)
        
        // JSON decode: build schema
        let schema: [Archivable.Type] = [Container.self, Component.self, Button.self, Field.self]
        let decoded = try Archiver.jsonDecode(objType: Container.self, schema: schema, json: json)
        
        // Check root object
        XCTAssertEqual(decoded.title, "Test Container")
        XCTAssertEqual(decoded.components.count, 2)
        
        // Check types and values of decoded components
        guard let decodedButton = decoded.components.first as? Button else {
            XCTFail("First component should be Button")
            return
        }
        //XCTAssertEqual(decodedButton.type, .toggle)
        XCTAssertEqual(decodedButton.label, "Test Button")
        XCTAssertEqual(decodedButton.x, 10.5)
        XCTAssertEqual(decodedButton.y, 20.5)
        
        guard let decodedField = decoded.components.last as? Field else {
            XCTFail("Second component should be Field")
            return
        }
        XCTAssertEqual(decodedField.placeholder, "Enter name")
        XCTAssertEqual(decodedField.x, 1.5)
        XCTAssertEqual(decodedField.y, 3.5)
    }
}

// MARK: - Test Models

@Archivable
class Container {
    var title: String? = nil
    var components: [Component] = []
    
    required init() {
    }
}

@Archivable
class Component {
    var x: Double = 0
    var y: Double = 0
    
    required init() {}
}

enum ButtonType: String {
    case push
    case toggle
}

@Archivable
class Button: Component {
    //var type: ButtonType = .push
    var label: String = ""
    
    required init() {}
}

@Archivable
class Field: Component {
    var placeholder: String = ""
    
    required init() {}
}

@Archivable
struct Preferences {
    var reopenWindows: Bool = true
}

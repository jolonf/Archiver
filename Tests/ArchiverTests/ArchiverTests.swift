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

enum ButtonType {
    case push
    case toggle
}

@Archivable
class Button: Component {
    var type: ButtonType = .push
    var label: String = ""
    
    required init() {}
}

class Field: Component {
    var placeholder: String = ""
    
    required init() {}
}


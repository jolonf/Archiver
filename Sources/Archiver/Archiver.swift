import Foundation

// MARK: - Macro

/// A macro that automatically synthesizes the `Archivable` protocol conformance,
/// including the required `decode(from:schema:)` member.
@attached(member, names: named(decode(from:schema:)))
@attached(extension, conformances: Archivable)
public macro Archivable() = #externalMacro(module: "ArchiverMacros", type: "ArchivableMacro")

/// A macro that produces both a value and a string containing the
/// source code that generated the value. For example,
///
///     #stringify(x + y)
///
/// produces a tuple `(x + y, "x + y")`.
@freestanding(expression)
public macro stringify<T>(_ value: T) -> (T, String) = #externalMacro(module: "ArchiverMacros", type: "StringifyMacro")

// MARK: - Types

public enum ArchiverError: Error {
    case unknownType(message: String = "")
}

public typealias ArchivableClass = (Archivable & AnyObject).Type

public typealias ArchivableSchema = [String: ArchivableClass]

public protocol Archivable: AnyObject {
    init()
    func decode(from json: [String: Any], schema: ArchivableSchema) throws
}

// MARK: - Archiver

public class Archiver {
    public static let typeDiscriminator = "_$type"
    
    // MARK: - JSON
    
    public static func jsonDecode<T: Archivable>(objType: T.Type, schema types: [ArchivableClass], json: Data) throws -> T {
        let deser = try JSONSerialization.jsonObject(with: json)
        let schema = createSchema(from: types)
        switch deser {
        case let dict as [String: Any]:
            return try decode(type: objType, from: dict, schema: schema)
        default:
            throw ArchiverError.unknownType(message: "Expected an object")
        }
    }
    
    public static func jsonEncode(_ obj: AnyObject, options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys]) throws -> Data {
        let archive = try encode(obj: obj)
        return try JSONSerialization.data(withJSONObject: archive, options: options)
    }

    // MARK: - Encode

    public static func encode(obj: AnyObject) throws -> [String: Any] {
        return try encode(objMirror: Mirror(reflecting: obj))
    }

    public static func encode(objMirror: Mirror) throws -> [String: Any] {
        var archive: [String: Any] = [:]
        archive[typeDiscriminator] = String(describing: objMirror.subjectType)
        try encode(properties: objMirror, archive: &archive)
        // Do the superclass
        if let superclassMirror = objMirror.superclassMirror {
            try encode(properties: superclassMirror, archive: &archive)
        }
        return archive
    }

    public static func encode(properties: Mirror, archive: inout [String: Any]) throws {
        try properties.children.forEach { (child: Mirror.Child) in
            if let label = child.label {
                let valueMirror = Mirror(reflecting: child.value)
                var value: Any
                // Optionals
                if valueMirror.displayStyle == .optional && !valueMirror.children.isEmpty {
                    if !valueMirror.children.isEmpty {
                        value = child.value
                    } else {
                        return // No property created for nil values
                    }
                // Enums
                } else if valueMirror.displayStyle == .enum {
                    if child.value is any RawRepresentable {
                        value = child.value
                    } else {
                        value = String(describing: child.value)
                    }
                } else {
                    value = child.value
                }
                archive[label] = try encode(value: value)
            }
        }
    }

    public static func encode(value: Any) throws -> Any {
        switch value {
        case let value as String:
            return value
        case let value as Int:
            return value
        case let value as Double:
            return value
        // TODO: - Dictionary
        case let array as [Any]:
            var archiveArray: [Any] = []
            try array.enumerated().forEach { (index, element) in
                archiveArray.append(try encode(value: element))
            }
            return archiveArray
        case let obj as AnyObject:
            return try encode(obj: obj)
        default:
            throw ArchiverError.unknownType(message: "Data type not supported \(value)")
        }
    }

    // MARK: - Decode
    
    /// Convenience form of `decode(from:schema:)` that casts to `T`
    public static func decode<T>(type: T.Type, from value: Any, schema: ArchivableSchema) throws -> T {
        return try decode(from: value, schema: schema) as! T
    }

    public static func decode(from value: Any, schema: ArchivableSchema) throws -> Any {
        switch value {
        case let value as String:
            return value
        case let value as Int:
            return value
        case let value as Double:
            return value
        case let dict as [String: Any]:
            // The dict may be an object or it may be just a dict
            if let className = dict[typeDiscriminator] as? String {
                // Object
                return try decodeObject(from: dict, schema: schema)
            } else {
                // Dict
                return value
            }
        case let array as [Any]:
            var decodedArray: [Any] = []
            try array.enumerated().forEach { (index, element) in
                decodedArray.append(try decode(type: Any.self, from: element, schema: schema))
            }
            return decodedArray
        default:
            throw ArchiverError.unknownType(message: "Data type not supported for value: \(value)")
        }
    }
    
    /// Polymorphic decode
    public static func decodeObject(from archive: [String: Any], schema: ArchivableSchema) throws -> AnyObject {
        if let typeName = archive[typeDiscriminator] as? String,
           let type = schema[typeName] {
            var obj = type.init()
            try obj.decode(from: archive, schema: schema)
            return obj
        } else {
            throw ArchiverError.unknownType(message: "Class not found in schema")
        }
    }
    
    public static func createSchema(from types: [ArchivableClass]) -> ArchivableSchema {
        var schema: ArchivableSchema = [:]
        for type in types {
            let typeName = String(describing: type)
            schema[typeName] = type
        }
        return schema
    }
}

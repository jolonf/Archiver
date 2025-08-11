import Foundation

// MARK: - Macro

/// A macro that automatically synthesizes the `Archivable` protocol conformance,
/// including the required `decode(from:schema:)` member.
@attached(member, names: named(decode(from:schema:)))
@attached(extension, conformances: Archivable)
public macro Archivable() = #externalMacro(module: "ArchiverMacros", type: "ArchivableMacro")


// MARK: - Types

public protocol Archivable {
    init()
    mutating func decode(from archive: [String: Any], schema: ArchivableSchema) throws
}

/// String to Archivable type mapping.
/// Used to map types stored in the archive to a Swift type which can be instantiated during decoding.
public struct ArchivableSchema {
    var schema: [String: Archivable.Type]
    
    public init(_ schema: [Archivable.Type]) {
        self.schema = Self.createSchema(from: schema)
    }
    
    public func type(forKey key: String) -> Archivable.Type? {
        schema[key]
    }
    
    public static func createSchema(from types: [Archivable.Type]) -> [String: Archivable.Type] {
        var schema: [String: Archivable.Type] = [:]
        for type in types {
            let typeName = String(describing: type)
            schema[typeName] = type
        }
        return schema
    }
}

public enum ArchiverError: Error {
    case unknownType(message: String = "")
}

// MARK: - Archiver

public class Archiver {
    /// The key which contains the type name (e.g. class, struct, or enum name)
    public static let typeDiscriminator = "_$type"

    // MARK: - Encode

    /// Encodes an object into a dictionary
    public static func encode(obj: Archivable) throws -> [String: Any] {
        var archive: [String: Any] = [:]
        let mirror = Mirror(reflecting: obj)
        archive[typeDiscriminator] = String(describing: mirror.subjectType)
        try encode(properties: mirror, archive: &archive)
        // Do the superclass
        if let superclassMirror = mirror.superclassMirror {
            try encode(properties: superclassMirror, archive: &archive)
        }
        return archive
    }

    /// Encodes the properties of an object into a dictionary.
    /// Called from `encode(obj:)`. This function exists separately because when we
    /// encode superclasses we encode the properties to the same dictionary as the subclass.
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
                } else {
                    value = child.value
                }
                archive[label] = try encode(value: value)
            }
        }
    }

    /// Encode a value to be stored in a dictionary entry.
    public static func encode(value: Any) throws -> Any {
        switch value {
        case let value as Bool:
            return value
        case let value as String:
            return value
        case let value as Int:
            return value
        case let value as Double:
            return value
        case let value as any RawRepresentable:
            var archive: [String: Any] = [:]
            archive[typeDiscriminator] = String(describing: type(of: value))
            archive["rawValue"] = try encode(value: value.rawValue)
            return archive
        case let dict as [String: Any]:
            var archiveDict: [String: Any] = [:]
            try dict.forEach { (key, value) in
                archiveDict[key] = try encode(value: value)
            }
            return archiveDict
        case let array as [Any]:
            var archiveArray: [Any] = []
            try array.enumerated().forEach { (index, element) in
                archiveArray.append(try encode(value: element))
            }
            return archiveArray
        case let obj as Archivable:
            return try encode(obj: obj)
        default:
            throw ArchiverError.unknownType(message: "Data type not supported encoding for value: `\(value)`")
        }
    }

    // MARK: - Decode
    
    /// Convenience form of `decode(from:schema:)` that casts to `T`
    public static func decode<T>(type: T.Type, from value: Any, schema: ArchivableSchema) throws -> T {
        return try decode(from: value, schema: schema) as! T
    }

    /// Decode any value that may occur in a dictionary entry.
    /// Recursively decode arrays, dictionaries, and objects.
    public static func decode(from value: Any, schema: ArchivableSchema) throws -> Any {
        switch value {
        case let value as Bool:
            return value
        case let value as String:
            return value
        case let value as Int:
            return value
        case let value as Double:
            return value
        case let dict as [String: Any]:
            // The dict may be an object or it may be just a dict
            if dict[typeDiscriminator] is String {
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
    
    /// Polymorphic decode.
    /// The type of the object is retrieved from the `typeDescriminator` key in the dictionary.
    /// An instance is created by looking up the type name in the schema.
    public static func decodeObject(from archive: [String: Any], schema: ArchivableSchema) throws -> Archivable {
        if let typeName = archive[typeDiscriminator] as? String {
            if let type = schema.type(forKey: typeName) {
                var obj = type.init()
                try obj.decode(from: archive, schema: schema)
                return obj
            } else {
                throw ArchiverError.unknownType(message: "Class `\(typeName)` not found in schema")
            }
        } else {
            throw ArchiverError.unknownType(message: "Dictionary does not contain key \(typeDiscriminator)")
        }
    }
}

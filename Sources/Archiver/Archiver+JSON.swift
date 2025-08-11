//
//  Archiver+JSON.swift
//  Archiver
//
//  Created by Jolon on 11/8/2025.
//

import Foundation

public extension Archiver {
    static func jsonDecode<T: Archivable>(objType: T.Type, schema: ArchivableSchema, json: Data) throws -> T {
        let deser = try JSONSerialization.jsonObject(with: json)
        //let schema = createSchema(from: types)
        switch deser {
        case let dict as [String: Any]:
            return try decode(type: objType, from: dict, schema: schema)
        default:
            throw ArchiverError.unknownType(message: "Expected an object")
        }
    }
    
    static func jsonEncode(_ obj: Archivable, options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys]) throws -> Data {
        let archive = try encode(obj: obj)
        return try JSONSerialization.data(withJSONObject: archive, options: options)
    }
}

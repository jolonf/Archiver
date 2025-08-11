# Archiver

Archiver is a Swift Package that is similar to `NSKeyedArchiver` but isn't restricted to `NSObject`s. 

The key advantage of using Archiver over `Codable` is support for inheritance which `Codable` has no support for and will likely never have support for.

Archiver takes inspiration from a few existing approaches:
- `NSKeyedArchiver` - Supports serialising subclasses and stores the type (class name) of each object.
- Swift Data - Uses a macro `@Archivable` to synthesise `decode` methods. Requires a schema of all of the types used in the archive to instantiate the correct type when decoding.
- `Codable` - Uses an `Archivable` protocol for decoding.

The motivation for Archiver is for it to be a minimial implementation to support archiving and unarchiving objects. It is not designed to conform to arbitrary formats. It is highly opinionated in that respect. Even though extra features could be added, the goal is to keep the implementation minimal as a demonstration of the minimum required to support archiving subclasses.

The Archiver produces a dictionary (similar to `NSKeyedArchiver`). This can then be converted to a file format. For example the dictionary can be passed to `JSONSerialization` to produce JSON, and it can unarchive from a JSON object produced by `JSONSerialization`. There are also convenience `jsonEncode` and `jsonDecode` functions provided.

## Usage

```swift
import Foundation
import Archiver

// Models

@Archivable
struct App {
    var container: Container = Container()
    var preferences: Preferences = Preferences()
        
    init() {}
}

@Archivable
struct Preferences {
    var reopenWindows: Bool = true
    
    init() {}
}

@Archivable
class Container {
    var title: String = ""
    var components: [Component] = []
    
    required init() {}
}

@Archivable
class Component {
    var x: Double = 0
    var y: Double = 0
    
    required init() {}
}

@Archivable
enum ButtonType: String {
    case push
    case toggle

    init() {
        self = .push // Default value is required otherwise won't compile
    }
}

@Archivable
class Button: Component {
    var type: ButtonType = .push
    var label: String = ""
    
    required init() {}
}

@Archivable
class Field: Component {
    var placeholder: String = ""
    
    required init() {}
}

// Create objects
var app = App()
var button = Button()
button.type = .toggle
button.label = "Click here"
app.container.title = "Main"
app.container.components.append(button)
var field = Field()
field.placeholder = "Type here"
app.container.components.append(field)
app.preferences.reopenWindows = false

// Archive to JSON
var json = Archiver.jsonEncode(app)
print(json)

// Unarchive from JSON
var app = Archiver.jsonDecode(objType: App.self, schema: ArchivableSchema([App.self, Preferences.self, Container.self, Component.self, ButtonType.self, Button.self, Field.self]), json: json)
```

Example JSON created from the above example:

```json
{
  "_$type" : "App",
  "container" : {
    "_$type" : "Container",
    "components" : [
      {
        "_$type" : "Button",
        "label" : "Click here",
        "type" : {
          "_$type" : "ButtonType",
          "rawValue" : "toggle"
        },
        "x" : 0,
        "y" : 0
      },
      {
        "_$type" : "Field",
        "placeholder" : "Type here",
        "x" : 0,
        "y" : 0
      }
    ],
    "title" : "Main"
  },
  "preferences" : {
    "_$type" : "Preferences",
    "reopenWindows" : false
  }
}
```

## Core Concepts

`@Archivable` can be applied to `class`, `struct`, and `enum` types.

The `Archivable` protocol requires that conformers implement `init` and `decode` functions. The `@Archivable` macro will synthesize the `decode` function, but you will need to provide the `init`.

```swift
public protocol Archivable {
    init()
    mutating func decode(from archive: [String: Any], schema: ArchivableSchema) throws
}
```

Note that the `init` contains no parameters, the decoder assumes that it can create an instance with default values. The call to `decode` happens subsequently on the already created instance, which means that the properties must be mutable.

Enums must be `RawRepresentable` and the `init` must provide a default initialization, for example:

```swift
@Archivable
enum ButtonType: String { // <-- String provides automatic RawRepresentable conformance
    case push
    case toggle
    
    public init() {
        self = .push // <-- initialization required
    }
}
```

Whenever an archive is decoded a schema must always be provided. The schema is similar in principle to that used by Swift Data. It is simply an array of all of the `Archivable` types that may be encountered whilst decoding.

## Limitations

### Synthesizing `decode()`

`@Archivable` will synthesize a `decode()` for the class. If the class has a superclass the synthesized `decode()` function will include `override` (as required by Swift syntax) and include a call to `super.decode()` in its function. However it doesn't check if the superclass does in fact conform to `Archivable`, which is possible. A more complete check of the superclass should be added to the macro which synthesizes decode function.

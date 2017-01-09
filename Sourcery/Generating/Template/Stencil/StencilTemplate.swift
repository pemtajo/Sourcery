import Foundation
import Stencil
import PathKit

final class StencilTemplate: Stencil.Template, Template {
    private(set) var sourcePath: Path = ""

    convenience init(path: Path) throws {
        self.init(templateString: try path.read(), environment: StencilTemplate.sourceryEnvironment())
        sourcePath = path
    }

    convenience init(templateString: String) {
        self.init(templateString: templateString, environment: StencilTemplate.sourceryEnvironment())
    }

    func render(types: [Type], arguments: [String: NSObject]) throws -> String {
        var typesByName = [String: Type]()
        types.forEach { typesByName[$0.name] = $0 }

        let context: [String: Any] = [
                "types": TypesReflectionBox(types: types),
                "type": typesByName,
                "argument": arguments
        ]

        return try super.render(context)
    }

    private static func sourceryEnvironment() -> Stencil.Environment {
        let ext = Stencil.Extension()
        ext.registerFilter("upperFirst", filter: Filter<String>.make({ $0.upperFirst() }))
        ext.registerBoolFilterWithArguments("contains", filter: { (s1: String, s2) in s1.contains(s2) })
        ext.registerBoolFilterWithArguments("hasPrefix", filter: { (s1: String, s2) in s1.hasPrefix(s2) })
        ext.registerBoolFilterWithArguments("hasSuffix", filter: { (s1: String, s2) in s1.hasSuffix(s2) })

        ext.registerBoolFilter("computed", filter: { (v: Variable) in v.isComputed && !v.isStatic })
        ext.registerBoolFilter("stored", filter: { (v: Variable) in !v.isComputed && !v.isStatic })
        ext.registerBoolFilter("tuple", filter: { (v: Variable) in v.isTuple })

        ext.registerBoolFilterOrWithArguments("based",
                                              filter: { (t: Type, name: String) in t.based[name] != nil },
                                              other: { (t: Typed, name: String) in t.type?.based[name] != nil })
        ext.registerBoolFilterOrWithArguments("implements",
                                              filter: { (t: Type, name: String) in t.implements[name] != nil },
                                              other: { (t: Typed, name: String) in t.type?.implements[name] != nil })
        ext.registerBoolFilterOrWithArguments("inherits",
                                              filter: { (t: Type, name: String) in t.inherits[name] != nil },
                                              other: { (t: Typed, name: String) in t.type?.inherits[name] != nil })

        ext.registerBoolFilter("enum", filter: { (t: Type) in t is Enum })
        ext.registerBoolFilter("struct", filter: { (t: Type) in t is Struct })
        ext.registerBoolFilter("protocol", filter: { (t: Type) in t is Protocol })

        ext.registerFilter("camelCased", filter: Filter<String>.make({ $0.camelCased }))
        ext.registerFilter("PascalCased", filter: Filter<String>.make({ $0.PascalCased }))
        ext.registerFilter("snake_cased", filter: Filter<String>.make({ $0.snake_cased }))
        ext.registerFilter("dottedNameToCamelCased", filter: Filter<String>.make({ $0.dottedNameToCamelCased }))
        ext.registerFilter("undotted", filter: Filter<String>.make({ $0.undotted }))

        ext.registerFilter("computed", filter: Filter<Variable>.make({ $0.isComputed && !$0.isStatic }))
        ext.registerFilter("stored", filter: Filter<Variable>.make({ !$0.isComputed && !$0.isStatic }))
        ext.registerFilter("tuple", filter: Filter<Variable>.make({ $0.isTuple }))
        ext.registerFilter("count", filter: count)

        ext.registerBoolFilter("initializer", filter: { (m: Method) in m.isInitializer })
        ext.registerBoolFilterOr("class",
                                 filter: { (t: Type) in t is Class },
                                 other: { (m: Method) in m.isClass })
        ext.registerBoolFilterOr("static",
                                 filter: { (v: Variable) in v.isStatic },
                                 other: { (m: Method) in m.isStatic })
        ext.registerBoolFilterOr("instance",
                                 filter: { (v: Variable) in !v.isStatic },
                                 other: { (m: Method) in !(m.isStatic || m.isClass) })

        ext.registerBoolFilterWithArguments("annotated", filter: { (a: Annotated, annotation) in a.isAnnotated(with: annotation) })

        return Stencil.Environment(extensions: [ext])
    }
}

extension Annotated {

    func isAnnotated(with annotation: String) -> Bool {
        if annotation.contains("=") {
            let components = annotation.components(separatedBy: "=").map({ $0.trimmingCharacters(in: .whitespaces) })
            return annotations[components[0]]?.description == components[1]
        } else {
            return annotations[annotation] != nil
        }
    }

}

extension Stencil.Extension {

    func registerFilterWithArguments<A>(_ name: String, filter: @escaping (Any?, A) throws -> Any?) {
        registerFilter(name) { (any, args) throws -> Any? in
            guard args.count == 1, let arg = args.first as? A else {
                throw TemplateSyntaxError("'\(name)' filter takes a single \(A.self) argument")
            }
            return try filter(any, arg)
        }
    }

    func registerBoolFilterWithArguments<U, A>(_ name: String, filter: @escaping (U, A) -> Bool) {
        registerFilterWithArguments(name, filter: Filter.make(filter))
        registerFilterWithArguments("!\(name)", filter: Filter.make({ !filter($0, $1) }))
    }

    public func registerBoolFilter<U>(_ name: String, filter: @escaping (U) -> Bool) {
        registerFilter(name, filter: Filter.make(filter))
        registerFilter("!\(name)", filter: Filter.make({ !filter($0) }))
    }

    func registerBoolFilterOrWithArguments<U, V, A>(_ name: String, filter: @escaping (U, A) -> Bool, other: @escaping (V, A) -> Bool) {
        registerFilterWithArguments(name, filter: FilterOr.make(filter, other: other))
        registerFilterWithArguments("!\(name)", filter: FilterOr.make({ !filter($0, $1) }, other: { !other($0, $1) }))
    }

    public func registerBoolFilterOr<U, V>(_ name: String, filter: @escaping (U) -> Bool, other: @escaping (V) -> Bool) {
        registerFilter(name, filter: FilterOr.make(filter, other: other))
        registerFilter("!\(name)", filter: FilterOr.make({ !filter($0) }, other: { !other($0) }))
    }

}

private func count(_ value: Any?) -> Any? {
    guard let array = value as? NSArray else {
        return value
    }
    return array.count
}

extension String {
    fileprivate func upperFirst() -> String {
        let first = String(characters.prefix(1)).capitalized
        let other = String(characters.dropFirst())
        return first + other
    }

    private var first: String {
        return self.substring(to: self.index(self.startIndex, offsetBy: 1))
    }

    var camelCased: String {
        if self.characters.contains(" ") {
            let rest = String(self.capitalized.replacingOccurrences(of: " ", with: "").characters.dropFirst())
            return "\(self.first.lowercased())\(rest)"
        } else {
            let rest = String(self.characters.dropFirst())
            return "\(self.first.lowercased())\(rest)"
        }
    }

    var PascalCased: String {
        if self.characters.contains(" ") {
            return self.capitalized.replacingOccurrences(of: " ", with: "")
        } else {
            let rest = String(self.characters.dropFirst())
            return "\(self.first.uppercased())\(rest)"
        }
    }

    var snake_cased: String {
        if let regex = try? NSRegularExpression(pattern: "([A-Z])", options: []) {
            let modString = regex.stringByReplacingMatches(in: self,
                                                           options: .withTransparentBounds,
                                                           range: NSMakeRange(0, self.characters.count),
                                                           withTemplate: "_$1")
            return modString.lowercased()
        }
        return self.replacingOccurrences(of: " ", with: "_").lowercased()
    }

    var dottedNameToCamelCased: String {
        return String(self.characters.split(separator: ".").map { String($0).PascalCased }.joined()).camelCased
    }

    var undotted: String {
        return self.replacingOccurrences(of: ".", with: "")
    }
}

private struct Filter<T> {
    static func make(_ filter: @escaping (T) -> Bool) -> (Any?) throws -> Any? {
        return { (any) throws -> Any? in
            switch any {
            case let type as T:
                return filter(type)

            case let array as NSArray:
                return array.flatMap { $0 as? T }.filter(filter)

            default:
                return any
            }
        }
    }

    static func make<U>(_ filter: @escaping (T) -> U?) -> (Any?) throws -> Any? {
        return { (any) throws -> Any? in
            switch any {
            case let type as T:
                return filter(type)

            case let array as NSArray:
                return array.flatMap { $0 as? T }.flatMap(filter)

            default:
                return any
            }
        }
    }

    static func make<A>(_ filter: @escaping (T, A) -> Bool) -> (Any?, A) throws -> Any? {
        return { (any, arg) throws -> Any? in
            switch any {
            case let type as T:
                return filter(type, arg)

            case let array as NSArray:
                return array.flatMap { $0 as? T }.filter({ filter($0, arg) })

            default:
                return any
            }
        }
    }
}

private struct FilterOr<T, Y> {
    static func make(_ filter: @escaping (T) -> Bool, other: @escaping (Y) -> Bool) -> (Any?) throws -> Any? {
        return { (any) throws -> Any? in
            switch any {
            case let type as T:
                return filter(type)

            case let type as Y:
                return other(type)

            case let array as NSArray:
                if let _ = array.firstObject as? T {
                    return array.flatMap { $0 as? T }.filter(filter)
                } else {
                    return array.flatMap { $0 as? Y }.filter(other)
                }

            default:
                return any
            }
        }
    }

    static func make<A>(_ filter: @escaping (T, A) -> Bool, other: @escaping (Y, A) -> Bool) -> (Any?, A) throws -> Any? {
        return { (any, arg) throws -> Any? in
            switch any {
            case let type as T:
                return filter(type, arg)

            case let type as Y:
                return other(type, arg)

            case let array as NSArray:
                if let _ = array.firstObject as? T {
                    return array.flatMap { $0 as? T }.filter({ filter($0, arg) })
                } else {
                    return array.flatMap { $0 as? Y }.filter({ other($0, arg) })
                }

            default:
                return any
            }
        }
    }
}

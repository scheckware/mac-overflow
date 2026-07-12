import ApplicationServices
import Foundation

/// Thin, failure-tolerant helpers over the C Accessibility (AX) API.
///
/// Every accessor returns `nil`/`false` on any AX error rather than trapping,
/// which keeps call sites readable and robust against apps that don't expose a
/// given attribute.
enum AX {
    /// Reads an attribute and casts it to the requested type, returning `nil`
    /// on any failure (missing attribute, AX error, or type mismatch).
    static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value as? T
    }

    /// Reads a boxed `AXValue` attribute (e.g. a `CGPoint` or `CGSize`) of the
    /// given `AXValueType`.
    private static func axValue(_ element: AXUIElement, _ name: String, _ type: AXValueType) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        let boxed = value as! AXValue // safe: type id checked above
        return AXValueGetType(boxed) == type ? boxed : nil
    }

    /// Reads a `CGPoint`-valued attribute.
    static func point(_ element: AXUIElement, _ name: String) -> CGPoint? {
        guard let boxed = axValue(element, name, .cgPoint) else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(boxed, .cgPoint, &point) ? point : nil
    }

    /// Reads a `CGSize`-valued attribute.
    static func size(_ element: AXUIElement, _ name: String) -> CGSize? {
        guard let boxed = axValue(element, name, .cgSize) else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(boxed, .cgSize, &size) ? size : nil
    }

    /// Reads a boolean attribute (AX booleans bridge from `CFBoolean`).
    static func bool(_ element: AXUIElement, _ name: String) -> Bool? {
        attribute(element, name)
    }

    /// The element's children, or an empty array if it has none.
    static func children(_ element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute as String) ?? []
    }

    /// The action names the element supports (e.g. `AXPress`, `AXShowMenu`), or
    /// an empty array on any AX error / no actions.
    static func actionNames(_ element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success,
              let names = names as? [String] else {
            return []
        }
        return names
    }

    /// Performs an AX action (e.g. press), reporting whether it succeeded.
    @discardableResult
    static func perform(_ element: AXUIElement, _ action: String) -> Bool {
        AXUIElementPerformAction(element, action as CFString) == .success
    }
}

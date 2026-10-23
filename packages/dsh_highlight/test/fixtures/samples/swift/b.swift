import SwiftUI
@testable import MyModule

@main
struct App: App {
    @State private var count = 0
    @Environment(\.colorScheme) var scheme
    var body: some Scene {
        WindowGroup { ContentView().environmentObject(Store()) }
    }
}

@propertyWrapper struct Clamped<V: Comparable> {
    var wrappedValue: V { didSet { wrappedValue = min(max(wrappedValue, lo), hi) } }
    let lo: V, hi: V
}

protocol P: AnyObject, Sendable { associatedtype T; static func make() -> Self }
extension Array where Element: Equatable { func uniq() -> [Element] { reduce(into: []) { if !$0.contains($1) { $0.append($1) } } } }
actor Counter { private var n = 0; func inc() -> Int { n += 1; return n } }
indirect enum Tree<T> { case leaf, node(Tree, T, Tree) }

func f<T>(_ x: T, label y: Int = 0, _ rest: String...) async throws -> T? where T: Codable {
    let s = "tab\t\"q\" \u{1F600} \(x) \\n"
    let r = #"raw \(not)"#, m = """
        multi \(y)
        """
    let n = 1_000 + 0xFF + 0b11 + 0o7, d = 1.5e-3
    guard let v = Optional(x), case .some = Optional(v) else { return nil }
    switch y { case 1...3, 5: break; case let z where z > 9: break; default: fallthrough }
    let kp = \String.count; let c = { [weak self] (a: Int) -> Int in a }
    defer { print("done") }
    #if os(macOS)
    print("mac")
    #endif
    return try await Task { x }.value
}

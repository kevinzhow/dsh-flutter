import Foundation

protocol Drawable {
    var size: Int { get }
    func draw(in rect: CGRect) -> Bool
}

/// Documentation comment
struct Point: Hashable, Codable {
    var x: Double
    let y: Double = 0
    static let zero = Point(x: 0)
}

enum Result<T> {
    case success(T)
    case failure(Error)
}

final class Canvas<Item: Drawable>: NSObject {
    private var items: [Item] = []
    @Published var title: String? = nil

    init(title: String) { self.title = title }

    func add(_ item: Item) throws {
        guard item.size > 0 else { throw NSError(domain: "x", code: 1) }
        items.append(item)
    }

    @discardableResult
    func render() async -> String {
        let text = "Items: \(items.count) \"quoted\" \n"
        let multi = """
            multi \(text)
            """
        let re = #"raw \d+"#
        if let first = items.first, first.size > 1 { print(first) }
        return text + multi + re
    }
}

let closure = { (a: Int, b: Int) -> Int in a &+ b }
for i in 0..<10 where i % 2 == 0 { print(i) }
// trailing

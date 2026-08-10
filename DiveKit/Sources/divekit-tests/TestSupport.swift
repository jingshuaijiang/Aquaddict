import Foundation

// Minimal zero-dependency test harness (Command Line Tools has no XCTest/swift-testing).
// Migrate to swift-testing once Xcode is installed.

nonisolated(unsafe) var failures = 0
nonisolated(unsafe) var checks = 0

func expect(_ condition: Bool, _ message: @autoclosure () -> String,
            file: String = #file, line: Int = #line) {
    checks += 1
    if !condition {
        failures += 1
        let name = (file as NSString).lastPathComponent
        print("  ✗ \(name):\(line)  \(message())")
    }
}

func expectEqual<T: Equatable>(_ a: T, _ b: T, _ label: String,
                               file: String = #file, line: Int = #line) {
    expect(a == b, "\(label): \(a) != \(b)", file: file, line: line)
}

func expectClose(_ a: Double, _ b: Double, tol: Double, _ label: String,
                 file: String = #file, line: Int = #line) {
    expect(abs(a - b) < tol, "\(label): \(a) !≈ \(b) (tol \(tol))", file: file, line: line)
}

func runTest(_ name: String, _ body: () throws -> Void) {
    let before = failures
    do {
        try body()
        print(failures == before ? "PASS \(name)" : "FAIL \(name)")
    } catch {
        failures += 1
        print("FAIL \(name) — threw \(error)")
    }
}

func loadFixture(_ name: String) throws -> Data {
    guard let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil) else {
        throw NSError(domain: "fixtures", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "missing fixture \(name)"])
    }
    return try Data(contentsOf: url)
}

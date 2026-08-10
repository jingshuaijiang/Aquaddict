import Foundation
import DiveKit

runTest("packageBuilds") {
    expectEqual(DiveKit.version, "0.1.0", "version")
}

print("\n\(checks) checks, \(failures) failures")
exit(failures == 0 ? 0 : 1)

import Foundation
import DiveKit

pnfParserTests()
metricsAndPhysicsTests()

print("\n\(checks) checks, \(failures) failures")
exit(failures == 0 ? 0 : 1)

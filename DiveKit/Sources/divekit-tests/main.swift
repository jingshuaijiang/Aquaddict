import Foundation
import DiveKit

pnfParserTests()
metricsAndPhysicsTests()
shearwaterProtocolTests()
gnssTests()
gasPlannerTests()
trimModelTests()

print("\n\(checks) checks, \(failures) failures")
exit(failures == 0 ? 0 : 1)

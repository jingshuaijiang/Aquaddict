import Foundation
import DiveKit

pnfParserTests()
metricsAndPhysicsTests()
shearwaterProtocolTests()
gnssTests()
gasPlannerTests()
trimModelTests()
weightCalcTests()
decoTests()
calorieTests()

print("\n\(checks) checks, \(failures) failures")
exit(failures == 0 ? 0 : 1)

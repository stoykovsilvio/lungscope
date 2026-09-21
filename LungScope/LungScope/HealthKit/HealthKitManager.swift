import Foundation
import HealthKit

final class HealthKitManager {

    private let store = HKHealthStore()

    static var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() async {
        guard Self.isAvailable else { return }
        let types: Set<HKSampleType> = [respiratoryRateType, mindfulSessionType]
        try? await store.requestAuthorization(toShare: types, read: [])
    }

    func save(_ result: DiagnosticResult) async {
        guard Self.isAvailable else { return }

        let start = result.timestamp
        let end   = start.addingTimeInterval(30)

        // ACI [0,1] → respiratory rate [12, 24] breaths/min.
        // Higher constriction correlates with faster compensatory breathing.
        let bpm = 12.0 + Double(result.airwayConstrictionIndex) * 12.0
        let rateSample = HKQuantitySample(
            type: respiratoryRateType,
            quantity: HKQuantity(unit: .count().unitDivided(by: .minute()),
                                 doubleValue: bpm),
            start: start,
            end: end,
            metadata: [
                "ACI":  Double(result.airwayConstrictionIndex),
                "VHSS": Double(result.vocalHarmonyStabilityScore)
            ]
        )

        let sessionSample = HKCategorySample(
            type: mindfulSessionType,
            value: HKCategoryValue.notApplicable.rawValue,
            start: start,
            end: end,
            metadata: [HKMetadataKeyExternalUUID: result.id.uuidString]
        )

        try? await store.save([rateSample, sessionSample])
    }

    // MARK: - Private

    private var respiratoryRateType: HKQuantityType {
        HKQuantityType.quantityType(forIdentifier: .respiratoryRate)!
    }

    private var mindfulSessionType: HKCategoryType {
        HKCategoryType.categoryType(forIdentifier: .mindfulSession)!
    }
}

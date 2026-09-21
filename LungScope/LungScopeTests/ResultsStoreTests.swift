import Testing
import Foundation
@testable import LungScope

struct ResultsStoreTests {

    private func makeStore() -> ResultsStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_assessments_\(UUID().uuidString).json")
        return ResultsStore(storeURL: url)
    }

    @Test func emptyStoreReturnsEmptyArray() {
        let store = makeStore()
        #expect(store.results.isEmpty)
    }

    @Test func savedResultAppearsInResults() throws {
        let store = makeStore()
        let result = DiagnosticResult(airwayConstrictionIndex: 0.3, vocalHarmonyStabilityScore: 0.8)
        try store.save(result)
        #expect(store.results.count == 1)
        #expect(store.results[0] == result)
    }

    @Test func savedResultPersistsAcrossReload() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_persist_\(UUID().uuidString).json")
        let result = DiagnosticResult(airwayConstrictionIndex: 0.4, vocalHarmonyStabilityScore: 0.6)

        let store1 = ResultsStore(storeURL: url)
        try store1.save(result)

        let store2 = ResultsStore(storeURL: url)
        #expect(store2.results.count == 1)
        #expect(store2.results[0] == result)
    }

    @Test func deleteRemovesCorrectEntry() throws {
        let store = makeStore()
        let r1 = DiagnosticResult(airwayConstrictionIndex: 0.2, vocalHarmonyStabilityScore: 0.9)
        let r2 = DiagnosticResult(airwayConstrictionIndex: 0.5, vocalHarmonyStabilityScore: 0.5)
        try store.save(r1)
        try store.save(r2)
        try store.delete(id: r1.id)
        #expect(store.results.count == 1)
        #expect(store.results[0] == r2)
    }

    @Test func deletingNonExistentIdIsNoop() throws {
        let store = makeStore()
        let r = DiagnosticResult(airwayConstrictionIndex: 0.3, vocalHarmonyStabilityScore: 0.7)
        try store.save(r)
        try store.delete(id: UUID())
        #expect(store.results.count == 1)
    }
}

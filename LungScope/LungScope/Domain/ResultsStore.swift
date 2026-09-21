import Foundation
import Combine

final class ResultsStore: ObservableObject {

    @Published private(set) var results: [DiagnosticResult] = []

    private let storeURL: URL

    init(storeURL: URL = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("assessments.json")) {
        self.storeURL = storeURL
        results = (try? loadAll()) ?? []
    }

    func save(_ result: DiagnosticResult) throws {
        var all = results
        all.append(result)
        try persist(all)
        results = all
    }

    var trend: TrendAlert {
        TrendAnalyser.analyse(results)
    }

    func delete(id: UUID) throws {
        let filtered = results.filter { $0.id != id }
        try persist(filtered)
        results = filtered
    }

    // MARK: - Private

    private func loadAll() throws -> [DiagnosticResult] {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return [] }
        let data = try Data(contentsOf: storeURL)
        return try JSONDecoder().decode([DiagnosticResult].self, from: data)
    }

    private func persist(_ all: [DiagnosticResult]) throws {
        let data = try JSONEncoder().encode(all)
        let tmp = storeURL.appendingPathExtension("tmp")
        try data.write(to: tmp, options: .atomic)
        _ = try FileManager.default.replaceItemAt(storeURL, withItemAt: tmp)
    }
}

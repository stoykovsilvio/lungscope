import SwiftUI

struct ReportView: View {
    let results: [DiagnosticResult]
    let generatedDate: Date
    private let stripe = Color(red: 0.95, green: 0.95, blue: 0.97)

    private var sorted: [DiagnosticResult] {
        results.sorted { $0.timestamp > $1.timestamp }
    }

    private var avgACI: Double {
        guard !sorted.isEmpty else { return 0 }
        return sorted.map { Double($0.airwayConstrictionIndex) }.reduce(0, +) / Double(sorted.count)
    }

    private var avgVHSS: Double {
        guard !sorted.isEmpty else { return 0 }
        return sorted.map { Double($0.vocalHarmonyStabilityScore) }.reduce(0, +) / Double(sorted.count)
    }

    private var period: String {
        guard let first = sorted.last?.timestamp, let last = sorted.first?.timestamp else { return "—" }
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .none
        return "\(fmt.string(from: first)) – \(fmt.string(from: last))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            summaryStrip
            tableSection
            footer
        }
        .frame(width: 612)
        .background(Color.white)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LungScope")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color.teal)
            Text("Respiratory Assessment Report")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
            HStack(spacing: 24) {
                labelValue("Period", period)
                labelValue("Generated", formattedDate(generatedDate))
                labelValue("Assessments", "\(sorted.count)")
            }
            .padding(.top, 4)
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(stripe)
    }

    // MARK: - Summary

    private var summaryStrip: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                statTile(title: "Avg ACI", value: "\(Int(avgACI * 100))%", sub: aciBand(avgACI), color: .orange)
                Divider().frame(height: 60)
                statTile(title: "Avg VHSS", value: "\(Int(avgVHSS * 100))%", sub: vhssBand(avgVHSS), color: .teal)
                Divider().frame(height: 60)
                statTile(title: "Trend", value: trendLabel, sub: "", color: trendColor)
            }
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(Color.white)
            Divider()
        }
    }

    // MARK: - Table

    private var tableSection: some View {
        VStack(spacing: 0) {
            tableHeader
            ForEach(Array(sorted.enumerated()), id: \.element.id) { index, result in
                tableRow(result, shaded: index.isMultiple(of: 2))
            }
        }
    }

    private var tableHeader: some View {
        HStack {
            Text("Date").frame(maxWidth: .infinity, alignment: .leading)
            Text("Time").frame(width: 70, alignment: .leading)
            Text("ACI").frame(width: 55, alignment: .trailing)
            Text("VHSS").frame(width: 55, alignment: .trailing)
            Text("Status").frame(width: 80, alignment: .trailing)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 28)
        .padding(.vertical, 8)
        .background(stripe)
    }

    private func tableRow(_ result: DiagnosticResult, shaded: Bool) -> some View {
        let aci = result.airwayConstrictionIndex
        let status = aci < 0.31 ? "Good" : aci < 0.61 ? "Monitor" : "Elevated"
        let statusColor: Color = aci < 0.31 ? .teal : aci < 0.61 ? .orange : .red

        return HStack {
            Text(result.timestamp, style: .date)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(result.timestamp, style: .time)
                .frame(width: 70, alignment: .leading)
            Text("\(Int(result.airwayConstrictionIndex * 100))%")
                .frame(width: 55, alignment: .trailing)
                .foregroundStyle(Color.orange)
            Text("\(Int(result.vocalHarmonyStabilityScore * 100))%")
                .frame(width: 55, alignment: .trailing)
                .foregroundStyle(Color.teal)
            Text(status)
                .frame(width: 80, alignment: .trailing)
                .foregroundStyle(statusColor)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 28)
        .padding(.vertical, 9)
        .background(shaded ? stripe : Color.white)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            Text("For personal wellness tracking only. LungScope is not a medical device and cannot diagnose any condition. This report should not be used as a substitute for professional medical advice.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(28)
        }
    }

    // MARK: - Helpers

    private func labelValue(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 12, weight: .medium))
        }
    }

    private func statTile(title: String, value: String, sub: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 22, weight: .semibold)).foregroundStyle(color)
            if !sub.isEmpty {
                Text(sub).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func formattedDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }

    private func aciBand(_ v: Double) -> String {
        if v < 0.31 { return "Normal" }
        if v < 0.61 { return "Mildly Elevated" }
        return "Elevated"
    }

    private func vhssBand(_ v: Double) -> String {
        if v > 0.65 { return "Stable" }
        if v > 0.40 { return "Mildly Irregular" }
        return "Irregular"
    }

    private var trendLabel: String {
        switch TrendAnalyser.analyse(results) {
        case .improving:  return "Improving ↓"
        case .worsening:  return "Worsening ↑"
        case .stable:     return "Stable →"
        case .notEnoughData: return "—"
        }
    }

    private var trendColor: Color {
        switch TrendAnalyser.analyse(results) {
        case .improving:  return .teal
        case .worsening:  return .red
        default:          return .secondary
        }
    }
}

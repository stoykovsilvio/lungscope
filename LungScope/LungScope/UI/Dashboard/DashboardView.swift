import SwiftUI
import Charts
import UIKit

struct DashboardView: View {
    @EnvironmentObject private var store: ResultsStore
    @State private var selectedDate: Date? = nil
    @State private var exportItem: ExportItem? = nil

    private var sorted: [DiagnosticResult] {
        store.results.sorted { $0.timestamp > $1.timestamp }
    }

    private var chartWindow: [DiagnosticResult] {
        Array(sorted.prefix(30)).reversed()
    }

    private var chartPoints: [TrendPoint] {
        chartWindow.flatMap { r in [
            TrendPoint(timestamp: r.timestamp, value: Double(r.airwayConstrictionIndex),    metric: "ACI"),
            TrendPoint(timestamp: r.timestamp, value: Double(r.vocalHarmonyStabilityScore), metric: "VHSS")
        ]}
    }

    private var selectedResult: DiagnosticResult? {
        guard let date = selectedDate else { return nil }
        return chartWindow.min(by: { abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date)) })
    }

    private func nearest(to date: Date) -> Date? {
        chartWindow.map(\.timestamp).min(by: { abs($0.timeIntervalSince(date)) < abs($1.timeIntervalSince(date)) })
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.results.isEmpty {
                    emptyState
                } else {
                    resultsList
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if let url = PDFExporter.export(results: store.results) {
                            exportItem = ExportItem(url: url)
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(store.results.isEmpty)
                }
            }
            .sheet(item: $exportItem) { item in
                ActivityView(items: [item.url])
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 56, weight: .thin))
                .foregroundStyle(.secondary)
            Text("No assessments yet")
                .font(.title3.weight(.semibold))
            Text("Complete your first assessment to start tracking your respiratory health over time.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    // MARK: - Results List

    private var resultsList: some View {
        ScrollViewReader { proxy in
            List {
                if store.trend != .notEnoughData && store.trend != .stable {
                    Section {
                        TrendBannerView(trend: store.trend)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                    }
                }

                Section("Trends (last \(min(sorted.count, 30)))") {
                    trendChart
                        .frame(height: 180)
                        .padding(.vertical, 8)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .id("trendChart")

                    if let result = selectedResult {
                        selectionCard(result)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                    } else {
                        Text("Drag the chart to inspect a point")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                    }
                }

                Section("All Assessments") {
                    ForEach(sorted) { result in
                        ResultRowView(result: result) {
                            selectedDate = result.timestamp
                            withAnimation { proxy.scrollTo("trendChart", anchor: .top) }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                try? store.delete(id: result.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    // MARK: - Trend Chart

    private var trendChart: some View {
        Chart {
            RuleMark(y: .value("ACI limit", 0.31))
                .foregroundStyle(Color.orange.opacity(0.45))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                .annotation(position: .trailing, alignment: .center) {
                    Text("ACI").font(.caption2).foregroundStyle(.orange.opacity(0.7))
                }

            RuleMark(y: .value("VHSS target", 0.65))
                .foregroundStyle(Color.teal.opacity(0.45))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                .annotation(position: .trailing, alignment: .center) {
                    Text("VHSS").font(.caption2).foregroundStyle(.teal.opacity(0.7))
                }

            ForEach(chartPoints) { point in
                LineMark(
                    x: .value("Date", point.timestamp),
                    y: .value("Score", point.value)
                )
                .foregroundStyle(by: .value("Metric", point.metric))
                .symbol(by: .value("Metric", point.metric))
                .interpolationMethod(.catmullRom)
            }

            if let result = selectedResult {
                RuleMark(x: .value("Selected", result.timestamp))
                    .foregroundStyle(Color.primary.opacity(0.2))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
        }
        .chartYScale(domain: 0...1)
        .chartYAxis {
            AxisMarks(values: [0.0, 0.25, 0.5, 0.75, 1.0]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v * 100))%").font(.caption2)
                    }
                }
            }
        }
        .chartForegroundStyleScale(["ACI": Color.orange, "VHSS": Color.teal])
        .chartSymbolScale(["ACI": Circle(), "VHSS": Circle()])
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let origin = geo[proxy.plotAreaFrame].origin
                                let x = value.location.x - origin.x
                                if let date: Date = proxy.value(atX: x) {
                                    selectedDate = nearest(to: date)
                                }
                            }
                            .onEnded { _ in selectedDate = nil }
                    )
            }
        }
    }

    private func selectionCard(_ result: DiagnosticResult) -> some View {
        HStack(spacing: 10) {
            Text(result.timestamp, style: .date)
                .font(.caption2.weight(.semibold))
            HStack(spacing: 3) {
                Circle().fill(.orange).frame(width: 5, height: 5)
                Text("\(Int(result.airwayConstrictionIndex * 100))%")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 3) {
                Circle().fill(.teal).frame(width: 5, height: 5)
                Text("\(Int(result.vocalHarmonyStabilityScore * 100))%")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .fixedSize()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
    }
}

// MARK: - Supporting Types

private struct ExportItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {}
}

private struct TrendPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let value: Double
    let metric: String
}

private struct ResultRowView: View {
    let result: DiagnosticResult
    let onTap: () -> Void

    private var status: (label: String, color: Color) {
        let aci = result.airwayConstrictionIndex
        if aci < 0.31 { return ("Good", .teal) }
        if aci < 0.61 { return ("Monitor", .orange) }
        return ("Elevated", .red)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(result.timestamp, style: .date)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(status.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(status.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(status.color.opacity(0.12), in: Capsule())
            }
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Circle().fill(.orange).frame(width: 8, height: 8)
                    Text("ACI \(Int(result.airwayConstrictionIndex * 100))%")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    Circle().fill(.teal).frame(width: 8, height: 8)
                    Text("VHSS \(Int(result.vocalHarmonyStabilityScore * 100))%")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(result.timestamp, style: .time)
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

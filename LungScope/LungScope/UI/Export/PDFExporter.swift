import SwiftUI

@MainActor
struct PDFExporter {

    static func export(results: [DiagnosticResult]) -> URL? {
        let view = ReportView(results: results, generatedDate: Date())
            .environment(\.colorScheme, .light)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0

        guard let uiImage = renderer.uiImage else { return nil }

        let bounds = CGRect(origin: .zero, size: uiImage.size)
        let pdfRenderer = UIGraphicsPDFRenderer(bounds: bounds)
        let data = pdfRenderer.pdfData { ctx in
            ctx.beginPage()
            uiImage.draw(in: bounds)
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LungScope_Report.pdf")
        try? data.write(to: url)
        return url
    }
}


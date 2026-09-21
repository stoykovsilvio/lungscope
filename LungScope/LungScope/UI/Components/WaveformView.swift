import SwiftUI

/// Scrolling bar-chart waveform that renders RMS amplitude values posted
/// by the AudioEngine tap at ≤30fps. Reads from viewModel.waveformSamples —
/// never from the ring buffer directly.
struct WaveformView: View {
    @EnvironmentObject private var viewModel: AssessmentViewModel

    private let maxBars = 150
    private let barSpacing: CGFloat = 2

    var body: some View {
        GeometryReader { geo in
            let samples = Array(viewModel.waveformSamples.suffix(maxBars))
            let barWidth = max(2, (geo.size.width - barSpacing * CGFloat(maxBars)) / CGFloat(maxBars))

            Canvas { context, size in
                let count = samples.count
                guard count > 0 else { return }

                for i in 0..<count {
                    let amplitude = CGFloat(samples[i])
                    let barHeight = max(2, amplitude * size.height * 0.9)
                    let x = CGFloat(i) * (barWidth + barSpacing)
                    let y = (size.height - barHeight) / 2

                    let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
                    let color = barColor(for: samples[i])
                    context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2),
                                 with: .color(color))
                }
            }
        }
    }

    // Transitions from teal (quiet) to orange to red as amplitude rises.
    private func barColor(for amplitude: Float) -> Color {
        switch amplitude {
        case ..<0.2:  return .teal
        case ..<0.5:  return .orange
        default:      return .red
        }
    }
}

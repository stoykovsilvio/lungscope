enum AppPhase: Equatable {
    case idle
    case coughRecording
    case vowelReady
    case vowelRecording
    case analyzing
    case results(DiagnosticResult)
}

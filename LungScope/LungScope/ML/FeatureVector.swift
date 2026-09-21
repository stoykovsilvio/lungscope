import CoreML

/// Typed container mapping all DSP outputs to the exact 29-feature input
/// shape the CoreML classifier expects.
///
/// The flat index order is the schema contract with Scripts/train_model.py.
/// Changing property order here without updating the Python pipeline will
/// produce a model that accepts input silently but makes wrong predictions.
struct FeatureVector: Equatable {

    // MARK: - Cough-side features (from MFCCExtractor + SpectralFlatness)

    let mfccMean:   [Float]   // length 13 — indices 0–12
    let mfccStdDev: [Float]   // length 13 — indices 13–25
    let spectralFlatness: Float  // index 26

    // MARK: - Vowel-side features (from JitterCalculator + ShimmerCalculator)

    let jitter:  Float  // index 27
    let shimmer: Float  // index 28

    // MARK: - Initialisation

    init(
        mfccMean: [Float],
        mfccStdDev: [Float],
        spectralFlatness: Float,
        jitter: Float,
        shimmer: Float
    ) {
        precondition(mfccMean.count == 13,   "FeatureVector: mfccMean must have 13 elements.")
        precondition(mfccStdDev.count == 13, "FeatureVector: mfccStdDev must have 13 elements.")
        self.mfccMean        = mfccMean
        self.mfccStdDev      = mfccStdDev
        self.spectralFlatness = spectralFlatness
        self.jitter          = jitter
        self.shimmer         = shimmer
    }

    // MARK: - CoreML Conversion

    /// Flattens the struct into an MLMultiArray in the documented index order.
    /// The layout must exactly match the column order in Scripts/train_model.py.
    ///
    /// Index layout:
    ///   0–12  mfccMean[0...12]
    ///  13–25  mfccStdDev[0...12]
    ///     26  spectralFlatness
    ///     27  jitter
    ///     28  shimmer
    func toMLMultiArray() throws -> MLMultiArray {
        let array = try MLMultiArray(shape: [29], dataType: .float32)
        var idx = 0
        for v in mfccMean        { array[idx] = NSNumber(value: v); idx += 1 }
        for v in mfccStdDev      { array[idx] = NSNumber(value: v); idx += 1 }
        array[idx] = NSNumber(value: spectralFlatness); idx += 1
        array[idx] = NSNumber(value: jitter);           idx += 1
        array[idx] = NSNumber(value: shimmer)
        return array
    }
}

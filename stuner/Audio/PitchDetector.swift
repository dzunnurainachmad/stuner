import Accelerate
import Foundation

struct PitchResult: Sendable {
    let frequency: Double
    let confidence: Double
}

enum PitchDetector {
    private static let lock = NSLock()
    private static var stableFrequency: Double?
    private static var stableCount: Int = 0
    private static let stableThreshold = 2  // readings needed before octave correction kicks in

    static func detectPitch(
        buffer: [Float],
        sampleRate: Double,
        threshold: Double = 0.2
    ) -> PitchResult? {
        let halfLength = buffer.count / 2
        guard halfLength > 2 else { return nil }

        // YIN difference using vDSP
        var difference = [Float](repeating: 0.0, count: halfLength)
        var delta = [Float](repeating: 0, count: halfLength)
        buffer.withUnsafeBufferPointer { bufPtr in
            let base = bufPtr.baseAddress!
            for tau in 0..<halfLength {
                vDSP_vsub(base + tau, 1, base, 1, &delta, 1, vDSP_Length(halfLength))
                vDSP_dotpr(delta, 1, delta, 1, &difference[tau], vDSP_Length(halfLength))
            }
        }

        // Cumulative mean normalized difference
        var cmnd = [Float](repeating: 0.0, count: halfLength)
        cmnd[0] = 1.0
        var runningSum: Float = 0.0
        for tau in 1..<halfLength {
            runningSum += difference[tau]
            cmnd[tau] = difference[tau] * Float(tau) / runningSum
        }

        // Find first dip below threshold
        var tauEstimate: Int?
        for tau in 2..<halfLength {
            if cmnd[tau] < Float(threshold) {
                var minTau = tau
                while minTau + 1 < halfLength && cmnd[minTau + 1] < cmnd[minTau] {
                    minTau += 1
                }
                tauEstimate = minTau
                break
            }
        }

        guard var tau = tauEstimate else { return nil }

        // Sub-octave correction: YIN sometimes locks onto 2x the true period
        // (octave below) when the fundamental's CMND dip is just above threshold.
        // Check if half the detected period also has a reasonable dip.
        let halfTau = tau / 2
        if halfTau >= 2 {
            let margin = max(2, halfTau / 10)
            let lo = max(2, halfTau - margin)
            let hi = min(halfLength - 1, halfTau + margin)
            var bestHalf = lo
            for t in lo...hi where cmnd[t] < cmnd[bestHalf] {
                bestHalf = t
            }
            // Prefer shorter period if:
            // 1. Half-period has a decent dip (below relaxed threshold)
            // 2. Full-period match is only moderate — if it's excellent (very low CMND),
            //    it's the true fundamental and shouldn't be corrected (protects E2, G3)
            if cmnd[bestHalf] < Float(threshold) + 0.15,
               cmnd[tau] > Float(threshold) * 0.5 {
                tau = bestHalf
            }
        }

        // Parabolic interpolation
        let betterTau: Double
        if tau > 0 && tau < cmnd.count - 1 {
            let s0 = Double(cmnd[tau - 1])
            let s1 = Double(cmnd[tau])
            let s2 = Double(cmnd[tau + 1])
            let denom = 2.0 * (2.0 * s1 - s2 - s0)
            betterTau = denom != 0 ? Double(tau) + (s2 - s0) / denom : Double(tau)
        } else {
            betterTau = Double(tau)
        }

        let frequency = sampleRate / betterTau
        let confidence = 1.0 - Double(cmnd[tau])

        guard frequency > 60.0, frequency < 1400.0, confidence > 0.7 else {
            return nil
        }

        let corrected = correctOctaveJump(frequency)
        return PitchResult(frequency: corrected, confidence: confidence)
    }

    /// Octave-correcting filter:
    /// During the first few readings (before stableThreshold), accepts whatever
    /// YIN returns so the correct pitch can establish itself. Once stable,
    /// rejects octave/harmonic jumps.
    private static func correctOctaveJump(_ frequency: Double) -> Double {
        lock.lock()
        defer { lock.unlock() }

        guard let stable = stableFrequency else {
            stableFrequency = frequency
            stableCount = 1
            return frequency
        }

        let ratio = frequency / stable

        // Close to stable (normal tuning variation)
        if ratio > 0.9 && ratio < 1.1 {
            stableFrequency = stable * 0.8 + frequency * 0.2
            stableCount += 1
            return stableFrequency!
        }

        // Only apply octave correction once we've confirmed the stable frequency
        // with enough consistent readings. Before that, accept the new frequency
        // so an initial wrong detection doesn't lock in the wrong octave.
        if stableCount < stableThreshold {
            stableFrequency = frequency
            stableCount = 1
            return frequency
        }

        // Check if this is an octave/harmonic jump
        let isOctaveUp = ratio > 1.8 && ratio < 2.2
        let isOctaveDown = ratio > 0.45 && ratio < 0.55
        let isFifthUp = ratio > 2.8 && ratio < 3.2
        let isFifthDown = ratio > 0.3 && ratio < 0.36

        if isOctaveUp || isOctaveDown || isFifthUp || isFifthDown {
            return stable  // Snap back
        }

        // Genuinely different pitch — accept (new string plucked)
        stableFrequency = frequency
        stableCount = 1
        return frequency
    }

    static func reset() {
        lock.lock()
        stableFrequency = nil
        stableCount = 0
        lock.unlock()
    }
}

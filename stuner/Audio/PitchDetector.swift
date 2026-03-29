import Accelerate
import Foundation

struct PitchResult: Sendable {
    let frequency: Double
    let confidence: Double
}

enum PitchDetector {

    static func detectPitch(
        buffer: [Float],
        sampleRate: Double,
        threshold: Double = 0.2
    ) -> PitchResult? {
        let halfLength = buffer.count / 2
        guard halfLength > 2 else { return nil }

        // YIN difference using vDSP
        // d(tau) = sum of (buffer[i] - buffer[i + tau])^2 for i in 0..<halfLength
        var difference = [Float](repeating: 0.0, count: halfLength)
        var delta = [Float](repeating: 0, count: halfLength)
        buffer.withUnsafeBufferPointer { bufPtr in
            let base = bufPtr.baseAddress!
            for tau in 0..<halfLength {
                // vDSP_vsub: C[i] = B[i] - A[i]
                // We want delta[i] = buffer[i] - buffer[i + tau]
                // So A = buffer[tau..], B = buffer[0..], C = delta
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

        guard let tau = tauEstimate else { return nil }

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

        return PitchResult(frequency: frequency, confidence: confidence)
    }
}

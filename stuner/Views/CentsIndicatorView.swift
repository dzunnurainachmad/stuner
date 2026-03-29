import SwiftUI

struct CentsIndicatorView: View {
    let centsOffset: Double  // -50 to +50
    let confidence: Double

    private var dotColor: Color {
        let absCents = abs(centsOffset)
        if confidence < 0.7 { return .gray }
        if absCents <= 2 { return .green }
        if absCents <= 10 { return .yellow }
        return .red
    }

    /// Map cents (-50...+50) to position (0...1)
    private var dotPosition: Double {
        guard confidence >= 0.7 else { return 0.5 }
        return (centsOffset + 50.0) / 100.0
    }

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                let width = geo.size.width

                ZStack(alignment: .leading) {
                    // Center tick
                    Rectangle()
                        .fill(Color.gray.opacity(0.4))
                        .frame(width: 2, height: 16)
                        .position(x: width / 2, y: 8)

                    // Quarter ticks
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 1, height: 10)
                        .position(x: width * 0.25, y: 8)
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 1, height: 10)
                        .position(x: width * 0.75, y: 8)

                    // Track
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 4)
                        .position(x: width / 2, y: 24)

                    // Dot
                    Circle()
                        .fill(dotColor)
                        .frame(width: 16, height: 16)
                        .shadow(color: dotColor.opacity(0.4), radius: 6)
                        .position(x: width * dotPosition, y: 24)
                }
            }
            .frame(height: 36)

            // Labels
            HStack {
                Text("FLAT")
                    .font(.system(size: 11))
                    .foregroundStyle(.gray)
                Spacer()
                Text(centsText)
                    .font(.system(size: 11))
                    .foregroundStyle(dotColor)
                Spacer()
                Text("SHARP")
                    .font(.system(size: 11))
                    .foregroundStyle(.gray)
            }
        }
        .animation(.easeOut(duration: 0.1), value: centsOffset)
    }

    private var centsText: String {
        guard confidence >= 0.7 else { return "—" }
        let rounded = Int(round(centsOffset))
        if rounded == 0 { return "IN TUNE" }
        return rounded > 0 ? "+\(rounded) cents" : "\(rounded) cents"
    }
}

#Preview {
    VStack(spacing: 40) {
        CentsIndicatorView(centsOffset: 0, confidence: 0.9)
        CentsIndicatorView(centsOffset: 15, confidence: 0.9)
        CentsIndicatorView(centsOffset: -3, confidence: 0.9)
        CentsIndicatorView(centsOffset: 0, confidence: 0.3)
    }
    .padding(40)
    .background(.black)
}

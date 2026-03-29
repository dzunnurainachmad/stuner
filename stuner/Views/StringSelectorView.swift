import SwiftUI

struct StringSelectorView: View {
    let strings: [StringTuning]       // 6 strings, index 0 = string 6 (low)
    let targetString: StringTuning?   // currently detected/locked string
    let selectedString: Int?          // locked string number (nil = auto)
    let onSelect: (Int?) -> Void      // tap handler — pass string number or nil to unlock

    var body: some View {
        HStack(spacing: 12) {
            ForEach(strings) { string in
                let isTarget = targetString?.stringNumber == string.stringNumber
                let isLocked = selectedString == string.stringNumber

                Button {
                    if isLocked {
                        onSelect(nil)  // tap again to unlock
                    } else {
                        onSelect(string.stringNumber)
                    }
                } label: {
                    Text(string.displayName)
                        .font(.system(size: 14))
                        .frame(width: 40, height: 40)
                        .foregroundStyle(isTarget ? .white : .gray)
                        .background(
                            Circle()
                                .fill(isTarget ? Color.white.opacity(0.1) : Color.clear)
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    isLocked ? Color.white : (isTarget ? Color.gray : Color.gray.opacity(0.3)),
                                    lineWidth: isLocked ? 2 : 1
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#Preview {
    let strings = GuitarTuning.standard.strings
    StringSelectorView(
        strings: strings,
        targetString: strings[4],  // B3
        selectedString: nil,
        onSelect: { _ in }
    )
    .padding()
    .background(.black)
}

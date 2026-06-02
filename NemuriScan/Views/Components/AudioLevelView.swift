import SwiftUI

struct AudioLevelView: View {
    let level: Float
    let barCount = 30

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                let threshold = Float(index) / Float(barCount)
                let active = level > threshold
                RoundedRectangle(cornerRadius: 2)
                    .fill(barColor(index: index, active: active))
                    .frame(width: 4)
                    .frame(height: barHeight(index: index))
                    .animation(.easeOut(duration: 0.08), value: active)
            }
        }
        .frame(height: 50)
    }

    private func barHeight(index: Int) -> CGFloat {
        let center = barCount / 2
        let distance = abs(index - center)
        let maxHeight: CGFloat = 50
        let minHeight: CGFloat = 8
        let normalized = 1.0 - Double(distance) / Double(center)
        return minHeight + CGFloat(normalized) * (maxHeight - minHeight)
    }

    private func barColor(index: Int, active: Bool) -> Color {
        guard active else { return Color.white.opacity(0.12) }
        let ratio = Float(index) / Float(barCount)
        if ratio < 0.5 { return Color(red: 0.48, green: 0.62, blue: 0.88) }
        if ratio < 0.8 { return Color(red: 0.91, green: 0.84, blue: 0.64) }
        return Color(red: 0.95, green: 0.4, blue: 0.3)
    }
}

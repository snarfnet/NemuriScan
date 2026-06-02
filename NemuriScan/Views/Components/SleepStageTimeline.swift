import SwiftUI

struct SleepStageTimeline: View {
    let stages: [SleepStage]
    let totalDuration: TimeInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(stages) { stage in
                        let width = totalDuration > 0
                            ? geo.size.width * CGFloat(stage.duration / totalDuration)
                            : geo.size.width / CGFloat(max(1, stages.count))
                        Rectangle()
                            .fill(stageColor(stage.type))
                            .frame(width: max(1, width))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .frame(height: 28)

            HStack(spacing: 12) {
                ForEach(SleepStageType.allCases, id: \.self) { type in
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(stageColor(type))
                            .frame(width: 10, height: 10)
                        Text(type.localizedName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
        }
    }

    private func stageColor(_ type: SleepStageType) -> Color {
        switch type {
        case .awake: return Color(red: 1.0, green: 0.6, blue: 0.2)       // orange
        case .light: return Color(red: 0.4, green: 0.8, blue: 0.9)        // cyan
        case .deep: return Color(red: 0.27, green: 0.27, blue: 0.78)      // indigo
        case .rem: return Color(red: 0.6, green: 0.3, blue: 0.85)         // purple
        }
    }
}

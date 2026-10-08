import SwiftUI

/// A fader drawn in its actual vertical coordinate space, avoiding transformed native slider geometry.
struct VerticalGainFader: View {
    @Binding var value: Double
    var label: String
    var identifier: String
    @State private var isDragging = false

    var body: some View {
        GeometryReader { geometry in
            let travel = max(1, geometry.size.height - 14)
            let normalized = CGFloat(min(1, max(0, value / 2)))
            let knobY = 7 + travel * (1 - normalized)
            ZStack {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.primary.opacity(0.13))
                    .frame(width: 5, height: travel)
                RoundedRectangle(cornerRadius: 3)
                    .fill(StudioAppearance.accent.opacity(0.7))
                    .frame(width: 5, height: travel * normalized)
                    .position(x: geometry.size.width / 2, y: 7 + travel - travel * normalized / 2)
                HStack(spacing: 14) {
                    Rectangle().fill(Color.primary.opacity(0.3)).frame(width: 3, height: 1)
                    Rectangle().fill(Color.primary.opacity(0.3)).frame(width: 3, height: 1)
                }
                .position(x: geometry.size.width / 2, y: 7 + travel * 0.5)
                RoundedRectangle(cornerRadius: 3)
                    .fill(.regularMaterial)
                    .overlay { RoundedRectangle(cornerRadius: 3).stroke(isDragging ? StudioAppearance.accent : Color.primary.opacity(0.5), lineWidth: 1) }
                    .overlay { Rectangle().fill(Color.primary.opacity(0.65)).frame(width: 15, height: 1) }
                    .frame(width: 24, height: 12)
                    .position(x: geometry.size.width / 2, y: knobY)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { gesture in
                    isDragging = true
                    value = min(2, max(0, 2 * (1 - Double((gesture.location.y - 7) / travel))))
                }
                .onEnded { _ in isDragging = false })
        }
        .help("\(label): \(StudioAppearance.db(value)) · drag up or down")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(StudioAppearance.db(value))
        .accessibilityIdentifier(identifier)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(2, value + 0.05)
            case .decrement: value = max(0, value - 0.05)
            @unknown default: break
            }
        }
    }
}

import SwiftUI

struct BoxIconView: View {
    let symbolName: String
    let tint: BoxTint
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint.color)
            .symbolRenderingMode(.hierarchical)
            .frame(width: size, height: size)
            .background(
                tint.color.opacity(0.18),
                in: RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: 12) {
        ForEach(BoxTint.allCases) { tint in
            BoxIconView(symbolName: "externaldrive.fill", tint: tint)
        }
    }
    .padding()
}

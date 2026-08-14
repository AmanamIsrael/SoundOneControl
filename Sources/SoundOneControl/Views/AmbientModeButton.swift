import SwiftUI

struct AmbientModeButton: View {
  let mode: AmbientMode
  let isSelected: Bool
  let fillsWidth: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 5) {
        Image(systemName: mode.symbol)
          .font(.body)
        Text(mode.shortTitle)
          .font(.caption.weight(.medium))
          .lineLimit(1)
          .minimumScaleFactor(0.85)
      }
      .frame(minWidth: fillsWidth ? 0 : 96, maxWidth: fillsWidth ? .infinity : nil)
      .frame(minHeight: 46)
      .padding(.horizontal, 8)
      .foregroundStyle(isSelected ? Color.white : Color.primary)
      .background(
        isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor),
        in: RoundedRectangle(cornerRadius: 8)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 8)
          .strokeBorder(Color.secondary.opacity(isSelected ? 0 : 0.18))
      }
    }
    .buttonStyle(.plain)
    .contentShape(RoundedRectangle(cornerRadius: 8))
    .accessibilityLabel(mode.title)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

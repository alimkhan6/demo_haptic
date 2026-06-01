import SwiftUI

struct ActionButtonView: View {
    let iconName: String
    let title: String
    let subtitle: String
    let gradientColors: [Color]
    let action: () -> Void
    let isDisabled: Bool
    
    init(
        iconName: String,
        title: String,
        subtitle: String,
        gradientColors: [Color],
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.iconName = iconName
        self.title = title
        self.subtitle = subtitle
        self.gradientColors = gradientColors
        self.isDisabled = isDisabled
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.system(size: 60))
                
                Text(title)
                    .font(.headline)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
            .background(
                LinearGradient(
                    colors: gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(16)
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1.0)
    }
}

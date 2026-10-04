import SwiftUI

enum ObserverStyle {
    static let secondaryText = Color("ObserverSupportingText")
    static let linkTint = Color("ObserverLink")
    // This blue has sufficient contrast with both black and white label text.
    static let solidButtonTint = Color(red: 0, green: 115.0 / 255, blue: 230.0 / 255)
}

private struct ActionWidthPreference: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// AnyLayout preserves control identity when larger text needs a vertical stack.
struct AdaptiveActionStack<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var width: CGFloat = 0
    let minimumHorizontalWidth: CGFloat
    let content: Content
    init(minimumHorizontalWidth: CGFloat = 480, @ViewBuilder content: () -> Content) {
        self.minimumHorizontalWidth = minimumHorizontalWidth
        self.content = content()
    }
    var body: some View {
        let layout = textSize.isAccessibilitySize || width < minimumHorizontalWidth
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        layout { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GeometryReader { geometry in
                Color.clear.preference(key: ActionWidthPreference.self, value: geometry.size.width)
            })
            .onPreferenceChange(ActionWidthPreference.self) { width = $0 }
    }
}

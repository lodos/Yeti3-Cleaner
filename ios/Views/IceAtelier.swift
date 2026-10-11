import SwiftUI

// Reference: Connector assets/premium-ice/tokens.json + IceGlassUI.swift;
// Node ios/Sources/NodeApp.swift (22pt panels, 20pt padding, rounded hero).
enum CleanerIce {
    static let midnight = Color(red: 7/255, green: 18/255, blue: 31/255)
    static let deepIce = Color(red: 23/255, green: 49/255, blue: 68/255)
    static let glacier = Color(red: 161/255, green: 221/255, blue: 1)
    static let mint = Color(red: 121/255, green: 232/255, blue: 206/255)
}

struct CleanerIceBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var opaque
    var body: some View {
        ZStack {
            LinearGradient(colors: [CleanerIce.midnight, Color(red: 0.015, green: 0.025, blue: 0.045)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            if !opaque {
                GeometryReader { geometry in
                    Image("IceAtelierBackground").resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped().opacity(0.3)
                }
            }
        }.ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct CleanerGlassSurface: View {
    @Environment(\.accessibilityReduceTransparency) private var opaque
    var body: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(opaque ? AnyShapeStyle(CleanerIce.deepIce) : AnyShapeStyle(.ultraThinMaterial))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.095), CleanerIce.glacier.opacity(0.035), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(LinearGradient(colors: [.white.opacity(0.36), CleanerIce.glacier.opacity(0.28), .white.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8)
            }
    }
}

struct CleanerSection<Content: View>: View {
    private let title: LocalizedStringKey?
    private let content: Content
    init(_ title: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) {
        self.title = title; self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title { Text(title).font(.headline).foregroundStyle(CleanerIce.glacier).accessibilityAddTraits(.isHeader) }
            content
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20).background(CleanerGlassSurface())
    }
}

struct CleanerMenu<Selection: Hashable, Content: View>: View {
    private let title: LocalizedStringKey
    @Binding private var selection: Selection
    private let identifier: String
    private let content: Content
    init(_ title: LocalizedStringKey, selection: Binding<Selection>, identifier: String = "", @ViewBuilder content: () -> Content) {
        self.title = title; _selection = selection; self.identifier = identifier; self.content = content()
    }
    var body: some View {
        LabeledContent(title) {
            Picker(title, selection: $selection) { content }.labelsHidden().pickerStyle(.menu).accessibilityIdentifier(identifier)
        }
    }
}

extension View {
    func cleanerScreen() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity).scrollContentBackground(.hidden).background(CleanerIceBackground())
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
    }
}

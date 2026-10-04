import SwiftUI

extension Color {
    static let wrapBackground = Color(white: 0.04)
    static let wrapCard = Color(white: 0.075)
    static let wrapBorder = Color.white.opacity(0.09)
    static let wrapSecondary = Color.white.opacity(0.55)
    static let wrapAccent = Color(red: 0.45, green: 0.64, blue: 1.0)
}

struct HeroGlow: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack {
                glow(Color.white.opacity(0.16), width: w * 0.8, height: 560)
                    .offset(x: -w * 0.05, y: -60)
                glow(Color.white.opacity(0.20), width: w * 0.65, height: 380)
                    .offset(x: w * 0.3, y: 120)
                glow(Color.wrapAccent.opacity(0.34), width: w * 0.7, height: 480)
                    .offset(x: w * 0.2, y: -20)
            }
            .frame(width: w, height: geo.size.height)
        }
        .frame(height: 520)
        .mask(
            LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .bottom)
        )
        .allowsHitTesting(false)
    }

    private func glow(_ color: Color, width: CGFloat, height: CGFloat) -> some View {
        Ellipse()
            .fill(EllipticalGradient(colors: [color, color.opacity(0)], center: .center,
                                     startRadiusFraction: 0, endRadiusFraction: 0.5))
            .frame(width: width, height: height)
    }
}

struct WrapPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PrimaryPill(configuration: configuration)
    }

    private struct PrimaryPill: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.black)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.white))
                .shadow(color: Color.wrapAccent.opacity(hovering && isEnabled ? 0.55 : 0), radius: 10)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.35)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.15), value: hovering)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }
}

struct WrapSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SecondaryPill(configuration: configuration)
    }

    private struct SecondaryPill: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        private var lit: Bool { hovering && isEnabled }

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.white.opacity(
                    configuration.isPressed ? 0.12 : (lit ? 0.07 : 0.03))))
                .overlay(Capsule().strokeBorder(lit ? Color.wrapAccent.opacity(0.7) : Color.wrapBorder))
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .opacity(isEnabled ? 1 : 0.35)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.15), value: hovering)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }
}

extension View {
    func rowHover(_ hovering: Bool, cornerRadius: CGFloat = 8) -> some View {
        self
            .background(RoundedRectangle(cornerRadius: cornerRadius).fill(Color.white.opacity(hovering ? 0.05 : 0)))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Color.wrapAccent.opacity(hovering ? 0.3 : 0)))
            .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

extension ButtonStyle where Self == WrapPrimaryButtonStyle {
    static var wrapPrimary: WrapPrimaryButtonStyle { .init() }
}

extension ButtonStyle where Self == WrapSecondaryButtonStyle {
    static var wrapSecondary: WrapSecondaryButtonStyle { .init() }
}

extension View {
    func wrapCard(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.wrapCard))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.wrapBorder))
    }
}

struct Eyebrow: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.wrapSecondary)
    }
}

struct Heading: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 22, weight: .medium))
            .tracking(-0.4)
            .foregroundStyle(.white)
    }
}

struct ThinProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule()
                    .fill(LinearGradient(colors: [.white, Color.wrapAccent],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 3)
        .animation(.easeOut(duration: 0.25), value: value)
    }
}

// MARK: - Dashboard pieces

struct CountBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Color.wrapSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.white.opacity(0.07)))
    }
}

struct CollapsibleHeader: View {
    let title: String
    let count: Int
    @Binding var isOpen: Bool
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { isOpen.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(hovering ? Color.white : Color.wrapSecondary)
                        .rotationEffect(.degrees(isOpen ? 0 : -90))
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("\(count)")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.wrapSecondary)
                }
                .contentShape(Rectangle())
                .opacity(hovering ? 1 : 0.92)
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)
        }
    }
}

struct WrapFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.03)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.wrapBorder))
    }
}

struct HintText: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Color.wrapSecondary)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
    }
}

enum WrapUser {
    static var defaultName: String {
        NSFullUserName().split(separator: " ").first.map(String.init) ?? "there"
    }
}

// MARK: - Nav bar that shrinks on scroll

extension EnvironmentValues {
    @Entry var setNavProgress: (CGFloat) -> Void = { _ in }
}

extension View {
    func reportsScrollForNav() -> some View {
        modifier(ReportsScrollForNav())
    }
}

private struct ReportsScrollForNav: ViewModifier {
    @Environment(\.setNavProgress) private var setNavProgress

    private let shrinkDistance: CGFloat = 160

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                let offset = geometry.contentOffset.y + geometry.contentInsets.top
                let progress = min(max(offset / shrinkDistance, 0), 1)
                return (progress * 24).rounded() / 24
            } action: { _, progress in
                setNavProgress(progress)
            }
            .onAppear { setNavProgress(0) }
    }
}

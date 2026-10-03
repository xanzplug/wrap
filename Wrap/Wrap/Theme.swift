import SwiftUI

// Wrap's look: near-black, white type, soft grey borders, pill buttons.

extension Color {
    /// The window background.
    static let wrapBackground = Color(white: 0.04)
    /// Cards and bars that sit on the background.
    static let wrapCard = Color(white: 0.075)
    /// Thin outlines around cards and secondary buttons.
    static let wrapBorder = Color.white.opacity(0.09)
    /// Quiet text: labels, captions, counts.
    static let wrapSecondary = Color.white.opacity(0.55)
}

/// White pill with black text, for the main action on a screen.
struct WrapPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.black)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.white))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.35)
    }
}

/// Dark pill with a thin outline, for everything else.
struct WrapSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.1 : 0.03)))
            .overlay(Capsule().strokeBorder(Color.wrapBorder))
            .opacity(isEnabled ? 1 : 0.35)
    }
}

extension ButtonStyle where Self == WrapPrimaryButtonStyle {
    static var wrapPrimary: WrapPrimaryButtonStyle { .init() }
}

extension ButtonStyle where Self == WrapSecondaryButtonStyle {
    static var wrapSecondary: WrapSecondaryButtonStyle { .init() }
}

extension View {
    /// A dark rounded card with a thin border.
    func wrapCard(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.wrapCard))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.wrapBorder))
    }
}

/// Small grey uppercase label above a heading, e.g. "SHOT LIST".
struct Eyebrow: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .medium))
            .tracking(1.2)
            .foregroundStyle(Color.wrapSecondary)
    }
}

/// A large heading with tight letter spacing.
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

/// A thin white progress line on a faint track.
struct ThinProgressBar: View {
    let value: Double   // 0...1

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule().fill(Color.white)
                    .frame(width: geo.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 3)
        .animation(.easeOut(duration: 0.25), value: value)
    }
}

// MARK: - Dashboard pieces

/// A small grey pill with a number, e.g. next to "Projects".
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

/// A thin line, a chevron, a big title and a count. Click to fold the section.
struct CollapsibleHeader: View {
    let title: String
    let count: Int
    @Binding var isOpen: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Rectangle().fill(Color.wrapBorder).frame(height: 1)
            Button {
                withAnimation(.easeOut(duration: 0.2)) { isOpen.toggle() }
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.wrapSecondary)
                        .rotationEffect(.degrees(isOpen ? 0 : -90))
                    Text(title)
                        .font(.system(size: 36, weight: .medium))
                        .tracking(-1)
                        .foregroundStyle(.white)
                    CountBadge(count: count)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

/// A dark text box with a thin border.
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

/// Grey helper text, for empty states and explanations.
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

/// The name in "Welcome back, …". Defaults to your Mac account's first name.
enum WrapUser {
    static var defaultName: String {
        NSFullUserName().split(separator: " ").first.map(String.init) ?? "there"
    }
}

// MARK: - Nav bar that shrinks on scroll

extension EnvironmentValues {
    /// How far the page is scrolled, from 0 (at the top) to 1 (scrolled past
    /// the shrink distance). The nav bar follows it frame by frame.
    @Entry var setNavProgress: (CGFloat) -> Void = { _ in }
}

extension View {
    /// Let the nav bar shrink smoothly as this scroll view scrolls.
    func reportsScrollForNav() -> some View {
        modifier(ReportsScrollForNav())
    }
}

private struct ReportsScrollForNav: ViewModifier {
    @Environment(\.setNavProgress) private var setNavProgress

    /// Points of scrolling it takes to go from full width to the small pill.
    private let shrinkDistance: CGFloat = 160

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                let offset = geometry.contentOffset.y + geometry.contentInsets.top
                let progress = min(max(offset / shrinkDistance, 0), 1)
                return (progress * 200).rounded() / 200   // fine steps, fewer redraws
            } action: { _, progress in
                setNavProgress(progress)
            }
            .onAppear { setNavProgress(0) }
    }
}

import SwiftUI
import Foundation

/// The bento kit's accent palette. Used for the atmospheric light leaks behind the cards
/// and for the gauge's glowing stroke.
extension Color {
    static let bentoPurple = Color(hex: "9D4EDD")
    static let bentoMagenta = Color(hex: "C77DFF")
    static let bentoBlue = Color(hex: "0077B6")
    static let bentoCyan = Color(hex: "00B4D8")
    static let bentoCopper = Color(hex: "E07A5F")
    static let bentoAmber = Color(hex: "F4A261")
    /// Muted cool gray for captions and small uppercase labels.
    static let studyMuted = Color(hex: "8E8E93")
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double
        if cleaned.count == 8 {
            red = Double((value >> 24) & 0xFF) / 255
            green = Double((value >> 16) & 0xFF) / 255
            blue = Double((value >> 8) & 0xFF) / 255
            alpha = Double(value & 0xFF) / 255
        } else {
            red = Double((value >> 16) & 0xFF) / 255
            green = Double((value >> 8) & 0xFF) / 255
            blue = Double(value & 0xFF) / 255
            alpha = 1
        }
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    /// The managed club's primary accent. Falls back to the default palette until a
    /// career exists — see `TeamTheme`.
    static var studyGreen: Color { TeamTheme.primary }
    /// The managed club's secondary accent.
    static var studyTeal: Color { TeamTheme.secondary }
    static let studyGold = Color(hex: "E6B84A")
    static let studyInk = Color(hex: "14201B")
    static let studyViolet = Color(hex: "7C5CFF")
    static let studyAmber = Color(hex: "F08A4B")
    static let studyCanvas = Color(hex: "09090D")
}

/// sRGB components held alongside `Color`, so accent colours can be judged for contrast.
struct RGB {
    var r: Double
    var g: Double
    var b: Double

    init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    init?(_ hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count >= 6 else { return nil }
        var value: UInt64 = 0
        Scanner(string: String(cleaned.prefix(6))).scanHexInt64(&value)
        self.init(
            r: Double((value >> 16) & 0xFF) / 255,
            g: Double((value >> 8) & 0xFF) / 255,
            b: Double(value & 0xFF) / 255
        )
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: 1) }

    /// Perceived brightness, 0 (black) to 1 (white).
    var luminance: Double { 0.299 * r + 0.587 * g + 0.114 * b }

    var isLight: Bool { luminance > 0.62 }

    /// Raises a club colour's brightness while keeping its hue and saturation, so a dark
    /// garnet reads as a vivid garnet instead of washing out to pink, and a near-black
    /// club colour becomes a usable neutral instead of vanishing against the canvas.
    var liftedForAccent: RGB {
        var hsv = HSV(self)
        if hsv.s < 0.08 {
            hsv.v = max(hsv.v, 0.76)
        } else {
            hsv.s = max(hsv.s, 0.5)
            hsv.v = max(hsv.v, 0.9)
        }
        return hsv.rgb
    }
}

/// Minimal RGB ↔ HSV, only bright enough to re-value a club colour without shifting hue.
private struct HSV {
    var h: Double
    var s: Double
    var v: Double

    init(_ c: RGB) {
        let maxChannel = max(c.r, c.g, c.b)
        let minChannel = min(c.r, c.g, c.b)
        let delta = maxChannel - minChannel
        v = maxChannel
        s = maxChannel == 0 ? 0 : delta / maxChannel
        if delta == 0 {
            h = 0
        } else if maxChannel == c.r {
            h = 60 * ((c.g - c.b) / delta).truncatingRemainder(dividingBy: 6)
        } else if maxChannel == c.g {
            h = 60 * ((c.b - c.r) / delta + 2)
        } else {
            h = 60 * ((c.r - c.g) / delta + 4)
        }
        if h < 0 { h += 360 }
    }

    var rgb: RGB {
        let chroma = v * s
        let x = chroma * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = v - chroma
        let channels: RGB
        switch h {
        case ..<60: channels = RGB(r: chroma, g: x, b: 0)
        case ..<120: channels = RGB(r: x, g: chroma, b: 0)
        case ..<180: channels = RGB(r: 0, g: chroma, b: x)
        case ..<240: channels = RGB(r: 0, g: x, b: chroma)
        case ..<300: channels = RGB(r: x, g: 0, b: chroma)
        default: channels = RGB(r: chroma, g: 0, b: x)
        }
        return RGB(r: channels.r + m, g: channels.g + m, b: channels.b + m)
    }
}

/// The managed club drives the whole app's palette: a Barcelona career runs garnet and
/// blue, a Real Madrid career white and gold. Before a career exists the default palette
/// is used unchanged, so club selection keeps the neutral bento look.
enum TeamTheme {
    static var club: Club?

    static var hasClub: Bool { club != nil }

    /// Primary accent, brightened enough to read on the near-black canvas.
    static var primary: Color { accent(club?.primaryHex) ?? Color(hex: "2FBF71") }

    /// Secondary accent, brightened the same way.
    static var secondary: Color { accent(club?.secondaryHex) ?? Color(hex: "1FA8A0") }

    /// Whether the primary is bright enough to need dark text on top of it.
    static var primaryIsLight: Bool { lifted(club?.primaryHex)?.isLight ?? false }

    static var secondaryIsLight: Bool { lifted(club?.secondaryHex)?.isLight ?? false }

    private static func lifted(_ hex: String?) -> RGB? {
        guard let hex, let rgb = RGB(hex) else { return nil }
        return rgb.liftedForAccent
    }

    private static func accent(_ hex: String?) -> Color? { lifted(hex)?.color }
}

extension Club {
    var primaryColor: Color { Color(hex: primaryHex) }
    var secondaryColor: Color { Color(hex: secondaryHex) }

    var usesDarkBadgeText: Bool {
        let hex = primaryHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard hex.count >= 6 else { return false }
        var value: UInt64 = 0
        Scanner(string: String(hex.prefix(6))).scanHexInt64(&value)
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        let luminance = 0.299 * red + 0.587 * green + 0.114 * blue
        return luminance > 0.62
    }

    var badgeTextColor: Color {
        usesDarkBadgeText ? Color.black.opacity(0.82) : Color.white
    }
}

extension PlayerRarity {
    var accentColor: Color {
        switch self {
        case .bronze: Color(hex: "B47142")
        case .silver: Color(hex: "AAB5C2")
        case .gold: Color(hex: "E0B94E")
        case .wonderkid: Color(hex: "42D6C3")
        case .icon: Color(hex: "E7D28A")
        }
    }

    var gradient: LinearGradient {
        let colors: [Color]
        switch self {
        case .bronze:
            colors = [Color(hex: "5D3720"), Color(hex: "B47142")]
        case .silver:
            colors = [Color(hex: "3E4854"), Color(hex: "AAB5C2")]
        case .gold:
            colors = [Color(hex: "4E3B13"), Color(hex: "C39A2A")]
        case .wonderkid:
            colors = [Color(hex: "123C3A"), Color(hex: "1B8C86"), Color(hex: "54D7C4")]
        case .icon:
            colors = [Color(hex: "121A2B"), Color(hex: "5A4A20"), Color(hex: "DCC477")]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var cardTextColor: Color {
        self == .silver ? Color(hex: "14201B") : .white
    }

    var cardSecondaryTextColor: Color {
        self == .silver ? Color.black.opacity(0.62) : Color.white.opacity(0.72)
    }
}

extension View {
    /// A bento card: translucent dark fill over a material, a hairline edge and a diffuse
    /// black shadow. Outer cards use the spec's 24–32pt radii.
    func surface(padding: CGFloat = 20, cornerRadius: CGFloat = 26) -> some View {
        self
            .padding(padding)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color(hex: "12121A").opacity(0.7))
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: Color.black.opacity(0.5), radius: 15, x: 0, y: 8)
    }

    func elevatedSurface(padding: CGFloat = 20, cornerRadius: CGFloat = 30) -> some View {
        self
            .padding(padding)
            .background(
                LinearGradient(
                    colors: [Color.studyViolet.opacity(0.12), Color.white.opacity(0.03), Color.studyAmber.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.studyViolet.opacity(0.45), Color.white.opacity(0.06), Color.studyAmber.opacity(0.35)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.5), radius: 15, x: 0, y: 8)
    }
}

/// The canvas: near-black with several heavily blurred light leaks in the bento accent
/// palette, layered so the glow shows in the negative space between cards.
struct AppBackground: View {
    /// Once a career exists the light leaks become the club's own colours, so the whole
    /// canvas reads as a red-and-blue mix for Barcelona or white-and-gold for Real Madrid.
    private var palette: [Color] {
        guard TeamTheme.hasClub else {
            return [.bentoPurple, .bentoMagenta, .bentoBlue, .bentoCyan, .bentoAmber, .bentoCopper]
        }
        return [
            TeamTheme.primary, TeamTheme.secondary, TeamTheme.primary,
            TeamTheme.secondary, TeamTheme.primary, TeamTheme.secondary
        ]
    }

    var body: some View {
        ZStack {
            Color.studyCanvas
            GeometryReader { proxy in
                let width = proxy.size.width
                let height = proxy.size.height
                let reach = max(width, height)
                let leaks = palette
                ZStack {
                    leak(leaks[0], 0.34, diameter: reach * 0.95, at: CGPoint(x: width * 0.10, y: -height * 0.08))
                    leak(leaks[1], 0.24, diameter: reach * 0.62, at: CGPoint(x: width * 0.32, y: height * 0.16))
                    leak(leaks[2], 0.28, diameter: reach * 0.80, at: CGPoint(x: width * 0.88, y: height * 0.42))
                    leak(leaks[3], 0.18, diameter: reach * 0.55, at: CGPoint(x: width * 0.58, y: height * 0.74))
                    leak(leaks[4], 0.22, diameter: reach * 0.66, at: CGPoint(x: width * 0.94, y: height * 1.02))
                    leak(leaks[5], 0.16, diameter: reach * 0.48, at: CGPoint(x: width * 0.72, y: height * 0.88))
                }
                .blur(radius: 40)
            }
        }
        .ignoresSafeArea()
    }

    private func leak(_ color: Color, _ opacity: Double, diameter: CGFloat, at point: CGPoint) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(opacity), color.opacity(opacity * 0.4), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: diameter / 2
                )
            )
            .frame(width: diameter, height: diameter)
            .position(point)
    }
}

struct ScreenHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(eyebrow.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(Color.studyGreen)
            Text(title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String?
    var symbol: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.studyGreen)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    var subtitle: String?
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.12), in: Circle())
                Spacer()
            }
            Text(value)
                .font(.system(size: 23, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
            VStack(alignment: .leading, spacing: 3) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(Color.studyMuted)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(padding: 16, cornerRadius: 24)
    }
}

struct BentoGaugeView: View {
    let progress: Double
    var label: String = "READY"
    var tint: Color = .studyGreen

    /// The arc runs through the club's own colours once a career exists.
    private var arcColors: [Color] {
        TeamTheme.hasClub
            ? [TeamTheme.primary, .white, TeamTheme.secondary, .white]
            : [Color.bentoCopper, .bentoAmber, .white, Color.bentoCyan]
    }

    var body: some View {
        let clamped = min(1, max(0, progress))
        ZStack {
            Circle()
                .trim(from: 0.15, to: 0.85)
                .stroke(Color.white.opacity(0.15), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(90))
            Circle()
                .trim(from: 0.15, to: 0.15 + clamped * 0.70)
                .stroke(
                    AngularGradient(
                        colors: arcColors,
                        center: .center,
                        startAngle: .degrees(54),
                        endAngle: .degrees(306)
                    ),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(90))
                .shadow(color: tint.opacity(0.6), radius: 8)
                .animation(.spring(response: 0.5, dampingFraction: 0.82), value: clamped)
            // High-brightness node riding the end of the active arc.
            if clamped > 0.005 {
                let radians = (360 * (0.15 + clamped * 0.70) + 90) * .pi / 180
                Circle()
                    .fill(Color.white)
                    .frame(width: 13, height: 13)
                    .shadow(color: tint.opacity(0.95), radius: 7)
                    .offset(x: cos(radians) * 70, y: sin(radians) * 70)
                    .animation(.spring(response: 0.5, dampingFraction: 0.82), value: clamped)
            }
            VStack(spacing: 2) {
                Text("\(Int(clamped * 100))%")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Color.white.opacity(0.6))
            }
        }
        .frame(width: 140, height: 140)
    }
}

struct Pill: View {
    let text: String
    var color: Color = .secondary
    var icon: String?

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(text)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12), in: Capsule())
    }
}

struct ReadinessBar: View {
    let progress: Double
    var tint: Color = .studyGreen
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.15))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.72), tint],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, proxy.size.width * min(1, max(0, progress))))
                    .shadow(color: tint.opacity(0.6), radius: 5)
                    .animation(.spring(response: 0.5, dampingFraction: 0.82), value: progress)
            }
        }
        .frame(height: height)
    }
}

/// A button's accent, expressed as a role rather than a raw colour so the label can stay
/// readable on a white Real Madrid button as easily as on a dark Barcelona one.
enum BentoAccent {
    case primary, secondary, gold, white, danger

    var color: Color {
        switch self {
        case .primary: TeamTheme.primary
        case .secondary: TeamTheme.secondary
        case .gold: Color(hex: "E6B84A")
        case .white: .white
        case .danger: .red
        }
    }

    /// The label colour that stays legible on a fill of `color`.
    var onColor: Color {
        switch self {
        case .primary: TeamTheme.primaryIsLight ? Color.studyInk : .white
        case .secondary: TeamTheme.secondaryIsLight ? Color.studyInk : .white
        case .gold, .white: Color.studyInk
        case .danger: .white
        }
    }
}

/// Buttons read their accent from this key rather than `\.tint`, which this toolchain
/// does not expose to a ButtonStyle. `.bentoTint` mirrors `.tint` at the call sites.
private struct BentoTintKey: EnvironmentKey {
    static let defaultValue: BentoAccent = .primary
}

extension EnvironmentValues {
    var bentoTint: BentoAccent {
        get { self[BentoTintKey.self] }
        set { self[BentoTintKey.self] = newValue }
    }
}

extension View {
    func bentoTint(_ accent: BentoAccent) -> some View { environment(\.bentoTint, accent) }
}

/// Buttons use the same language as the cards: a translucent fill, a hairline edge and
/// the spec's 12–16pt inner radius. The prominent variant is filled with the view's tint.
struct BentoProminentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.bentoTint) private var accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(accent.color.opacity(configuration.isPressed ? 1 : 0.86))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
            .foregroundStyle(accent.onColor)
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .shadow(color: accent.color.opacity(configuration.isPressed ? 0.15 : 0.32), radius: 10, y: 4)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct BentoBorderedButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.bentoTint) private var accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.12 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
            .foregroundStyle(accent.color)
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == BentoProminentButtonStyle {
    static var bentoProminent: BentoProminentButtonStyle { BentoProminentButtonStyle() }
}

extension ButtonStyle where Self == BentoBorderedButtonStyle {
    static var bentoBordered: BentoBorderedButtonStyle { BentoBorderedButtonStyle() }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color.studyGreen)
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 330)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }
}

struct ClubBadge: View {
    let club: Club
    var size: CGFloat = 42

    var body: some View {
        ZStack {
            Circle()
                .fill(club.primaryColor)
            Circle()
                .stroke(club.secondaryColor.opacity(0.95), lineWidth: max(2, size * 0.055))
                .padding(size * 0.07)
            Text(club.code)
                .font(.system(size: size * 0.25, weight: .black, design: .rounded))
                .foregroundStyle(club.badgeTextColor)
                .minimumScaleFactor(0.6)
                .padding(size * 0.14)
        }
        .frame(width: size, height: size)
        .shadow(color: club.primaryColor.opacity(0.22), radius: size * 0.12, y: size * 0.04)
    }
}

struct RarityTag: View {
    let rarity: PlayerRarity
    var compact: Bool = false

    var body: some View {
        Text(rarity.displayName.uppercased())
            .font(.system(size: compact ? 8 : 9, weight: .black, design: .rounded))
            .tracking(compact ? 0.6 : 0.9)
            .foregroundStyle(rarity == .silver ? Color.black.opacity(0.75) : Color.white.opacity(0.92))
            .padding(.horizontal, compact ? 6 : 8)
            .padding(.vertical, compact ? 3 : 4)
            .background(.black.opacity(rarity == .silver ? 0.12 : 0.22), in: Capsule())
    }
}

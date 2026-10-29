import SwiftUI

/// Liquid Glass arrived with the macOS 26 SDK, which is always present when compiling this
/// package, so the APIs below are safe to reference. What changes is whether the *running*
/// system draws them, which is what this reports.
enum GlassDesign {
    static var isSupported: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }
}

/// The bright top edge and softer bottom edge that make a panel read as glass rather than a
/// flat fill. Drawn on both paths so the app keeps one shape language.
struct GlassRim: View {
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.40),
                        Color.white.opacity(0.10),
                        Color.white.opacity(0.06),
                        Color.white.opacity(0.18)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1
            )
            .allowsHitTesting(false)
    }
}

/// Sits behind a card. On macOS 26 it is Apple's glass; below that it is whatever the caller
/// used before, so nothing about the older layout changes.
struct GlassBackdrop<Fallback: View>: View {
    let cornerRadius: CGFloat
    var tint: Color? = nil
    @ViewBuilder var fallback: () -> Fallback

    var body: some View {
        ZStack {
            if #available(macOS 26.0, *) {
                Color.clear
                    .glassEffect(Self.glass(tint: tint), in: shape)
            } else {
                fallback()
            }
        }
        .overlay(GlassRim(cornerRadius: cornerRadius))
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    @available(macOS 26.0, *)
    private static func glass(tint: Color?) -> Glass {
        var glass: Glass = .regular
        if let tint {
            glass = glass.tint(tint)
        }
        return glass
    }
}

private struct GlassChromeModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color?
    let interactive: Bool

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(glass, in: shape)
                .overlay(GlassRim(cornerRadius: cornerRadius))
        } else {
            content
                .background(Color(hex: "12121A").opacity(0.55), in: shape)
                .background(.ultraThinMaterial, in: shape)
                .overlay(GlassRim(cornerRadius: cornerRadius))
        }
    }

    @available(macOS 26.0, *)
    private var glass: Glass {
        var glass: Glass = .regular
        if let tint {
            glass = glass.tint(tint)
        }
        if interactive {
            glass = glass.interactive()
        }
        return glass
    }
}

extension View {
    /// Glass on the control layer: the tab bar, its pills and the small capsule buttons.
    /// `cornerRadius` of 999 or more gives a capsule.
    func glassChrome(
        cornerRadius: CGFloat = 20,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        modifier(GlassChromeModifier(cornerRadius: cornerRadius, tint: tint, interactive: interactive))
    }
}

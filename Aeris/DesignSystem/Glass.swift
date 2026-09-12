import SwiftUI

// MARK: - Shapes

/// Shared corner geometry so every glass surface reads as one family.
enum GlassShape {
    /// Small surfaces: stat tiles, chart cards.
    static var tile: RoundedRectangle {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
    }

    /// Larger surfaces: map panels, information panels.
    static var panel: RoundedRectangle {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
    }
}

// MARK: - Surface modifier

extension View {
    /// Applies a Liquid Glass surface.
    ///
    /// On iOS 26+ this is the native `glassEffect` API; on earlier releases it
    /// falls back to an ultra-thin system material with a hairline border, so
    /// the app stays stable wherever it runs.
    @ViewBuilder
    func glassSurface<S: Shape>(
        in shape: S,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(GlassFactory.make(tint: tint, interactive: interactive), in: shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(.quaternary, lineWidth: 0.5))
        }
    }
}

/// Builds `Glass` values outside of `@ViewBuilder` context — statements like
/// assignments are not allowed inside a view builder.
@available(iOS 26.0, *)
private enum GlassFactory {
    static func make(tint: Color?, interactive: Bool) -> Glass {
        var glass = Glass.regular
        if let tint {
            glass = glass.tint(tint)
        }
        if interactive {
            glass = glass.interactive()
        }
        return glass
    }
}

// MARK: - Glass container

/// Groups sibling glass elements so iOS 26 can blend and morph them.
/// A no-op on earlier releases.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat
    @ViewBuilder var content: () -> Content

    init(spacing: CGFloat = 10, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
    }
}

// MARK: - Glass button

/// A Liquid Glass button.
///
/// Uses the native `.glass` / `.glassProminent` button styles on iOS 26+ and a
/// material capsule style on earlier releases. `morphID`/`namespace` opt the
/// button into `glassEffectID` morphing inside a `GlassGroup`.
struct GlassButton: View {
    var title: String? = nil
    var icon: String? = nil
    var prominent = false
    var large = false
    var circle: CGFloat? = nil
    var tint: Color? = nil
    var morphID: String? = nil
    var namespace: Namespace.ID? = nil
    let action: () -> Void

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                if prominent {
                    core.buttonStyle(.glassProminent)
                } else {
                    core.buttonStyle(.glass)
                }
            } else {
                core.buttonStyle(MaterialGlassButtonStyle(prominent: prominent, tint: tint))
            }
        }
        .glassMorphID(morphID, in: namespace)
    }

    private var core: some View {
        Button {
            action()
        } label: {
            labelView
        }
        .tint(tint)
    }

    @ViewBuilder
    private var labelView: some View {
        if let circle {
            Image(systemName: icon ?? "questionmark")
                .font(.system(size: circle * 0.36, weight: .semibold))
                .frame(width: circle, height: circle)
        } else {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(labelFont)
                }
                if let title {
                    Text(title)
                        .font(labelFont)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .padding(.horizontal, large ? 34 : 20)
            .padding(.vertical, large ? 15 : 12)
        }
    }

    private var labelFont: Font {
        .system(.title3, design: .default, weight: .semibold)
    }
}

private extension View {
    @ViewBuilder
    func glassMorphID(_ id: String?, in namespace: Namespace.ID?) -> some View {
        if #available(iOS 26.0, *) {
            if let id, let namespace {
                self.glassEffectID(id, in: namespace)
            } else {
                self
            }
        } else {
            self
        }
    }
}

// MARK: - Pre-iOS 26 fallback style

struct MaterialGlassButtonStyle: ButtonStyle {
    var prominent = false
    var tint: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .background {
                if prominent {
                    Capsule().fill(tint ?? .accentColor)
                } else {
                    Capsule().fill(.ultraThinMaterial)
                }
            }
            .overlay(Capsule().strokeBorder(.quaternary, lineWidth: 0.5))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

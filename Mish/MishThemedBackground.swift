import SwiftUI
import CoreMotion

/// Renders a user's selected background. A theme can replace album-art blur,
/// while the original background settings remain in control when override is off.
struct MishThemedBackground: View {
    let artwork: UIImage?
    let fallbackTheme: MishBaseTheme
    let albumBlurEnabled: Bool
    let albumBlurRadius: Double

    @EnvironmentObject private var themeStore: MishThemeStore
    @StateObject private var motion = MishDeviceMotion()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var theme: MishTheme { themeStore.activeTheme }

    private var effectiveMotion: MishTheme.BackgroundMotion {
        reduceMotion ? .none : theme.motion
    }

    // MARK: Picking what to draw

    private struct Backdrop {
        let image: UIImage
        let blurRadius: CGFloat
    }

    /// Custom picture first, then album art, otherwise nil (gradient fallback).
    private var backdrop: Backdrop? {
        if let custom = themeStore.backgroundImage(for: theme) {
            let radius: Double = theme.blurEnabled ? theme.blurRadius : 0
            return Backdrop(image: custom, blurRadius: CGFloat(radius))
        }

        if let artwork, fallbackTheme != .amoled {
            let enabled: Bool = theme.overridesAlbumArtBlur ? theme.blurEnabled : albumBlurEnabled
            let base: Double = theme.overridesAlbumArtBlur ? theme.blurRadius : albumBlurRadius
            let radius: Double = enabled ? base : 0
            return Backdrop(image: artwork, blurRadius: CGFloat(radius))
        }

        return nil
    }

    // MARK: Body

    var body: some View {
        GeometryReader { geometry in
            content(size: geometry.size)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
        }
        .ignoresSafeArea()
        .onAppear { syncMotion(to: effectiveMotion) }
        .onChange(of: effectiveMotion) { _, newValue in
            syncMotion(to: newValue)
        }
        .onDisappear { motion.stop() }
    }

    @ViewBuilder
    private func content(size: CGSize) -> some View {
        let source = backdrop

        ZStack {
            theme.backgroundColor

            if let source {
                animatedImage(source, size: size)
            } else {
                fallbackGradient
            }

            if source == nil && artwork == nil {
                theme.backgroundColor.opacity(theme.overlayOpacity * 0.35)
            }
        }
    }

    // MARK: Image layer

    @ViewBuilder
    private func animatedImage(_ source: Backdrop, size: CGSize) -> some View {
        switch effectiveMotion {
        case .none:
            imageLayer(source, size: size, offset: .zero)

        case .scrolling:
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                imageLayer(
                    source,
                    size: size,
                    offset: scrollOffset(at: timeline.date, size: size)
                )
            }

        case .parallax:
            imageLayer(source, size: size, offset: parallaxOffset(size: size))
        }
    }

    private func imageLayer(_ source: Backdrop, size: CGSize, offset: CGSize) -> some View {
        let scale: CGFloat = effectiveMotion == .none ? 1.04 : 1.22

        return Image(uiImage: source.image)
            .resizable()
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .scaleEffect(scale)
            .offset(offset)
            .blur(radius: source.blurRadius)
            .overlay(theme.backgroundColor.opacity(theme.overlayOpacity))
            .clipped()
    }

    // MARK: Motion

    private func syncMotion(to mode: MishTheme.BackgroundMotion) {
        if mode == .parallax {
            motion.start()
        } else {
            motion.stop()
        }
    }

    /// Slow figure-eight drift; loops seamlessly because it is a sine wave.
    private func scrollOffset(at date: Date, size: CGSize) -> CGSize {
        let phase: Double = date.timeIntervalSinceReferenceDate * 0.2
        let travelX: CGFloat = size.width * 0.09
        let travelY: CGFloat = size.height * 0.05
        let x: CGFloat = CGFloat(sin(phase)) * travelX
        let y: CGFloat = CGFloat(cos(phase * 0.7)) * travelY
        return CGSize(width: x, height: y)
    }

    /// Moves against the tilt so the picture feels like it sits behind the glass.
    private func parallaxOffset(size: CGSize) -> CGSize {
        let travelX: CGFloat = size.width * 0.09
        let travelY: CGFloat = size.height * 0.05
        let x: CGFloat = -motion.tilt.width * travelX
        let y: CGFloat = -motion.tilt.height * travelY
        return CGSize(width: x, height: y)
    }

    // MARK: Fallback

    @ViewBuilder
    private var fallbackGradient: some View {
        switch fallbackTheme {
        case .smoked:
            LinearGradient(
                colors: smokedColors,
                startPoint: .top,
                endPoint: .bottom
            )
        case .amoled:
            Color.black
        case .clear:
            LinearGradient(
                colors: clearColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(.ultraThinMaterial)
        }
    }

    private var smokedColors: [Color] {
        let top = Color(white: 0.17)
        return [top, theme.backgroundColor]
    }

    private var clearColors: [Color] {
        let glow = theme.accentColor.opacity(0.3)
        let violet = Color.purple.opacity(0.22)
        return [glow, theme.backgroundColor, violet]
    }
}

// MARK: - Device tilt

/// Publishes a smoothed tilt in -1...1 on both axes.
/// Only runs while a parallax theme is on screen.
private final class MishDeviceMotion: ObservableObject {
    @Published private(set) var tilt: CGSize = .zero

    private let manager = CMMotionManager()
    private var baseline: (roll: Double, pitch: Double)?

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }

        baseline = nil
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            self.handle(roll: data.attitude.roll, pitch: data.attitude.pitch)
        }
    }

    func stop() {
        guard manager.isDeviceMotionActive else { return }
        manager.stopDeviceMotionUpdates()
        tilt = .zero
    }

    private func handle(roll: Double, pitch: Double) {
        // First reading = "center", so however the phone is held feels neutral.
        if baseline == nil {
            baseline = (roll: roll, pitch: pitch)
        }
        guard let base = baseline else { return }

        let range: Double = 0.5 // radians of tilt for full travel
        let targetX = clampUnit((roll - base.roll) / range)
        let targetY = clampUnit((pitch - base.pitch) / range)

        // Low-pass filter so it glides instead of jittering.
        let smoothing: Double = 0.12
        let currentX = Double(tilt.width)
        let currentY = Double(tilt.height)
        let nextX = currentX + (targetX - currentX) * smoothing
        let nextY = currentY + (targetY - currentY) * smoothing
        tilt = CGSize(width: nextX, height: nextY)
    }

    private func clampUnit(_ value: Double) -> Double {
        min(max(value, -1), 1)
    }
}

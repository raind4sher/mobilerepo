import SwiftUI
import UIKit

// MARK: - Turntable

/// The vinyl layout's record player.
///
/// - The record's angle is tied to the song position, so it turns while playing,
///   freezes when paused, and also turns when you use the seek bar.
/// - A tonearm swings onto the record when music plays, slowly moves inward as the
///   song goes on, and lifts off when paused.
/// - Drag around the record to scrub: clockwise goes forward, counter-clockwise goes back.
struct MishTurntableView: View {
    @EnvironmentObject private var player: PlayerModel

    // MARK: Tuning (change these to taste)

    /// How fast the record turns while playing (90 = one turn every 4 seconds).
    private let degreesPerSecond: Double = 90
    /// How many seconds of song one "record second" of dragging moves. Higher = faster seeking.
    private let scrubMultiplier: Double = 2.5

    // MARK: Layout

    private let discSize: CGFloat = 290
    private let canvasWidth: CGFloat = 360
    private let canvasHeight: CGFloat = 310
    private let armLength: CGFloat = 185
    /// Where the tonearm pivots, measured from the center of the record.
    private let pivot = CGPoint(x: 140, y: -120)

    // Tonearm angles in degrees (positive = clockwise).
    private let restAngle: Double = -8      // lifted, off the record
    private let outerAngle: Double = 7      // needle on the outer groove
    private let innerAngle: Double = 22     // needle near the label

    // MARK: Scratch state

    /// Extra rotation so the record stays under your finger even when seeking is clamped or scaled.
    @State private var spinOffset: Double = 0
    @State private var lastFingerAngle: Double?
    @State private var hapticDegrees: Double = 0
    @State private var feedback = UISelectionFeedbackGenerator()

    // MARK: Derived values

    private var needleDown: Bool {
        player.isPlaying || player.isScratching
    }

    private var discAngle: Double {
        player.liveCurrentTime * degreesPerSecond + spinOffset
    }

    private var armAngle: Double {
        guard needleDown else { return restAngle }

        let total = player.duration
        guard total > 0 else { return outerAngle }

        let fraction = min(max(player.liveCurrentTime / total, 0), 1)
        return outerAngle + (innerAngle - outerAngle) * fraction
    }

    // MARK: Body

    var body: some View {
        GeometryReader { geometry in
            let scale = min(1, geometry.size.width / canvasWidth)

            turntable
                .frame(width: canvasWidth, height: canvasHeight)
                .scaleEffect(scale)
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(height: canvasHeight)
        .padding(.vertical, 6)
        .onDisappear { finishDrag() }
    }

    private var turntable: some View {
        ZStack {
            discLayer
            sheen
            tonearm
            gestureLayer
        }
    }

    // MARK: Record

    private var discLayer: some View {
        TimelineView(.animation(paused: !needleDown)) { _ in
            MishVinylDisc(artwork: player.currentTrack?.artwork)
                .rotationEffect(.degrees(discAngle))
        }
        .frame(width: discSize, height: discSize)
        .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 6)
    }

    private var sheenColors: [Color] {
        let clear = Color.white.opacity(0)
        return [
            clear,
            Color.white.opacity(0.08),
            clear,
            clear,
            Color.white.opacity(0.06),
            clear
        ]
    }

    /// A fixed light reflection. It stays still while the record turns, which sells the motion.
    private var sheen: some View {
        Circle()
            .fill(AngularGradient(colors: sheenColors, center: .center))
            .frame(width: discSize, height: discSize)
            .allowsHitTesting(false)
    }

    // MARK: Tonearm

    private var tonearmHeight: CGFloat {
        armLength + MishTonearm.extraHeight
    }

    private var tonearmOffset: CGSize {
        let pivotFromCenter = tonearmHeight / 2 - MishTonearm.pivotFromTop
        return CGSize(width: pivot.x, height: pivot.y + pivotFromCenter)
    }

    private var tonearm: some View {
        let anchor = UnitPoint(x: 0.5, y: MishTonearm.pivotFromTop / tonearmHeight)

        return MishTonearm(length: armLength)
            .rotationEffect(.degrees(armAngle), anchor: anchor)
            .offset(tonearmOffset)
            .allowsHitTesting(false)
            .animation(.spring(response: 0.75, dampingFraction: 0.72), value: needleDown)
            .animation(.easeInOut(duration: 0.5), value: player.currentTrack?.url)
    }

    // MARK: Scratching

    private var gestureLayer: some View {
        Color.clear
            .frame(width: discSize, height: discSize)
            .contentShape(Circle())
            .gesture(scratchGesture)
            .accessibilityElement()
            .accessibilityLabel("Vinyl record")
            .accessibilityHint("Drag around the record to scrub through the song")
            .accessibilityAdjustableAction { direction in
                adjust(direction)
            }
    }

    private var scratchGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                handleDrag(at: value.location, start: value.startLocation)
            }
            .onEnded { _ in
                finishDrag()
            }
    }

    private func handleDrag(at point: CGPoint, start: CGPoint) {
        let center = discSize / 2
        let dx = point.x - center
        let dy = point.y - center
        let distance = (dx * dx + dy * dy).squareRoot()

        // Right at the middle the angle is jumpy, so ignore it.
        guard distance > 20 else { return }

        let finger: Double = Double(atan2(dy, dx)) * 180.0 / Double.pi

        guard let previous = lastFingerAngle else {
            // Wait for a real drag so a simple tap doesn't pause the music.
            let sx = point.x - start.x
            let sy = point.y - start.y
            let moved = (sx * sx + sy * sy).squareRoot()
            guard moved > 6 else { return }

            player.beginScratch()
            lastFingerAngle = finger
            return
        }

        var delta = finger - previous
        if delta > 180 {
            delta -= 360
        } else if delta < -180 {
            delta += 360
        }

        lastFingerAngle = finger
        applyScratch(degrees: delta)
    }

    private func applyScratch(degrees: Double) {
        let seconds = degrees / degreesPerSecond * scrubMultiplier
        let applied = player.scratch(by: seconds)

        // Keep the record exactly under the finger.
        spinOffset += degrees - applied * degreesPerSecond

        hapticDegrees += abs(degrees)
        if hapticDegrees >= 14 {
            hapticDegrees = 0
            feedback.selectionChanged()
        }
    }

    private func finishDrag() {
        if lastFingerAngle != nil {
            player.endScratch()
        }
        lastFingerAngle = nil
        hapticDegrees = 0
    }

    private func adjust(_ direction: AccessibilityAdjustmentDirection) {
        let step: TimeInterval = 10
        let now = player.liveCurrentTime
        let target: TimeInterval = direction == .increment ? now + step : now - step
        player.seek(to: target)
    }
}

// MARK: - Record

struct MishVinylDisc: View {
    let artwork: UIImage?

    private var bodyColors: [Color] {
        [Color(white: 0.25), Color.black, Color(white: 0.12), Color.black]
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: bodyColors,
                        center: .center,
                        startRadius: 8,
                        endRadius: 170
                    )
                )

            // Grooves
            ForEach(0..<7, id: \.self) { index in
                Circle()
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    .padding(CGFloat(index + 1) * 9)
            }

            label

            // Spindle hole
            Circle()
                .fill(Color.black)
                .frame(width: 12, height: 12)
                .overlay {
                    Circle()
                        .fill(Color.white.opacity(0.4))
                        .frame(width: 3, height: 3)
                }
        }
        .frame(width: 290, height: 290)
    }

    @ViewBuilder
    private var label: some View {
        if let artwork {
            Image(uiImage: artwork)
                .resizable()
                .scaledToFill()
                .frame(width: 155, height: 155)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                }
        } else {
            Circle()
                .fill(Color.mishGreen.opacity(0.75))
                .frame(width: 155, height: 155)
                .overlay {
                    Text("mish")
                        .font(.custom("delagothicone-regular", size: 30))
                        .foregroundStyle(Color.black)
                }
        }
    }
}

// MARK: - Tonearm

/// Drawn pointing straight down. The pivot sits `pivotFromTop` points below the top edge,
/// with the counterweight above it.
private struct MishTonearm: View {
    static let pivotFromTop: CGFloat = 50
    static let extraHeight: CGFloat = 70

    let length: CGFloat

    private var metal: LinearGradient {
        LinearGradient(
            colors: [Color(white: 0.92), Color(white: 0.62)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var dark: LinearGradient {
        LinearGradient(
            colors: [Color(white: 0.28), Color(white: 0.12)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Counterweight behind the pivot
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(dark)
                .frame(width: 18, height: 30)
                .offset(y: 4)

            // Arm tube
            Capsule()
                .fill(metal)
                .frame(width: 5, height: length)
                .offset(y: Self.pivotFromTop)

            // Headshell and needle
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(dark)
                .frame(width: 14, height: 24)
                .offset(y: Self.pivotFromTop + length - 12)

            Circle()
                .fill(Color.white)
                .frame(width: 3, height: 3)
                .offset(y: Self.pivotFromTop + length + 8)

            // Pivot base
            Circle()
                .fill(dark)
                .frame(width: 30, height: 30)
                .offset(y: Self.pivotFromTop - 15)

            Circle()
                .fill(metal)
                .frame(width: 12, height: 12)
                .offset(y: Self.pivotFromTop - 6)
        }
        .frame(width: 40, height: length + Self.extraHeight, alignment: .top)
        .shadow(color: Color.black.opacity(0.45), radius: 5, x: 3, y: 5)
    }
}

import SwiftUI
import UIKit

// MARK: - Turntable

/// The vinyl layout's record player.
///
/// - The record turns smoothly while playing, freezes when paused, and also turns when you
///   use the seek bar.
/// - A tonearm swings onto the record when music plays, slowly moves inward as the song
///   goes on, and lifts off when paused.
/// - Put a finger on the record and drag around it to scratch. The music follows your hand:
///   clockwise plays forward, counter-clockwise plays backwards, fast spins pitch it up,
///   and holding still silences it.
struct MishTurntableView: View {
    @EnvironmentObject private var player: PlayerModel

    // MARK: Tuning (change these to taste)

    /// How fast the record turns while playing (90 = one turn every 4 seconds).
    private let degreesPerSecond: Double = 90
    /// 1 = true scratching (turning the record at its normal speed plays at normal speed).
    /// Higher means the music moves faster than your hand, which is better for seeking.
    private let scrubMultiplier: Double = 1.5

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

    // MARK: State

    /// Smooths the record's angle so it never stutters.
    @State private var clock = MishDiscClock()
    /// Keeps the record's angle continuous after scratching or seeking.
    @State private var spinOffset: Double = 0

    @State private var scratchEnabled = false
    @State private var scratchAngle: Double = 0
    @State private var lastFingerAngle: Double?
    @State private var lastSpeedTime = Date()
    @State private var pendingDegrees: Double = 0
    @State private var smoothedSpeed: Double = 0
    @State private var hapticDegrees: Double = 0
    @State private var feedback = UISelectionFeedbackGenerator()

    // MARK: Derived values

    private var needleDown: Bool {
        player.isPlaying || player.isScratching
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
        TimelineView(.animation(paused: !needleDown)) { context in
            MishVinylDisc(artwork: player.currentTrack?.artwork)
                .equatable()
                .drawingGroup()
                .rotationEffect(.degrees(angle(at: context.date)))
        }
        .frame(width: discSize, height: discSize)
        .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 6)
    }

    /// The angle to draw this frame.
    private func angle(at date: Date) -> Double {
        if scratchEnabled {
            // The record sits exactly under your finger.
            clock.hold(at: scratchAngle, date: date)
            return scratchAngle
        }

        let target = player.liveCurrentTime * degreesPerSecond + spinOffset
        return clock.advance(
            to: date,
            playing: player.isPlaying,
            speed: degreesPerSecond,
            target: target
        )
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
            .accessibilityHint("Drag around the record to scratch and scrub through the song")
            .accessibilityAdjustableAction { direction in
                adjust(direction)
            }
    }

    private var scratchGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                handleDrag(at: value.location, start: value.startLocation, time: value.time)
            }
            .onEnded { _ in
                finishDrag()
            }
    }

    private func handleDrag(at point: CGPoint, start: CGPoint, time: Date) {
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

            beginScratch(finger: finger, time: time)
            return
        }

        var delta = finger - previous
        if delta > 180 {
            delta -= 360
        } else if delta < -180 {
            delta += 360
        }

        lastFingerAngle = finger

        guard scratchEnabled else { return }
        applyScratch(degrees: delta, time: time)
    }

    private func beginScratch(finger: Double, time: Date) {
        lastFingerAngle = finger
        scratchAngle = clock.angle
        pendingDegrees = 0
        smoothedSpeed = 0
        lastSpeedTime = time
        scratchEnabled = player.beginScratch()
    }

    private func applyScratch(degrees: Double, time: Date) {
        scratchAngle += degrees
        pendingDegrees += degrees

        // Turn hand movement into playback speed, a little smoothed so it doesn't crackle.
        let elapsed = time.timeIntervalSince(lastSpeedTime)
        if elapsed >= 0.008 {
            let angularSpeed = pendingDegrees / elapsed
            let rawSpeed = angularSpeed / degreesPerSecond * scrubMultiplier
            smoothedSpeed = smoothedSpeed * 0.4 + rawSpeed * 0.6
            player.setScratchSpeed(smoothedSpeed)

            pendingDegrees = 0
            lastSpeedTime = time
        }

        hapticDegrees += abs(degrees)
        if hapticDegrees >= 14 {
            hapticDegrees = 0
            feedback.selectionChanged()
        }
    }

    private func finishDrag() {
        if scratchEnabled {
            player.endScratch()
            // Carry on from exactly where the record was left.
            spinOffset = scratchAngle - player.liveCurrentTime * degreesPerSecond
            scratchEnabled = false
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

// MARK: - Smooth angle

/// Turns the audio clock into a steady rotation. The audio player's time moves in small
/// jumps, so the record turns at a constant speed and is only gently nudged to stay in sync.
final class MishDiscClock {
    private(set) var angle: Double = 0
    private var lastDate: Date?

    func hold(at newAngle: Double, date: Date) {
        angle = newAngle
        lastDate = date
    }

    func advance(to date: Date, playing: Bool, speed: Double, target: Double) -> Double {
        defer { lastDate = date }

        guard playing, let last = lastDate else {
            angle = target
            return angle
        }

        let dt = date.timeIntervalSince(last)
        guard dt > 0, dt < 0.25 else {
            // First frame after a pause or a long gap.
            angle = target
            return angle
        }

        angle += dt * speed

        let error = target - angle
        if abs(error) > 45 {
            // A seek or a new song: jump there.
            angle = target
        } else {
            angle += error * min(1, dt * 4)
        }
        return angle
    }
}

// MARK: - Record

struct MishVinylDisc: View, Equatable {
    let artwork: UIImage?

    static func == (lhs: MishVinylDisc, rhs: MishVinylDisc) -> Bool {
        lhs.artwork === rhs.artwork
    }

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

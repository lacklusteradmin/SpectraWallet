import SwiftUI

/// The coin drawn at the top of a wiki page, and the badge beside a row.
///
/// Shared by both wikis, which is why they take a `WikiCoinFace` rather than a
/// record: a coin page hands them a coin, a chain page hands them the coin
/// that chain runs on, and neither view needs to know which it got.

/// What the rotating coin and the badge need, so both wikis can draw one
/// without the views knowing whether they were handed a coin or a chain.
///
/// `assetName` is the artwork core already names on the row — no identifier is
/// built to be taken apart again. The wiki is indexed by coin and a coin's row
/// leads with wherever it lives first, so the identifier it used to build said
/// "USDC, native to Aptos" and drew nothing.
struct WikiCoinFace: Equatable {
    let name: String
    let symbol: String
    let assetName: String
    let color: Color
}

struct WikiRotatingCoin: View {
    let face: WikiCoinFace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var dragOffset: CGSize = .zero
    @State private var manualYaw: Double = 0
    @State private var manualPitch: Double = 0

    private let coinSize: CGFloat = 142

    var body: some View {
        Group {
            if reduceMotion {
                rotatingCoin(date: nil)
            } else {
                TimelineView(.animation) { context in
                    rotatingCoin(date: context.date)
                }
            }
        }
        .frame(height: 190)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($dragOffset) { value, state, _ in
                    state = value.translation
                }
                .onEnded { value in
                    manualYaw += Double(value.translation.width) * 0.72
                    manualPitch = Self.clamped(manualPitch - Double(value.translation.height) * 0.18, -18, 18)
                    spectraHaptic(.light)
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(face.name) \(AppLocalization.string("Interactive coin"))"))
    }

    private func rotatingCoin(date: Date?) -> some View {
        let automaticYaw = date.map { $0.timeIntervalSinceReferenceDate * 38 } ?? 0
        let yaw = automaticYaw + manualYaw + Double(dragOffset.width) * 0.72
        let pitch = Self.clamped(manualPitch - Double(dragOffset.height) * 0.18, -22, 22)
        let pulse = date.map { 0.5 + 0.5 * sin($0.timeIntervalSinceReferenceDate * 2.1) } ?? 0.5
        let radians = yaw * .pi / 180
        let edgeStrength = abs(sin(radians))
        let faceLight = 0.5 + 0.5 * cos(radians)

        return ZStack {
            orbitRings(yaw: yaw, pulse: pulse)
            coinShadow(yaw: yaw)
            ridgedCoinEdge(yaw: yaw, pitch: pitch, edgeStrength: edgeStrength)
            coinFace(yaw: yaw, pulse: pulse, faceLight: faceLight)
                .rotation3DEffect(.degrees(yaw), axis: (x: 0, y: 1, z: 0), perspective: 0.62)
                .rotation3DEffect(.degrees(pitch), axis: (x: 1, y: 0, z: 0), perspective: 0.62)
        }
        .frame(width: 232, height: 192)
    }

    private func orbitRings(yaw: Double, pulse: Double) -> some View {
        ZStack {
            Ellipse()
                .stroke(
                    AngularGradient(
                        colors: [
                            .clear,
                            face.color.opacity(0.72),
                            .white.opacity(0.72),
                            .clear,
                            face.color.opacity(0.48),
                            .clear,
                        ],
                        center: .center,
                        angle: .degrees(yaw * 0.7)
                    ),
                    lineWidth: 1.4
                )
                .frame(width: 208, height: 74)
                .rotationEffect(.degrees(-11))

            Ellipse()
                .stroke(face.color.opacity(0.16 + pulse * 0.08), lineWidth: 1)
                .frame(width: 176, height: 138)
                .rotationEffect(.degrees(23))
        }
        .blur(radius: 0.1)
    }

    private func coinShadow(yaw: Double) -> some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: [.black.opacity(0.24), .black.opacity(0.08), .clear],
                    center: .center,
                    startRadius: 8,
                    endRadius: 94
                )
            )
            .frame(width: 148, height: 30)
            .scaleEffect(x: CGFloat(0.78 + abs(cos(yaw * .pi / 180)) * 0.3), y: 1)
            .offset(y: 76)
            .blur(radius: 8)
    }

    private func ridgedCoinEdge(yaw: Double, pitch: Double, edgeStrength: Double) -> some View {
        let radians = yaw * .pi / 180
        let sideWidth = 16 + CGFloat(edgeStrength) * 46
        let offsetX = CGFloat(sin(radians)) * 15

        return ZStack {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            face.color.opacity(0.58),
                            .white.opacity(0.82),
                            face.color.opacity(0.84),
                            .black.opacity(0.34),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: sideWidth, height: coinSize * 1.03)

            ForEach(0..<24, id: \.self) { index in
                sideRidge(index: index, count: 24, width: sideWidth, edgeStrength: edgeStrength)
            }

            Capsule()
                .strokeBorder(.white.opacity(0.22), lineWidth: 1)
                .frame(width: sideWidth, height: coinSize * 1.03)
        }
        .offset(x: offsetX)
        .rotation3DEffect(.degrees(pitch * 0.34), axis: (x: 1, y: 0, z: 0), perspective: 0.62)
        .opacity(0.2 + edgeStrength * 0.8)
        .shadow(color: face.color.opacity(0.26), radius: 18, y: 8)
    }

    private func sideRidge(index: Int, count: Int, width: CGFloat, edgeStrength: Double) -> some View {
        let progress = CGFloat(index) / CGFloat(max(count - 1, 1))
        let x = -width / 2 + progress * width
        let centerDistance = abs(progress - 0.5) * 2
        let opacity = 0.26 + (1 - Double(centerDistance)) * 0.34 + edgeStrength * 0.26

        return Capsule()
            .fill(
                LinearGradient(
                    colors: [.white.opacity(0.72), face.color.opacity(0.34), .black.opacity(0.26)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 1.5, height: coinSize * (0.82 + centerDistance * 0.12))
            .offset(x: x)
            .opacity(opacity)
    }

    private func coinFace(yaw: Double, pulse: Double, faceLight: Double) -> some View {
        ZStack {
            Circle()
                .fill(
                    AngularGradient(
                        colors: [
                            .white.opacity(0.92),
                            face.color.opacity(0.94),
                            face.color.opacity(0.5),
                            .white.opacity(0.76 + faceLight * 0.12),
                            face.color.opacity(0.86),
                            .white.opacity(0.92),
                        ],
                        center: .center,
                        angle: .degrees(yaw * 0.45)
                    )
                )

            coinRidgeRing()

            Circle()
                .strokeBorder(.white.opacity(0.72), lineWidth: 2.6)
                .padding(8)

            Circle()
                .strokeBorder(face.color.opacity(0.34), lineWidth: 9)
                .padding(16)

            WikiStampedCoinLogo(face: face, size: 86)
                .compositingGroup()

            coinFaceGlare(yaw: yaw, pulse: pulse)

            Circle()
                .strokeBorder(.white.opacity(0.22), lineWidth: 1)
        }
        .frame(width: coinSize, height: coinSize)
        .clipShape(Circle())
        .shadow(color: face.color.opacity(0.34), radius: 24, y: 8)
        .shadow(color: .black.opacity(0.16), radius: 14, y: 12)
    }

    private func coinRidgeRing() -> some View {
        ZStack {
            ForEach(0..<56, id: \.self) { index in
                rimRidge(index: index, count: 56)
            }
        }
        .frame(width: coinSize, height: coinSize)
    }

    private func rimRidge(index: Int, count: Int) -> some View {
        let angle = Double(index) * 360 / Double(count)
        return Capsule()
            .fill(index.isMultiple(of: 2) ? .white.opacity(0.66) : face.color.opacity(0.5))
            .frame(width: 1.4, height: 10)
            .offset(y: -coinSize / 2 + 8)
            .rotationEffect(.degrees(angle))
            .opacity(0.68)
    }

    private func coinFaceGlare(yaw: Double, pulse: Double) -> some View {
        Circle()
            .fill(
                AngularGradient(
                    colors: [.clear, .white.opacity(0.42 + pulse * 0.16), .clear, .clear],
                    center: .center,
                    angle: .degrees(yaw * 0.32)
                )
            )
            .blendMode(.screen)
            .opacity(0.72)
            .padding(4)
    }

    private static func clamped(_ value: Double, _ lowerBound: Double, _ upperBound: Double) -> Double {
        min(max(value, lowerBound), upperBound)
    }
}

struct WikiStampedCoinLogo: View {
    let face: WikiCoinFace
    let size: CGFloat
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            .white.opacity(0.34),
                            face.color.opacity(0.2),
                            .black.opacity(0.18),
                        ],
                        center: .topLeading,
                        startRadius: 4,
                        endRadius: size * 0.68
                    )
                )
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(0.38), lineWidth: 1.4)
                }

            WikiCoinBadge(face: face, size: size * 0.68)
                .padding(size * 0.14)
                .clipShape(Circle())
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle()
                .strokeBorder(.black.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
    }
}

struct WikiCoinBadge: View {
    let face: WikiCoinFace
    let size: CGFloat
    var body: some View {
        CoinBadge(
            assetName: face.assetName, fallbackText: face.symbol,
            color: face.color, size: size
        )
    }
}

// MARK: — Data helpers

//
//  DirectionView.swift
//  final-project
//
//  Created by Whitman Stewart on 4/15/26.
//

import SwiftUI

struct DirectionView: View {
    @EnvironmentObject private var locationStore: LocationStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var displayedArrowRotation = 0.0
    @State private var isNearbyPulseExpanded = false
    let spot: SavedSpot?

    init(spot: SavedSpot? = nil) {
        self.spot = spot
    }

    private var activeSpot: SavedSpot? {
        // This screen can guide the user to either:
        // 1. the quick-save parking spot, or
        // 2. a specific place selected from the Places tab.
        spot ?? locationStore.quickSpot
    }

    private var compassArrowRotation: Double {
        locationStore.arrowRotation(to: activeSpot)
    }

    private var compassArrowDrift: CGFloat {
        // A tiny sine-wave drift keeps the arrow from feeling mechanically rigid
        // as heading updates come in from the phone's sensors.
        CGFloat(sin(displayedArrowRotation * .pi / 180) * 4)
    }

    private var isWithinNearbyZone: Bool {
        locationStore.isWithinGuidanceProximityZone(for: activeSpot)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if activeSpot == nil {
                    ContentUnavailableView(
                        "No Saved Location",
                        systemImage: "parkingsign",
                        description: Text("Save a location first so PinPoint can guide you back.")
                    )
                    .padding(.top, 80)
                } else {
                    compassCard
                    Button {
                        if let activeSpot {
                            locationStore.openInMaps(for: activeSpot)
                        }
                    } label: {
                        Label("Open Turn-by-Turn in Apple Maps", systemImage: "map")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.accentColor)
                    .padding(.top, 6)
                    
                }
            }
            .padding(20)
        }
        .background(screenBackground.ignoresSafeArea())
        .navigationTitle("Guide Back")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // This screen opts into a more responsive tracking mode so the arrow and distance
            // update smoothly as the user walks. Other screens stay on the lighter one-shot flow.
            displayedArrowRotation = compassArrowRotation
            locationStore.beginGuidanceTracking()
            isNearbyPulseExpanded = true
        }
        .onChange(of: compassArrowRotation) {
            // `arrowRotation(to:)` is normalized into 0..<360, which is good for a compass heading
            // but bad for animation. Example:
            // - old angle: 358°
            // - new angle: 2°
            //
            // Numerically that looks like a -356° jump, even though visually the arrow should
            // only move forward by 4°. To fix that, we "unwrap" the angle by applying the
            // shortest delta each time a new reading arrives.
            let delta = shortestRotationDelta(from: displayedArrowRotation, to: compassArrowRotation)
            displayedArrowRotation += delta
        }
        .onDisappear {
            locationStore.endGuidanceTracking()
        }
    }

    private var screenBackground: some View {
        LinearGradient(
            colors: colorScheme == .dark
            ? [
                Color(red: 0.11, green: 0.10, blue: 0.08),
                Color(red: 0.08, green: 0.10, blue: 0.14)
            ]
            : [
                Color(red: 0.98, green: 0.95, blue: 0.90),
                Color(red: 0.91, green: 0.94, blue: 0.98)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var cardFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.78)
    }

    private var compassCard: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 260, height: 260)

                Circle()
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.18) : Color.white.opacity(0.8), lineWidth: 18)
                    .frame(width: 220, height: 220)

                ForEach(["N", "E", "S", "W"], id: \.self) { label in
                    // These four labels are placed by offsetting them upward and then rotating each one.
                    // It is a simple way to fake compass tick labels without building a more complex layout.
                    Text(label)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.secondary)
                        .offset(y: -95)
                        .rotationEffect(rotation(for: label))
                }

                ZStack {
                    if isWithinNearbyZone {
                        nearbyPulseGraphic
                            .transition(.asymmetric(insertion: .scale(scale: 0.92).combined(with: .opacity),
                                                    removal: .scale(scale: 1.06).combined(with: .opacity)))
                    } else {
                        Image(systemName: "location.north.line.fill")
                            .font(.system(size: 88))
                            .foregroundStyle(.orange)
                            // `arrowRotation(to:)` comes from `LocationStore`.
                            // It represents "how many degrees should this arrow rotate so it points toward
                            // the saved location, relative to the phone's current heading?"
                            .rotationEffect(.degrees(displayedArrowRotation))
                            .offset(y: compassArrowDrift)
                            .animation(.timingCurve(0.37, 0, 0.63, 1, duration: 0.28), value: displayedArrowRotation)
                            .shadow(color: .orange.opacity(0.25), radius: 12, y: 6)
                            .transition(.asymmetric(insertion: .scale(scale: 1.04).combined(with: .opacity),
                                                    removal: .scale(scale: 0.94).combined(with: .opacity)))
                    }
                }
                .animation(.easeInOut(duration: 0.28), value: isWithinNearbyZone)
            }

            Text(locationStore.guidanceDistanceText(to: activeSpot) ?? "Locating...")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .monospacedDigit()

            if !isWithinNearbyZone {
                Text(locationStore.directionHint(to: activeSpot) ?? "Move a few steps so the compass can orient itself.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(cardFillColor, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    private var nearbyPulseGraphic: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(colorScheme == .dark ? 0.35 : 0.28), lineWidth: 3)
                .frame(width: 92, height: 92)
                .scaleEffect(isNearbyPulseExpanded ? 1.18 : 0.86)
                .opacity(isNearbyPulseExpanded ? 0 : 0.85)
                .animation(
                    .easeOut(duration: 1.5).repeatForever(autoreverses: false),
                    value: isNearbyPulseExpanded
                )

            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 82))
                .foregroundStyle(.orange)
                .shadow(color: .orange.opacity(0.2), radius: 10, y: 5)
        }
    }

    

    private func rotation(for label: String) -> Angle {
        // We keep the compass labels in one place in the view hierarchy and rotate them into position.
        switch label {
        case "N":
            return .degrees(0)
        case "E":
            return .degrees(90)
        case "S":
            return .degrees(180)
        default:
            return .degrees(270)
        }
    }

    private func shortestRotationDelta(from current: Double, to target: Double) -> Double {
        // Work in normalized compass space first.
        let normalizedCurrent = normalizedDegrees(current)
        let normalizedTarget = normalizedDegrees(target)
        var delta = normalizedTarget - normalizedCurrent

        // If the difference crosses the 0/360 seam, wrap it back to the shortest turn.
        if delta > 180 {
            delta -= 360
        } else if delta < -180 {
            delta += 360
        }

        return delta
    }

    private func normalizedDegrees(_ degrees: Double) -> Double {
        let normalized = degrees.truncatingRemainder(dividingBy: 360)
        return normalized >= 0 ? normalized : normalized + 360
    }
}

struct DirectionView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            DirectionView()
                .environmentObject(LocationStore())
        }
    }
}

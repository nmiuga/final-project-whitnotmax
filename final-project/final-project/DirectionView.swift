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

                Image(systemName: "location.north.line.fill")
                    .font(.system(size: 88))
                    .foregroundStyle(.orange)
                    // `arrowRotation(to:)` comes from `LocationStore`.
                    // It represents "how many degrees should this arrow rotate so it points toward
                    // the saved location, relative to the phone's current heading?"
                    .rotationEffect(.degrees(locationStore.arrowRotation(to: activeSpot)))
                    .shadow(color: .orange.opacity(0.25), radius: 12, y: 6)
            }

            Text(locationStore.distanceText(to: activeSpot) ?? "Locating...")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .monospacedDigit()

            Text(locationStore.directionHint(to: activeSpot) ?? "Move a few steps so the compass can orient itself.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(cardFillColor, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
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
}

struct DirectionView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            DirectionView()
                .environmentObject(LocationStore())
        }
    }
}

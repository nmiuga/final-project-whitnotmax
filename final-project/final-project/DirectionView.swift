//
//  DirectionView.swift
//  final-project
//
//  Created by Whitman Stewart on 4/15/26.
//

import SwiftUI

struct DirectionView: View {
    @EnvironmentObject private var locationStore: LocationStore

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if locationStore.savedSpot == nil {
                    ContentUnavailableView(
                        "No Saved Spot",
                        systemImage: "parkingsign",
                        description: Text("Save a location first so PinPoint can guide you back.")
                    )
                    .padding(.top, 80)
                } else {
                    compassCard
                    stepsCard
                }
            }
            .padding(20)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.95, blue: 0.90),
                    Color(red: 0.91, green: 0.94, blue: 0.98)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .navigationTitle("Guide Back")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var compassCard: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 260, height: 260)

                Circle()
                    .stroke(Color.white.opacity(0.8), lineWidth: 18)
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
                    // `arrowRotation` comes from `LocationStore`.
                    // It represents "how many degrees should this arrow rotate so it points toward
                    // the saved location, relative to the phone's current heading?"
                    .rotationEffect(.degrees(locationStore.arrowRotation))
                    .shadow(color: .orange.opacity(0.25), radius: 12, y: 6)
            }

            Text(locationStore.distanceText ?? "Locating...")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .monospacedDigit()

            Text(locationStore.directionHint ?? "Move a few steps so the compass can orient itself.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Quick tips")
                .font(.title3.weight(.bold))

            Label("The arrow points toward your saved location, like an AirTag-style beacon.", systemImage: "arrow.up.circle")
            Label("Distance updates as your GPS location refreshes.", systemImage: "figure.walk")
            Label("If the heading feels off, rotate once or walk a few steps to help the compass recalibrate.", systemImage: "safari")

            Button {
                locationStore.openInMaps()
            } label: {
                Label("Open Turn-by-Turn in Apple Maps", systemImage: "map")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.black.opacity(0.85))
            .padding(.top, 6)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
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

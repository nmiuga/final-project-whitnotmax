//
//  ContentView.swift
//  final-project
//
//  Created by Whitman Stewart on 4/13/26.
//

import SwiftUI
import MapKit
import CoreLocation

struct ContentView: View {
    @EnvironmentObject private var locationStore: LocationStore

    // `Map` in newer SwiftUI APIs is driven by a camera position instead of only a region binding.
    // We start with a harmless default region so the map has somewhere to render before GPS data arrives.
    // Once we have either the user's current location or a saved parking spot, `syncRegion()` will replace this.
    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 42.3601, longitude: -71.0589),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
    )

    private var annotations: [MapPinItem] {
        // We build map annotations from state owned by `LocationStore`.
        // This keeps the view "dumb": it only renders what the shared model says exists.
        var items: [MapPinItem] = []

        if let current = locationStore.currentLocation {
            items.append(
                MapPinItem(
                    title: "You",
                    subtitle: "Current location",
                    coordinate: current.coordinate,
                    tint: .blue
                )
            )
        }

        if let parked = locationStore.savedSpot {
            items.append(
                MapPinItem(
                    title: parked.name,
                    subtitle: parked.relativeTimestamp,
                    coordinate: parked.coordinate,
                    tint: .orange
                )
            )
        }

        return items
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    headerCard
                    mapCard
                    primaryActionCard
                    if let savedSpot = locationStore.savedSpot {
                        savedSpotCard(savedSpot)
                    } else {
                        emptyStateCard
                    }
                }
                .padding(20)
            }
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.95, green: 0.97, blue: 0.99),
                        Color(red: 0.88, green: 0.92, blue: 0.97)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .navigationTitle("PinPoint")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                locationStore.requestWhenInUsePermission()
                syncRegion()
            }
            .onChange(of: locationStore.currentLocation) {
                syncRegion()
            }
            .onChange(of: locationStore.savedSpot) {
                syncRegion()
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save your spot in one tap, then come back and let the app guide you back.")
                .font(.headline)
                .foregroundStyle(.primary)

            HStack(spacing: 12) {
                Label(locationStore.authorizationLabel, systemImage: locationStore.authorizationIcon)
                Spacer()
                if let distance = locationStore.distanceText {
                    Text(distance)
                        .font(.headline)
                        .monospacedDigit()
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if let message = locationStore.statusMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var mapCard: some View {
        // The map's camera is bound to `position`, so when we assign a new `MapCameraPosition`
        // in `syncRegion()`, the visible map updates automatically.
        Map(position: $position) {
            ForEach(annotations) { item in
                // Each `Annotation` drops a custom SwiftUI view onto the map at a coordinate.
                // We use the same annotation type for both "you" and the saved parking spot,
                // and visually distinguish them with different SF Symbols and tint colors.
                Annotation(item.title, coordinate: item.coordinate) {
                    VStack(spacing: 6) {
                        Image(systemName: item.title == "You" ? "location.fill" : "car.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(item.tint, in: Circle())
                        Text(item.title)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.thinMaterial, in: Capsule())
                    }
                }
            }
        }
        .frame(height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if locationStore.savedSpot != nil {
                NavigationLink(destination: DirectionView()) {
                    Label("Guide Me", systemImage: "scope")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.thinMaterial, in: Capsule())
                }
                .padding(14)
            }
        }
    }

    private var primaryActionCard: some View {
        VStack(spacing: 14) {
            Button {
                locationStore.saveCurrentSpot()
            } label: {
                Label(locationStore.savedSpot == nil ? "Save This Location" : "Update Saved Location", systemImage: "parkingsign.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .foregroundStyle(.white)
            }
            .disabled(!locationStore.canSaveCurrentLocation)

            HStack(spacing: 12) {
                Button {
                    locationStore.refreshLocation()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.black.opacity(0.75))

                Button(role: .destructive) {
                    locationStore.clearSavedSpot()
                } label: {
                    Label("Clear", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(locationStore.savedSpot == nil)
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func savedSpotCard(_ spot: SavedSpot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Saved Spot")
                .font(.title3.weight(.bold))

            Label(spot.name, systemImage: "car.fill")
                .font(.headline)

            Text(spot.formattedTimestamp)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let distance = locationStore.distanceText {
                Text("You are currently \(distance.lowercased()) away.")
                    .font(.subheadline.weight(.medium))
            }

            if let hint = locationStore.directionHint {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button {
                locationStore.openInMaps()
            } label: {
                Label("Open in Apple Maps", systemImage: "map.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var emptyStateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No saved spot yet")
                .font(.title3.weight(.bold))
            Text("When you park, open the app and tap Save This Location. PinPoint will remember the exact spot so you can walk back later.")
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func syncRegion() {
        // This helper decides what the map should focus on.
        //
        // Priority:
        // 1. If a saved spot exists, center on that because it is the main destination.
        // 2. Otherwise, center on the user's current location once we have GPS data.
        //
        // The small span keeps the map zoomed in enough to feel like a "where exactly is it?"
        // tool rather than a broad city-level map.
        if let savedSpot = locationStore.savedSpot {
            position = .region(
                MKCoordinateRegion(
                    center: savedSpot.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
                )
            )
        } else if let current = locationStore.currentLocation {
            position = .region(
                MKCoordinateRegion(
                    center: current.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
                )
            )
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(LocationStore())
    }
}

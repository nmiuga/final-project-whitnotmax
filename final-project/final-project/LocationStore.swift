//
//  LocationStore.swift
//  final-project
//
//  Created by Codex on 4/17/26.
//

import Foundation
import CoreLocation
import MapKit
import SwiftUI
import Combine

@MainActor
final class LocationStore: NSObject, ObservableObject {
    // MARK: Published state used by the SwiftUI views
    //
    // `@Published` means "tell SwiftUI to refresh any subscribed views when this value changes."
    // The views don't fetch GPS data themselves; they observe this object instead.
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var currentHeading: CLHeading?
    @Published var savedSpot: SavedSpot?
    @Published private(set) var statusMessage: String?

    // `CLLocationManager` is Apple's main GPS / compass manager.
    // It talks to the system, asks permission, and delivers location + heading updates
    // through delegate callbacks.
    private let locationManager = CLLocationManager()

    // The saved parking spot is persisted in `UserDefaults` under this key
    // so the app can restore it after closing and reopening.
    private let storageKey = "savedSpot"

    override init() {
        // We capture the current authorization status immediately so the UI can render
        // the right state before the first delegate callback happens.
        authorizationStatus = locationManager.authorizationStatus

        // If the user saved a location in a previous app session, restore it now.
        savedSpot = SavedSpotStorage.load(forKey: storageKey)
        super.init()

        // The location manager sends updates back to this object via CLLocationManagerDelegate.
        locationManager.delegate = self

        // "Nearest ten meters" is a reasonable tradeoff for a parked-car app:
        // accurate enough to be useful, but not as battery-hungry as the most precise mode.
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters

        // Ignore tiny movement changes so we do not over-update the UI while the user is standing still.
        locationManager.distanceFilter = 5

        // Only report heading changes once the phone turns at least 5 degrees.
        locationManager.headingFilter = 5
    }

    var canSaveCurrentLocation: Bool {
        // The one-tap save button should only work once we both:
        // 1. have permission, and
        // 2. actually have a GPS fix.
        currentLocation != nil && isAuthorized
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    var authorizationLabel: String {
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return "Location Ready"
        case .notDetermined:
            return "Permission Needed"
        case .denied:
            return "Location Denied"
        case .restricted:
            return "Location Restricted"
        @unknown default:
            return "Location Unknown"
        }
    }

    var authorizationIcon: String {
        isAuthorized ? "location.fill" : "location.slash"
    }

    var distanceText: String? {
        guard let currentLocation, let savedSpot else { return nil }

        // `distance(from:)` returns meters between the user's current position and the saved spot.
        let meters = currentLocation.distance(from: savedSpot.location)
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .providedUnit
        formatter.unitStyle = .medium

        // Keep nearby values in meters, but switch to kilometers once the distance gets larger.
        // That makes the readout feel natural and easy to scan.
        if meters >= 1000 {
            let value = Measurement(value: meters / 1000, unit: UnitLength.kilometers)
            return formatter.string(from: value)
        } else {
            let value = Measurement(value: meters, unit: UnitLength.meters)
            return formatter.string(from: value)
        }
    }

    var directionHint: String? {
        guard let currentLocation, let savedSpot else { return nil }

        // `bearing` is the compass direction from the current coordinate to the saved coordinate.
        // Example: if the saved car is due east, this returns roughly 90 degrees.
        let bearing = currentLocation.coordinate.bearing(to: savedSpot.coordinate)

        if let currentHeading {
            // `trueHeading` is the direction the top of the phone is currently facing.
            // Subtracting the phone heading from the destination bearing tells us how much
            // the user would need to turn to face the saved spot.
            let turnAngle = normalizeDegrees(bearing - currentHeading.trueHeading)
            return "Head \(cardinalDirection(for: bearing)). Turn \(Int(turnAngle.rounded()))° from where your phone is facing."
        }

        // If heading data is not available yet, fall back to a simpler text hint.
        return "Head \(cardinalDirection(for: bearing)) toward your saved spot."
    }

    var arrowRotation: Double {
        guard let currentLocation, let savedSpot else { return 0 }

        // Same idea as `directionHint`, but this value is used directly by the UI arrow.
        // We compute the destination bearing, subtract the phone heading, then normalize
        // the result so it always falls between 0 and 360 degrees.
        let bearing = currentLocation.coordinate.bearing(to: savedSpot.coordinate)
        let heading = currentHeading?.trueHeading ?? 0
        return normalizeDegrees(bearing - heading)
    }

    func requestWhenInUsePermission() {
        // Refresh authorization in case it changed in Settings while the app was backgrounded.
        authorizationStatus = locationManager.authorizationStatus

        if authorizationStatus == .notDetermined {
            // First run: ask the system permission dialog to appear.
            locationManager.requestWhenInUseAuthorization()
            statusMessage = "Allow location access so PinPoint can save where you parked."
        } else if isAuthorized {
            // If permission already exists, start location + heading updates immediately.
            startUpdating()
        } else if authorizationStatus == .denied {
            statusMessage = "Location access is off. You can enable it in Settings to save and find your spot."
        }
    }

    func refreshLocation() {
        guard isAuthorized else {
            requestWhenInUsePermission()
            return
        }

        // `requestLocation()` asks for a one-time fresh location sample.
        // We also restart heading updates in case the compass wasn't active yet.
        locationManager.requestLocation()
        if CLLocationManager.headingAvailable() {
            locationManager.startUpdatingHeading()
        }
    }

    func saveCurrentSpot() {
        guard let currentLocation else {
            statusMessage = "Waiting for your current location. Try Refresh in a moment."
            return
        }

        // We convert the live CLLocation into a small codable model that is easy to store.
        let spot = SavedSpot(
            latitude: currentLocation.coordinate.latitude,
            longitude: currentLocation.coordinate.longitude,
            timestamp: .now
        )
        savedSpot = spot

        // Persist the saved spot so it survives app relaunches.
        SavedSpotStorage.save(spot, forKey: storageKey)
        statusMessage = "Saved your current position."
    }

    func clearSavedSpot() {
        savedSpot = nil
        SavedSpotStorage.clear(forKey: storageKey)
        statusMessage = "Saved spot cleared."
    }

    func openInMaps() {
        guard let savedSpot else { return }

        // This creates a real Apple Maps destination from our saved coordinate.
        // The app can then hand off walking directions if the user wants a more
        // traditional navigation experience than the beacon-style UI.
        let item = MKMapItem(location: savedSpot.location, address: nil)
        item.name = savedSpot.name
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
        ])
    }

    private func startUpdating() {
        // `startUpdatingLocation()` keeps the GPS stream alive so distance changes
        // update automatically as the user walks.
        locationManager.startUpdatingLocation()

        // We also request an immediate one-shot update so the UI does not have to wait
        // for the next periodic GPS callback.
        locationManager.requestLocation()

        if CLLocationManager.headingAvailable() {
            // Heading updates power the rotating arrow in the guidance screen.
            locationManager.startUpdatingHeading()
        }
    }

    private func cardinalDirection(for degrees: Double) -> String {
        // Convert a raw compass angle into a friendly text label.
        // This makes it easier to read hints like "Head northeast" instead of "Head 43°".
        switch normalizeDegrees(degrees) {
        case 337.5..., ..<22.5:
            return "north"
        case 22.5..<67.5:
            return "northeast"
        case 67.5..<112.5:
            return "east"
        case 112.5..<157.5:
            return "southeast"
        case 157.5..<202.5:
            return "south"
        case 202.5..<247.5:
            return "southwest"
        case 247.5..<292.5:
            return "west"
        default:
            return "northwest"
        }
    }

    private func normalizeDegrees(_ degrees: Double) -> Double {
        // Bearings can go negative or above 360 after subtraction.
        // This wraps them back into the standard compass range of 0..<360.
        let normalized = degrees.truncatingRemainder(dividingBy: 360)
        return normalized >= 0 ? normalized : normalized + 360
    }
}

extension LocationStore: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // CLLocationManager delegate methods are not isolated to the main actor by default.
        // Because our published state drives SwiftUI, we hop back to the main actor
        // before mutating anything the UI observes.
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus

            if isAuthorized {
                statusMessage = "Location is active."
                startUpdating()
            } else if manager.authorizationStatus == .denied {
                statusMessage = "Location access is denied. Enable it in Settings to use PinPoint."
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Apple can provide multiple candidate locations in one callback.
        // The last item is usually the freshest reading, so we use that.
        guard let location = locations.last else { return }

        Task { @MainActor in
            currentLocation = location
            if savedSpot != nil {
                statusMessage = "Tracking your distance to the saved spot."
            } else {
                statusMessage = "Current location updated."
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        Task { @MainActor in
            // The direction screen uses this heading to rotate the arrow in real time.
            currentHeading = newHeading
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            statusMessage = "Could not update your location: \(error.localizedDescription)"
        }
    }
}

private enum SavedSpotStorage {
    static func load(forKey key: String) -> SavedSpot? {
        // Decode the saved JSON blob from UserDefaults back into our Swift model.
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SavedSpot.self, from: data)
    }

    static func save(_ spot: SavedSpot, forKey key: String) {
        // Encode the model as JSON because CLLocationCoordinate2D itself is not directly stored in UserDefaults.
        guard let data = try? JSONEncoder().encode(spot) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func clear(forKey key: String) {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

struct SavedSpot: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    let timestamp: Date

    var coordinate: CLLocationCoordinate2D {
        // Convenient bridge for MapKit and compass math.
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        // Convenient bridge for distance calculations and MKMapItem creation.
        CLLocation(latitude: latitude, longitude: longitude)
    }

    var name: String {
        "Saved Parking Spot"
    }

    var formattedTimestamp: String {
        timestamp.formatted(date: .abbreviated, time: .shortened)
    }

    var relativeTimestamp: String {
        timestamp.formatted(.relative(presentation: .named))
    }
}

struct MapPinItem: Identifiable {
    // Lightweight view model for map annotations.
    // It lets the UI describe pins without exposing the full saved spot / CLLocation types directly.
    let id = UUID()
    let title: String
    let subtitle: String
    let coordinate: CLLocationCoordinate2D
    let tint: Color
}

private extension CLLocationCoordinate2D {
    func bearing(to destination: CLLocationCoordinate2D) -> Double {
        // This is the core navigation math:
        // given two coordinates on Earth, calculate the compass bearing from one to the other.
        //
        // Steps:
        // 1. Convert degrees to radians because trig functions use radians.
        // 2. Compute the delta in longitude.
        // 3. Use the standard great-circle bearing formula.
        // 4. Convert the result back to degrees for easier UI use.
        let originLatitude = latitude.radians
        let originLongitude = longitude.radians
        let destinationLatitude = destination.latitude.radians
        let destinationLongitude = destination.longitude.radians

        let longitudeDifference = destinationLongitude - originLongitude
        let y = sin(longitudeDifference) * cos(destinationLatitude)
        let x = cos(originLatitude) * sin(destinationLatitude) - sin(originLatitude) * cos(destinationLatitude) * cos(longitudeDifference)
        let radiansBearing = atan2(y, x)
        return radiansBearing.degrees
    }
}

private extension Double {
    // Small helpers to keep the bearing math readable.
    var radians: Double { self * .pi / 180 }
    var degrees: Double { self * 180 / .pi }
}

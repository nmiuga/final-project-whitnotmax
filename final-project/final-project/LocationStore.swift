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
#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor
final class LocationStore: NSObject, ObservableObject {
    enum AppTab: Hashable {
        case quickSave
        case places
    }

    private enum LaunchAction {
        case saveQuickSpot
        case guideQuickSpot
    }

    private enum SaveRequest {
        case quickSpot
        case place(name: String, iconEmoji: String)
    }

    static let appGroupIdentifier = "group.whitmans.final-project"
    static let quickSpotStorageKey = "quickSpot"
    static let savedPlacesStorageKey = "savedPlaces"
    static let debugSlowSaveKey = "debugSimulateSlowSave"

    // MARK: Published state used by the SwiftUI views
    //
    // `@Published` means "tell SwiftUI to refresh any subscribed views when this value changes."
    // The views don't fetch GPS data themselves; they observe this object instead.
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var currentHeading: CLHeading?

    // `quickSpot` powers the "park now with one tap" workflow.
    // It stays separate from the full places list so the fast flow stays simple.
    @Published var quickSpot: SavedSpot?

    // `savedPlaces` powers the more flexible second tab where users can keep multiple locations.
    @Published private(set) var savedPlaces: [SavedSpot]

    @Published private(set) var statusMessage: String?
    @Published var selectedTab: AppTab = .quickSave
    @Published var activeGuidanceSpot: SavedSpot?
    @Published private(set) var pendingSaveDescription: String?
    @Published private(set) var successfulSaveCount = 0
    @Published var debugSimulateSlowSave: Bool {
        didSet {
            storageDefaults.set(debugSimulateSlowSave, forKey: Self.debugSlowSaveKey)
        }
    }

    // `CLLocationManager` is Apple's main GPS / compass manager.
    // It talks to the system, asks permission, and delivers location + heading updates
    // through delegate callbacks.
    private let locationManager = CLLocationManager()
    private let storageDefaults: UserDefaults

    // We persist the quick-save spot and the multi-place list separately so each part of the UI
    // can restore exactly what it needs when the app relaunches.
    private var pendingLaunchAction: LaunchAction?
    private var pendingSaveRequest: SaveRequest?
    private var pendingSaveReadyAfter: Date?
    private var pendingSaveDelayTask: Task<Void, Never>?
    private var isGuidanceTrackingActive = false

    override init() {
        storageDefaults = UserDefaults(suiteName: Self.appGroupIdentifier) ?? .standard
        debugSimulateSlowSave = storageDefaults.bool(forKey: Self.debugSlowSaveKey)

        // We capture the current authorization status immediately so the UI can render
        // the right state before the first delegate callback happens.
        authorizationStatus = locationManager.authorizationStatus

        // Restore any previously saved data so the app feels stateful across launches.
        quickSpot = SavedSpotStorage.load(forKey: Self.quickSpotStorageKey, defaults: storageDefaults)
        savedPlaces = SavedSpotStorage.loadArray(forKey: Self.savedPlacesStorageKey, defaults: storageDefaults)
        super.init()

        // The location manager sends updates back to this object via CLLocationManagerDelegate.
        locationManager.delegate = self

        configureStandardTracking()
    }

    var canSaveCurrentLocation: Bool {
        // The save actions should only work once we both:
        // 1. have permission, and
        // 2. actually have a GPS fix.
        resolvedCurrentLocation != nil && isAuthorized
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    var isWaitingForQuickSave: Bool {
        if case .quickSpot = pendingSaveRequest {
            return true
        }
        return false
    }

    var isWaitingForPlaceSave: Bool {
        if case .place = pendingSaveRequest {
            return true
        }
        return false
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

    var shouldShowLocationNotice: Bool {
        !isAuthorized || resolvedCurrentLocation == nil
    }

    var shouldShowPlacesLocationNotice: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    var locationNoticeTitle: String {
        switch authorizationStatus {
        case .notDetermined:
            return "Location Permission Needed"
        case .denied:
            return "Location Access Is Off"
        case .restricted:
            return "Location Is Restricted"
        case .authorizedAlways, .authorizedWhenInUse:
            return "Finding Your Location"
        @unknown default:
            return "Location Unavailable"
        }
    }

    var locationNoticeMessage: String {
        switch authorizationStatus {
        case .notDetermined:
            return "Allow location access so you can save this place and guide yourself back later."
        case .denied:
            return "Location access is currently set to Never for this app. Open Settings and switch it to While Using the App."
        case .restricted:
            return "This device is restricting location access, so PinPoint cannot save your current position right now."
        case .authorizedAlways, .authorizedWhenInUse:
            return "PinPoint is waiting for a GPS fix. This usually clears after a second or two outdoors."
        @unknown default:
            return "PinPoint cannot read your location yet."
        }
    }

    var locationNoticeButtonTitle: String {
        switch authorizationStatus {
        case .notDetermined:
            return "Allow Location"
        case .denied, .restricted:
            return "Open Settings"
        case .authorizedAlways, .authorizedWhenInUse:
            return "Refresh Location"
        @unknown default:
            return "Refresh Location"
        }
    }

    func distanceText(to spot: SavedSpot?) -> String? {
        guard let currentLocation, let spot else { return nil }

        // `distance(from:)` returns meters between the user's current position and the saved spot.
        let meters = currentLocation.distance(from: spot.location)
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .providedUnit
        formatter.unitStyle = .medium
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        numberFormatter.maximumFractionDigits = 2
        numberFormatter.minimumFractionDigits = 0
        formatter.numberFormatter = numberFormatter

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

    func guidanceDistanceText(to spot: SavedSpot?) -> String? {
        guard let currentLocation, let spot else { return nil }

        let meters = currentLocation.distance(from: spot.location)

        // Once the user is inside the phone's practical GPS fuzziness zone, a precise meter
        // readout starts to feel overconfident. Switching to a softer label makes the guidance
        // experience feel more trustworthy.
        let proximityThreshold = max(15.0, currentLocation.horizontalAccuracy)
        if meters <= proximityThreshold {
            return "You're Nearby"
        }

        return distanceText(to: spot)
    }

    func placesDistanceText(to spot: SavedSpot?) -> String? {
        guard let currentLocation, let spot else { return nil }

        let meters = currentLocation.distance(from: spot.location)
        let proximityThreshold = max(15.0, currentLocation.horizontalAccuracy)

        if meters <= proximityThreshold {
            return "Nearby"
        }

        return distanceText(to: spot)
    }

    func isWithinGuidanceProximityZone(for spot: SavedSpot?) -> Bool {
        guard let currentLocation, let spot else { return false }

        let meters = currentLocation.distance(from: spot.location)
        let proximityThreshold = max(15.0, currentLocation.horizontalAccuracy)
        return meters <= proximityThreshold
    }

    func directionHint(to spot: SavedSpot?) -> String? {
        guard let currentLocation, let spot else { return nil }

        // `bearing` is the compass direction from the current coordinate to the saved coordinate.
        // Example: if the saved place is due east, this returns roughly 90 degrees.
        let bearing = currentLocation.coordinate.bearing(to: spot.coordinate)

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

    func arrowRotation(to spot: SavedSpot?) -> Double {
        guard let currentLocation, let spot else { return 0 }

        // Same idea as `directionHint`, but this value is used directly by the UI arrow.
        // We compute the destination bearing, subtract the phone heading, then normalize
        // the result so it always falls between 0 and 360 degrees.
        let bearing = currentLocation.coordinate.bearing(to: spot.coordinate)
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
            // Real devices often already have a recent cached location available even before the
            // next delegate callback arrives. Copying it into published state makes the UI feel
            // much more responsive after launch / foregrounding.
            if currentLocation == nil, let cachedLocation = locationManager.location {
                currentLocation = cachedLocation
            }

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

        guard !isGuidanceTrackingActive else {
            // The guidance screen owns a more aggressive continuous tracking mode.
            // If it is active, we do not want background pages to downgrade it back to one-shot updates.
            return
        }

        // Pull in the most recent system-known coordinate right away if one exists.
        // This gives the save buttons something usable even if a fresh GPS callback has not
        // arrived yet after the app comes back on screen.
        if let cachedLocation = locationManager.location {
            currentLocation = cachedLocation
        }

        // `requestLocation()` asks for a one-time fresh location sample.
        // We also restart heading updates in case the compass was not active yet.
        locationManager.requestLocation()
        if CLLocationManager.headingAvailable() {
            locationManager.startUpdatingHeading()
        }
    }

    func beginGuidanceTracking() {
        guard isAuthorized else {
            requestWhenInUsePermission()
            return
        }

        isGuidanceTrackingActive = true

        // The guidance screen is the one place where responsiveness matters more than battery cost.
        // We temporarily switch to a finer-grained GPS stream so the distance and arrow keep up
        // as the user walks back toward the saved spot.
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.startUpdatingLocation()
        locationManager.requestLocation()

        if CLLocationManager.headingAvailable() {
            locationManager.startUpdatingHeading()
        }
    }

    func endGuidanceTracking() {
        guard isGuidanceTrackingActive else { return }

        isGuidanceTrackingActive = false
        configureStandardTracking()

        // Shut down the continuous guidance streams once the screen goes away so the rest
        // of the app returns to the lighter-weight "refresh on demand" behavior.
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()

        // Grab one final cached location so other screens still have something recent to show
        // without immediately re-entering continuous tracking.
        if let cachedLocation = locationManager.location {
            currentLocation = cachedLocation
        }
    }

    func saveQuickSpot() {
        performSaveRequest(.quickSpot)
    }

    func clearQuickSpot() {
        quickSpot = nil
        SavedSpotStorage.clear(forKey: Self.quickSpotStorageKey, defaults: storageDefaults)
        statusMessage = "Quick spot cleared."
        reloadWidgetTimelines()
    }

    func saveCurrentLocationToPlaces(named rawName: String, iconEmoji rawIconEmoji: String) {
        // The list-based flow is more flexible, so we accept a custom name.
        // If the user leaves it blank, we generate a simple timestamp-based fallback.
        let trimmedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedIconEmoji = rawIconEmoji.trimmingCharacters(in: .whitespacesAndNewlines)
        performSaveRequest(
            .place(
                name: trimmedName.isEmpty ? defaultPlaceName() : trimmedName,
                iconEmoji: trimmedIconEmoji.isEmpty ? "" : String(trimmedIconEmoji.prefix(1))
            )
        )
    }

    func deleteSavedPlace(_ spot: SavedSpot) {
        savedPlaces.removeAll { $0.id == spot.id }
        SavedSpotStorage.saveArray(savedPlaces, forKey: Self.savedPlacesStorageKey, defaults: storageDefaults)
        statusMessage = "Removed \(spot.name)."
    }

    func defaultPlaceName() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return "Saved Place \(formatter.string(from: .now))"
    }

    func openInMaps(for spot: SavedSpot) {
        // This creates a real Apple Maps destination from our saved coordinate.
        // The app can then hand off walking directions if the user wants a more
        // traditional navigation experience than the beacon-style UI.
        let item = MKMapItem(location: spot.location, address: nil)
        item.name = spot.name
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
        ])
    }

    func handleLocationNoticeAction() {
        switch authorizationStatus {
        case .notDetermined:
            requestWhenInUsePermission()
        case .denied, .restricted:
            openAppSettings()
        case .authorizedAlways, .authorizedWhenInUse:
            refreshLocation()
        @unknown default:
            refreshLocation()
        }
    }

    func handleIncomingURL(_ url: URL) {
        guard url.scheme == "pinpoint" else { return }

        let action = url.host ?? url.pathComponents.dropFirst().first ?? ""
        switch action {
        case "save-quick":
            selectedTab = .quickSave
            pendingLaunchAction = .saveQuickSpot
        case "guide-quick":
            selectedTab = .quickSave
            pendingLaunchAction = .guideQuickSpot
        default:
            return
        }

        processPendingLaunchAction()
    }

    func handleAppBecameActive() {
        requestWhenInUsePermission()
        refreshLocation()
        processPendingLaunchAction()
    }

    private func startUpdating() {
        // `startUpdatingLocation()` keeps the GPS stream alive so distance changes
        // update automatically as the user walks.
        if isGuidanceTrackingActive {
            beginGuidanceTracking()
        } else {
            refreshLocation()
        }
    }

    private func configureStandardTracking() {
        // "Nearest ten meters" is a reasonable tradeoff for the main app:
        // accurate enough to save a place, without keeping a high-power GPS stream active.
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters

        // Ignore tiny movement changes so we do not over-update the UI while the user is standing still.
        locationManager.distanceFilter = 5

        // Only report heading changes once the phone turns at least 5 degrees.
        locationManager.headingFilter = 5
    }

    private func processPendingLaunchAction() {
        guard let pendingLaunchAction else { return }

        switch pendingLaunchAction {
        case .saveQuickSpot:
            guard isAuthorized else {
                requestWhenInUsePermission()
                statusMessage = "Allow location access so PinPoint can save your quick spot."
                return
            }

            guard let location = resolvedCurrentLocation else {
                refreshLocation()
                statusMessage = "Opening PinPoint and looking for your current location."
                return
            }

            if currentLocation == nil {
                currentLocation = location
            }

            saveQuickSpot()
            self.pendingLaunchAction = nil

        case .guideQuickSpot:
            guard let quickSpot else {
                statusMessage = "Save a quick spot first so PinPoint has somewhere to guide you."
                self.pendingLaunchAction = nil
                return
            }

            activeGuidanceSpot = quickSpot
            self.pendingLaunchAction = nil
        }
    }

    private var resolvedCurrentLocation: CLLocation? {
        currentLocation ?? locationManager.location
    }

    private func performSaveRequest(_ request: SaveRequest) {
        guard isAuthorized else {
            requestWhenInUsePermission()
            statusMessage = "Allow location access so PinPoint can save this place."
            return
        }

        // If the latest reading is still very fresh, save immediately. Otherwise, wait for the
        // next Core Location callback so the saved coordinate is closer to the moment of the tap.
        if !debugSimulateSlowSave, let location = resolvedCurrentLocation, isFreshEnoughForImmediateSave(location) {
            commitSaveRequest(request, with: location)
            return
        }

        pendingSaveRequest = request
        pendingSaveReadyAfter = debugSimulateSlowSave ? Date().addingTimeInterval(2.5) : nil
        pendingSaveDescription = savePendingDescription(for: request)
        pendingSaveDelayTask?.cancel()

        if debugSimulateSlowSave {
            pendingSaveDelayTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(2.5))
                guard let pendingSaveRequest else { return }
                if let location = resolvedCurrentLocation {
                    commitSaveRequest(pendingSaveRequest, with: location)
                    self.pendingSaveRequest = nil
                } else {
                    refreshLocation()
                }
            }
        }

        locationManager.requestLocation()
        if CLLocationManager.headingAvailable() {
            locationManager.startUpdatingHeading()
        }
        statusMessage = pendingSaveDescription
    }

    private func commitSaveRequest(_ request: SaveRequest, with location: CLLocation) {
        if currentLocation == nil {
            currentLocation = location
        }

        pendingSaveDelayTask?.cancel()
        pendingSaveDelayTask = nil
        pendingSaveReadyAfter = nil

        switch request {
        case .quickSpot:
            // The quick-save flow intentionally uses a fixed default name so the user can
            // save with one tap and move on. No extra prompts, no extra friction.
            let spot = SavedSpot(
                name: "Saved Spot",
                iconEmoji: nil,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                timestamp: .now
            )
            quickSpot = spot
            SavedSpotStorage.save(spot, forKey: Self.quickSpotStorageKey, defaults: storageDefaults)
            statusMessage = "Saved your quick spot."
            reloadWidgetTimelines()

        case let .place(name, iconEmoji):
            let spot = SavedSpot(
                name: name,
                iconEmoji: iconEmoji.isEmpty ? nil : iconEmoji,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                timestamp: .now
            )
            savedPlaces.insert(spot, at: 0)
            SavedSpotStorage.saveArray(savedPlaces, forKey: Self.savedPlacesStorageKey, defaults: storageDefaults)
            statusMessage = "Saved \(spot.name)."
        }

        pendingSaveDescription = nil
        successfulSaveCount += 1
    }

    private func isFreshEnoughForImmediateSave(_ location: CLLocation) -> Bool {
        // "Exact at the moment of tap" is not something GPS can guarantee, but we can at least
        // insist on a location sample that is both recent and reasonably accurate before saving
        // immediately. If not, we wait for the next callback after the button press.
        let age = Date().timeIntervalSince(location.timestamp)
        return age <= 2 && location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= 35
    }

    private func savePendingDescription(for request: SaveRequest) -> String {
        switch request {
        case .quickSpot:
            return "Refreshing your location before saving your quick spot."
        case let .place(name, _):
            return "Refreshing your location before saving \(name)."
        }
    }

    private func openAppSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        guard UIApplication.shared.canOpenURL(settingsURL) else { return }
        UIApplication.shared.open(settingsURL)
    }

    private func reloadWidgetTimelines() {
#if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
#endif
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
                if isGuidanceTrackingActive {
                    beginGuidanceTracking()
                } else {
                    refreshLocation()
                }
            } else if manager.authorizationStatus == .denied {
                statusMessage = "Location access is denied. Enable it in Settings to use PinPoint."
            }

            processPendingLaunchAction()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Apple can provide multiple candidate locations in one callback.
        // The last item is usually the freshest reading, so we use that.
        guard let location = locations.last else { return }

        Task { @MainActor in
            currentLocation = location
            let completedPendingSave = pendingSaveRequest != nil

            if let pendingSaveRequest {
                // If a save was waiting on a fresher sample, this callback is exactly what we wanted.
                // Use the newest location delivered after the tap rather than an older cached reading.
                let isReadyToCommit = pendingSaveReadyAfter.map { Date() >= $0 } ?? true

                if isReadyToCommit {
                    commitSaveRequest(pendingSaveRequest, with: location)
                    self.pendingSaveRequest = nil
                }
            }

            if !completedPendingSave {
                if quickSpot != nil || !savedPlaces.isEmpty {
                    statusMessage = "Tracking your distance to saved locations."
                } else {
                    statusMessage = "Current location updated."
                }
            }

            processPendingLaunchAction()
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
            pendingSaveDelayTask?.cancel()
            pendingSaveDelayTask = nil
            pendingSaveRequest = nil
            pendingSaveReadyAfter = nil
            pendingSaveDescription = nil
            statusMessage = "Could not update your location: \(error.localizedDescription)"
        }
    }
}

private enum SavedSpotStorage {
    static func load(forKey key: String, defaults: UserDefaults = .standard) -> SavedSpot? {
        // Decode the saved JSON blob from UserDefaults back into our Swift model.
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SavedSpot.self, from: data)
    }

    static func save(_ spot: SavedSpot, forKey key: String, defaults: UserDefaults = .standard) {
        // Encode the model as JSON because CLLocationCoordinate2D itself is not directly stored in UserDefaults.
        guard let data = try? JSONEncoder().encode(spot) else { return }
        defaults.set(data, forKey: key)
    }

    static func loadArray(forKey key: String, defaults: UserDefaults = .standard) -> [SavedSpot] {
        guard let data = defaults.data(forKey: key),
              let spots = try? JSONDecoder().decode([SavedSpot].self, from: data) else {
            return []
        }
        return spots
    }

    static func saveArray(_ spots: [SavedSpot], forKey key: String, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(spots) else { return }
        defaults.set(data, forKey: key)
    }

    static func clear(forKey key: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}

struct SavedSpot: Codable, Equatable, Hashable, Identifiable {
    let id: UUID
    let name: String
    let iconEmoji: String?
    let latitude: Double
    let longitude: Double
    let timestamp: Date

    init(id: UUID = UUID(), name: String, iconEmoji: String?, latitude: Double, longitude: Double, timestamp: Date) {
        self.id = id
        self.name = name
        self.iconEmoji = iconEmoji
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
    }

    var coordinate: CLLocationCoordinate2D {
        // Convenient bridge for MapKit and compass math.
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        // Convenient bridge for distance calculations and MKMapItem creation.
        CLLocation(latitude: latitude, longitude: longitude)
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
    let iconEmoji: String?
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

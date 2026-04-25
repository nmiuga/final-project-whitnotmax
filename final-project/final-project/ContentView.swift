//
//  ContentView.swift
//  final-project
//
//  Created by Whitman Stewart on 4/13/26.
//

import SwiftUI
import MapKit
import CoreLocation
import UIKit

struct ContentView: View {
    @EnvironmentObject private var locationStore: LocationStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $locationStore.selectedTab) {
            QuickSaveView()
                .tag(LocationStore.AppTab.quickSave)
                .tabItem {
                    Label("Quick Save", systemImage: "mappin.circle.fill")
                }

            SavedPlacesView()
                .tag(LocationStore.AppTab.places)
                .tabItem {
                    Label("Places", systemImage: "list.bullet.rectangle")
                }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                // When the app returns to the foreground on a real phone, ask Core Location
                // for a fresh reading again so the save buttons are ready right away.
                locationStore.handleAppBecameActive()
            }
        }
    }
}

struct QuickSaveView: View {
    @EnvironmentObject private var locationStore: LocationStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var isEmptyStateDismissed = false

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

        if let quickSpot = locationStore.quickSpot {
            items.append(
                MapPinItem(
                    title: quickSpot.name,
                    subtitle: quickSpot.relativeTimestamp,
                    coordinate: quickSpot.coordinate,
                    tint: .orange,
                    iconEmoji: quickSpot.iconEmoji
                )
            )
        }

        return items
    }

    private var activeGuidanceSpotBinding: Binding<SavedSpot?> {
        Binding(
            get: { locationStore.activeGuidanceSpot },
            set: { locationStore.activeGuidanceSpot = $0 }
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if shouldShowEmptyStateCard {
                        dismissibleEmptyStateCard
                            .transition(
                                .asymmetric(
                                    insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .move(edge: .top).combined(with: .opacity)
                                )
                            )
                    }

                    if locationStore.shouldShowLocationNotice {
                        LocationNoticeCard()
                    }

                    mapCard
                    primaryActionCard
                    if let quickSpot = locationStore.quickSpot {
                        NavigationLink(destination: DirectionView(spot: quickSpot)) {
                            Label("Guide Me", systemImage: "scope")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.accentColor)
                    }
                }
                .padding(20)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: shouldShowEmptyStateCard)
            }
            .background(screenBackground.ignoresSafeArea())
            .navigationTitle("PinPoint")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                locationStore.requestWhenInUsePermission()
                locationStore.refreshLocation()
                syncRegion()
                if locationStore.quickSpot != nil {
                    isEmptyStateDismissed = true
                }
            }
            .onChange(of: locationStore.currentLocation) {
                syncRegion()
            }
            .onChange(of: locationStore.quickSpot) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    if locationStore.quickSpot != nil {
                        isEmptyStateDismissed = true
                    } else {
                        isEmptyStateDismissed = false
                    }
                }
                syncRegion()
            }
            .navigationDestination(item: activeGuidanceSpotBinding) { spot in
                DirectionView(spot: spot)
            }
        }
    }

    private var shouldShowEmptyStateCard: Bool {
        locationStore.quickSpot == nil && !isEmptyStateDismissed
    }

    private var screenBackground: some View {
        LinearGradient(
            colors: colorScheme == .dark
            ? [
                Color(red: 0.10, green: 0.12, blue: 0.16),
                Color(red: 0.07, green: 0.09, blue: 0.13)
            ]
            : [
                Color(red: 0.95, green: 0.97, blue: 0.99),
                Color(red: 0.88, green: 0.92, blue: 0.97)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var cardFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.78)
    }

    private var subtleControlFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.06)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save your spot in one tap, then come back and let the app guide you back.")
                .font(.headline)
                .foregroundStyle(.primary)

            HStack(spacing: 12) {
                Label(locationStore.authorizationLabel, systemImage: locationStore.authorizationIcon)
                Spacer()
                if let distance = locationStore.distanceText(to: locationStore.quickSpot) {
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
        Map(position: $position, interactionModes: []) {
            ForEach(annotations) { item in
                // Each `Annotation` drops a custom SwiftUI view onto the map at a coordinate.
                // We use the same annotation type for both "you" and the saved parking spot,
                // and visually distinguish them with different SF Symbols and tint colors.
                Annotation(item.title, coordinate: item.coordinate) {
                    VStack(spacing: 6) {
                        if let iconEmoji = item.iconEmoji {
                            Text(iconEmoji)
                                .font(.title3)
                                .frame(width: 40, height: 40)
                                .background(item.tint.opacity(0.18), in: Circle())
                        } else {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.white)
                                .padding(10)
                                .background(item.tint, in: Circle())
                        }
                        
                    }
                }
            }
        }
        .frame(height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var primaryActionCard: some View {
        let canSave = locationStore.canSaveCurrentLocation

        return VStack(spacing: 14) {
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    isEmptyStateDismissed = true
                }
                locationStore.saveQuickSpot()
            } label: {
                Group {
                    if locationStore.isWaitingForQuickSave {
                        HStack(spacing: 10) {
                            ProgressView()
                                .tint(.white)
                            Text("Saving...")
                        }
                    } else {
                        Label(locationStore.quickSpot == nil ? "Save This Location" : "Update Quick Spot", systemImage: "mappin.circle.fill")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    canSave ? Color.accentColor : Color.gray.opacity(0.35),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
                .foregroundStyle(canSave ? .white : .secondary)
                .opacity(canSave ? 1 : 0.9)
            }
            .disabled(!canSave || locationStore.isWaitingForQuickSave)

            if locationStore.isWaitingForQuickSave, let pendingSaveDescription = locationStore.pendingSaveDescription {
                Text(pendingSaveDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 12) {
                
                Button(role: .destructive) {
                    locationStore.clearQuickSpot()
                } label: {
                    Label("Clear", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(locationStore.quickSpot == nil)
            }
        }
        .padding(20)
        .background(cardFillColor, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func quickSpotCard(_ spot: SavedSpot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quick Spot")
                .font(.title3.weight(.bold))

            HStack(spacing: 10) {
                SpotIconView(spot: spot, font: .headline)
                Text(spot.name)
                    .font(.headline)
            }

            Text(spot.formattedTimestamp)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let distance = locationStore.distanceText(to: spot) {
                Text("You are currently \(distance.lowercased()) away.")
                    .font(.subheadline.weight(.medium))
            }

            if let hint = locationStore.directionHint(to: spot) {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFillColor, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var dismissibleEmptyStateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text("No quick spot yet")
                    .font(.title3.weight(.bold))

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        isEmptyStateDismissed = true
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(subtleControlFill, in: Circle())
                }
                .buttonStyle(.plain)
            }

            Text("When you park, open the app and tap Save This Location. PinPoint will remember the exact spot so you can walk back later.")
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFillColor, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func syncRegion() {
        // This helper decides what the map should focus on.
        //
        // Priority:
        // 1. If a saved quick spot exists, center on that because it is the main destination.
        // 2. Otherwise, center on the user's current location once we have GPS data.
        if let quickSpot = locationStore.quickSpot {
            position = .region(
                MKCoordinateRegion(
                    center: quickSpot.coordinate,
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

struct SavedPlacesView: View {
    @EnvironmentObject private var locationStore: LocationStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var isPresentingAddSheet = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Use this tab for saved trailheads, meet-up points, parking decks, or any location you want to come back to later.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Button {
                            isPresentingAddSheet = true
                        } label: {
                            Label("Save Current Location", systemImage: "mappin.circle.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    locationStore.canSaveCurrentLocation ? Color.accentColor : Color.gray.opacity(0.35),
                                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                                )
                                .foregroundStyle(locationStore.canSaveCurrentLocation ? .white : .secondary)
                                .opacity(locationStore.canSaveCurrentLocation ? 1 : 0.9)
                        }
                        .disabled(!locationStore.canSaveCurrentLocation)
                    }
                    .padding(.vertical, 4)
                }
                
                if locationStore.shouldShowPlacesLocationNotice {
                    Section {
                        LocationNoticeCard()
                            .listRowInsets(EdgeInsets())
                    }
                    .padding(0)
                    
                }

               
                if locationStore.savedPlaces.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No Saved Places",
                            systemImage: "map",
                            description: Text("Save a few locations here so the app stays flexible without cluttering the quick-save experience.")
                        )
                        .padding(.vertical, 24)
                    }
                } else {
                    Section("Saved Places") {
                        ForEach(locationStore.savedPlaces) { spot in
                            NavigationLink(destination: DirectionView(spot: spot)) {
                                SavedPlaceRow(spot: spot)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    locationStore.deleteSavedPlace(spot)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    locationStore.openInMaps(for: spot)
                                } label: {
                                    Label("Maps", systemImage: "map")
                                }
                                .tint(.orange)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Places")
            .scrollContentBackground(.hidden)
            .background(
                LinearGradient(
                    colors: colorScheme == .dark
                    ? [
                        Color(red: 0.10, green: 0.12, blue: 0.16),
                        Color(red: 0.07, green: 0.09, blue: 0.13)
                    ]
                    : [
                        Color(red: 0.95, green: 0.97, blue: 0.99),
                        Color(red: 0.88, green: 0.92, blue: 0.97)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .onAppear {
                locationStore.requestWhenInUsePermission()
                locationStore.refreshLocation()
            }
            .sheet(isPresented: $isPresentingAddSheet) {
                AddPlaceSheet()
                    .presentationDetents([.medium])
            }
        }
    }
}

struct SavedPlaceRow: View {
    @EnvironmentObject private var locationStore: LocationStore
    let spot: SavedSpot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 10) {
                    SpotIconView(spot: spot, font: .headline)
                    Text(spot.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
                Spacer()
                if let distance = locationStore.placesDistanceText(to: spot) {
                    Text(distance)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Text(spot.formattedTimestamp)
                .font(.subheadline)
                .foregroundStyle(.secondary)

        }
        .padding(.vertical, 4)
    }
}

struct LocationNoticeCard: View {
    @EnvironmentObject private var locationStore: LocationStore
    @Environment(\.colorScheme) private var colorScheme

    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(locationStore.locationNoticeTitle, systemImage: locationStore.authorizationIcon)
                .font(compact ? .headline : .title3.weight(.bold))
                .foregroundStyle(.primary)

            Text(locationStore.locationNoticeMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let statusMessage = locationStore.statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button(locationStore.locationNoticeButtonTitle) {
                locationStore.handleLocationNoticeAction()
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accentColor)
        }
        .padding(compact ? 16 : 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (colorScheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(compact ? 0.9 : 0.82)),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }
}

struct AddPlaceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var locationStore: LocationStore
    @State private var placeName = ""
    @State private var placeEmoji = ""
    @State private var shouldFocusNameField = false
    @State private var shouldFocusEmojiField = false
    @State private var shouldDismissEmojiField = false
    @State private var saveCountWhenOpened = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("Place Name") {
                    SelectAllTextField(
                        text: $placeName,
                        shouldFocus: $shouldFocusNameField,
                        placeholder: "Trailhead, Garage B, Campsite..."
                    )
                }

                Section("Icon") {
                    EmojiKeyboardTextField(
                        text: $placeEmoji,
                        shouldFocus: $shouldFocusEmojiField,
                        shouldDismiss: $shouldDismissEmojiField,
                        placeholder: "Optional emoji"
                    )

                    EmojiPaletteView(selection: $placeEmoji) {
                        shouldFocusNameField = false
                        shouldFocusEmojiField = true
                    } onDefaultTap: {
                        shouldFocusNameField = false
                        shouldFocusEmojiField = false
                        shouldDismissEmojiField = true
                    }

                    Text("Leave this empty to use the default pin icon. Tap Custom to jump to the emoji keyboard.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Text("This saves your current GPS location into the Places tab so you can guide yourself back to it later.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if locationStore.isWaitingForPlaceSave {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text(locationStore.pendingSaveDescription ?? "Refreshing your location before saving.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Save Place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(locationStore.isWaitingForPlaceSave)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        locationStore.saveCurrentLocationToPlaces(named: placeName, iconEmoji: placeEmoji)
                    }
                    .disabled(!locationStore.canSaveCurrentLocation || locationStore.isWaitingForPlaceSave)
                }
            }
            .onAppear {
                if placeName.isEmpty {
                    placeName = locationStore.defaultPlaceName()
                }
                saveCountWhenOpened = locationStore.successfulSaveCount
                shouldFocusNameField = true
            }
            .onChange(of: locationStore.successfulSaveCount) {
                guard locationStore.successfulSaveCount > saveCountWhenOpened else { return }
                dismiss()
            }
        }
    }
}

struct SpotIconView: View {
    let spot: SavedSpot
    let font: Font

    var body: some View {
        if let iconEmoji = spot.iconEmoji {
            Text(iconEmoji)
                .font(font)
        } else {
            Image(systemName: "mappin.circle.fill")
                .font(font)
                .foregroundStyle(Color.accentColor)
        }
    }
}

struct EmojiPaletteView: View {
    @Binding var selection: String
    let onCustomTap: () -> Void
    let onDefaultTap: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private let emojis = ["📍", "🚗", "🏠", "🏕️", "🌲", "☕️", "🏫", "🛒", "🎯", "❤️", "⭐️", "🎵"]

    private var tileFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.06)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Button {
                    onCustomTap()
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "face.smiling")
                            .font(.body)
                        Text("Custom")
                            .font(.caption2)
                    }
                    .frame(width: 58, height: 40)
                    .background(tileFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    selection = ""
                    onDefaultTap()
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.body)
                        Text("Default")
                            .font(.caption2)
                    }
                    .frame(width: 58, height: 40)
                    .background(tileFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

                ForEach(emojis, id: \.self) { emoji in
                    Button {
                        selection = emoji
                    } label: {
                        Text(emoji)
                            .font(.title3)
                            .frame(width: 40, height: 40)
                            .background(tileFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

struct SelectAllTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var shouldFocus: Bool
    let placeholder: String

    func makeUIView(context: Context) -> UITextField {
        let textField = SelectAllOnAttachTextField()
        textField.borderStyle = .roundedRect
        textField.delegate = context.coordinator
        textField.placeholder = placeholder
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }

        if let autoFocusTextField = uiView as? SelectAllOnAttachTextField {
            autoFocusTextField.shouldAutoFocusOnAttach = shouldFocus
        }

        if shouldFocus && uiView.isFirstResponder {
            shouldFocus = false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        @objc func textChanged(_ textField: UITextField) {
            text = textField.text ?? ""
        }
    }
}

final class SelectAllOnAttachTextField: UITextField {
    var shouldAutoFocusOnAttach = false
    private var hasAutoFocusedOnAttach = false

    override func didMoveToWindow() {
        super.didMoveToWindow()

        guard window != nil, shouldAutoFocusOnAttach, !hasAutoFocusedOnAttach else { return }
        hasAutoFocusedOnAttach = true

        // Request focus only once, right when the field has actually been attached to the
        // presented sheet. This is much more reliable than racing SwiftUI update timing.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil else { return }
            self.becomeFirstResponder()
            self.selectedTextRange = self.textRange(from: self.beginningOfDocument, to: self.endOfDocument)
        }
    }
}

struct EmojiKeyboardTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var shouldFocus: Bool
    @Binding var shouldDismiss: Bool
    let placeholder: String

    func makeUIView(context: Context) -> UITextField {
        let textField = EmojiCapableTextField()
        textField.borderStyle = .roundedRect
        textField.placeholder = placeholder
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.delegate = context.coordinator
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }

        // When the user taps the "Custom" tile, we explicitly promote the emoji field
        // to first responder so the keyboard comes up right away inside the sheet.
        if shouldFocus && !uiView.isFirstResponder {
            DispatchQueue.main.async {
                uiView.becomeFirstResponder()
                shouldFocus = false
            }
        }

        if shouldDismiss && uiView.isFirstResponder {
            DispatchQueue.main.async {
                uiView.resignFirstResponder()
                shouldDismiss = false
            }
        } else if shouldDismiss {
            shouldDismiss = false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            // Allow normal deletion so the user can clear the icon field.
            if string.isEmpty {
                return true
            }

            // Accept only emoji input. If the user pastes or types multiple characters,
            // we keep just the first emoji-like character and replace whatever was there before.
            guard let emoji = string.firstEmojiCharacter else {
                return false
            }

            let emojiString = String(emoji)
            textField.text = emojiString
            text = emojiString
            return false
        }

        @objc func textChanged(_ textField: UITextField) {
            let sanitizedText = textField.text?.firstEmojiCharacter.map(String.init) ?? ""
            if textField.text != sanitizedText {
                textField.text = sanitizedText
            }
            text = sanitizedText
        }
    }
}

final class EmojiCapableTextField: UITextField {
    // iOS does not offer a public standalone emoji picker API, so the most native option
    // is to focus a text field that prefers the installed emoji keyboard/input mode.
    override var textInputMode: UITextInputMode? {
        for inputMode in UITextInputMode.activeInputModes where inputMode.primaryLanguage == "emoji" {
            return inputMode
        }
        return super.textInputMode
    }
}

private extension String {
    var firstEmojiCharacter: Character? {
        first(where: \.isEmojiLike)
    }
}

private extension Character {
    var isEmojiLike: Bool {
        unicodeScalars.contains { $0.properties.isEmoji }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(LocationStore())
    }
}

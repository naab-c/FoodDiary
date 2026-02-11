//
//  ContentView.swift
//  FoodDiary
//
//  Created by NaabC on 11/11/25.
//

import SwiftUI
import SwiftData
import MapKit

// MARK: - App background (gradient + optional background image)
private let appGradient = LinearGradient(
    colors: [
        Color(red: 1.0, green: 0.98, blue: 0.88),
        Color(red: 1.0, green: 0.95, blue: 0.82),
        Color(red: 1.0, green: 0.92, blue: 0.78)
    ],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

/// Background with optional image (brick, flowers, etc.). Add your image to Assets → AppBackground.
private struct AppBackgroundView: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                appGradient
                Image("AppBackground")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .opacity(0.45)
            }
        }
        .ignoresSafeArea(.all)
    }
}

struct ContentView: View {
    @EnvironmentObject private var geofenceService: VisitGeofenceService
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeTab()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)

            MyVisitsTab()
                .tabItem {
                    Label("My Visits", systemImage: "list.bullet")
                }
                .tag(1)
        }
        .background(AppBackgroundView().ignoresSafeArea(.all))
        .onChange(of: geofenceService.pendingPlaceIdToShow) { _, newValue in
            if newValue != nil {
                selectedTab = 0
            }
        }
    }
}

// MARK: - Home Tab
private struct HomeTab: View {
    @Environment(\.modelContext) private var ctx
    @EnvironmentObject private var geofenceService: VisitGeofenceService
    @Query(sort: \VisitEntry.name) private var visits: [VisitEntry]

    @State private var locationSvc = LocationService()
    @State private var status = "Tap 'Find nearby places' to get started."
    @State private var currentItem: MKMapItem?
    @State private var existing: VisitEntry?
    @State private var notes: String = ""
    @State private var isNewlySaved: Bool = false

    // Picker state
    @State private var candidates: [MKMapItem] = []
    @State private var showPicker = false
    @State private var lastCoord: CLLocationCoordinate2D?

    // "You've been here" bubble when user is at a saved restaurant
    @State private var showNearbyBubble: VisitEntry?
    @State private var nearbyBubbleDismissed = false  // don't show again after dismiss until next "Find nearby"
    private let nearbyRadiusMeters: Double = 150

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if !status.isEmpty {
                    Text(status)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Button("Find nearby places") {
                    // Clear any existing form when starting new search
                    currentItem = nil
                    notes = ""
                    existing = nil
                    isNewlySaved = false
                    nearbyBubbleDismissed = false  // allow bubble to show again next time at a saved place

                    locationSvc.requestWhenInUse()
                    status = "Getting your location…"
                    locationSvc.getOneLocation { coord in
                        lastCoord = coord
                        status = "Searching nearby places…"
                        let startTime = Date()
                        searchNearbyPlaces(near: coord) { items in
                            let elapsed = Date().timeIntervalSince(startTime)
                            print("Search completed in \(String(format: "%.2f", elapsed)) seconds with \(items.count) results")
                            candidates = items
                            showPicker = true
                            status = items.isEmpty ? "No places found." : "Pick a place from the list."
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)

                if let v = existing {
                    KnownPlaceView(visit: v, isNewlySaved: isNewlySaved)
                        .padding(.horizontal)
                } else if let item = currentItem {
                    NewPlaceForm(
                        item: item,
                        notes: $notes,
                        onSave: {
                            let pid = makePlaceId(for: item)
                            let v = VisitEntry(
                                placeId: pid,
                                name: item.name ?? "Unknown place",
                                coordinate: item.location.coordinate,
                                notes: notes.isEmpty ? nil : notes
                            )
                            ctx.insert(v)
                            try? ctx.save()
                            geofenceService.updateMonitoredRegions()
                            existing = v
                            isNewlySaved = true
                            status = "Saved \(v.name) to My Visits."
                            currentItem = nil
                            notes = ""
                        },
                        onCancel: {
                            currentItem = nil
                            notes = ""
                            status = "Tap 'Find nearby places' to get started."
                        }
                    )
                    .padding(.horizontal)
                }

                Spacer()
            }
            .padding(.vertical)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppBackgroundView().ignoresSafeArea(.all))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("FoodDiary")
                        .font(.headline)
                }
            }
            .overlay {
                if let visit = showNearbyBubble {
                    NearbyVisitBubbleView(visit: visit) {
                        showNearbyBubble = nil
                        nearbyBubbleDismissed = true  // don't show again until they tap Find nearby
                    }
                }
            }
            .onAppear {
                // If we opened from an arrival notification tap, show that visit's details (don't set nearbyBubbleDismissed so in-app bubble can still show later)
                if let placeId = geofenceService.pendingPlaceIdToShow {
                    if let visit = visits.first(where: { $0.placeId == placeId }) {
                        showNearbyBubble = visit
                    }
                    geofenceService.pendingPlaceIdToShow = nil
                }

                // Clear everything when returning to Home tab
                if existing != nil {
                    existing = nil
                    isNewlySaved = false
                    status = "Tap 'Find nearby places' to get started."
                }
                else if currentItem != nil {
                    currentItem = nil
                    notes = ""
                    status = "Tap 'Find nearby places' to get started."
                }
                else if status.contains("Saved") || status.contains("to My Visits") {
                    status = "Tap 'Find nearby places' to get started."
                }

                // Check if user is at a saved restaurant and show "You've been here" bubble (only if not already dismissed)
                if !visits.isEmpty, existing == nil, currentItem == nil, !nearbyBubbleDismissed {
                    locationSvc.requestWhenInUse()
                    locationSvc.getOneLocation { coord in
                        let userLoc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                        var closest: (visit: VisitEntry, distance: Double)?
                        for visit in visits {
                            let placeLoc = CLLocation(latitude: visit.latitude, longitude: visit.longitude)
                            let d = userLoc.distance(from: placeLoc)
                            if d <= nearbyRadiusMeters, closest == nil || d < (closest?.distance ?? .infinity) {
                                closest = (visit, d)
                            }
                        }
                        if let match = closest {
                            showNearbyBubble = match.visit
                        }
                    }
                }
            }
            .sheet(isPresented: $showPicker) {
                PlacePickerSheet(
                    candidates: candidates,
                    origin: lastCoord,
                    onPick: { item in
                        showPicker = false
                        select(item)
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private func select(_ item: MKMapItem) {
        currentItem = item
        let pid = makePlaceId(for: item)
        let fetch = FetchDescriptor<VisitEntry>(predicate: #Predicate { $0.placeId == pid })
        let found = try? ctx.fetch(fetch).first
        existing = found
        isNewlySaved = false  // Reset flag when selecting a new place
        if found != nil {
            status = ""  // Clear status since details are shown below
            currentItem = nil
        } else {
            status = "New place: \(item.name ?? "Unknown place"). Add notes and save to My Visits."
            notes = ""
        }
    }
}

// MARK: - My Visits Tab
private struct MyVisitsTab: View {
    @Query(sort: \VisitEntry.name) private var visits: [VisitEntry]
    @Environment(\.modelContext) private var ctx
    @EnvironmentObject private var geofenceService: VisitGeofenceService
    @State private var searchText = ""

    private var filteredVisits: [VisitEntry] {
        if searchText.isEmpty {
            return visits
        }
        return visits.filter { visit in
            visit.name.localizedCaseInsensitiveContains(searchText) ||
            (visit.notes?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            if visits.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "list.bullet.clipboard")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)
                    Text("No visits yet")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Find nearby places from the Home tab and save them here.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppBackgroundView().ignoresSafeArea(.all))
            } else {
                List(filteredVisits, id: \.placeId) { visit in
                    EditableVisitRow(visit: visit)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                ctx.delete(visit)
                                try? ctx.save()
                                geofenceService.updateMonitoredRegions()
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                .scrollContentBackground(.hidden)
                .background(AppBackgroundView().ignoresSafeArea(.all))
                .navigationTitle("My Visits")
                .searchable(text: $searchText, prompt: "Search visits")
            }
        }
    }
}

private struct PlacePickerSheet: View {
    let candidates: [MKMapItem]
    let origin: CLLocationCoordinate2D?
    let onPick: (MKMapItem) -> Void

    @State private var query: String = ""
    private var filtered: [MKMapItem] {
        guard !query.isEmpty else { return candidates }
        return candidates.filter { ($0.name ?? "").localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    // rows
                    ForEach(Array(filtered.enumerated()), id: \.offset) { _, item in
                        Button { onPick(item) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name ?? "Unknown place").font(.headline)
                                if let d = distanceString(from: origin, to: item) {
                                    Text(d).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("\(filtered.count) results").textCase(nil)
                }
            }
            .listStyle(.plain)
            .scrollIndicators(.visible)
            .navigationTitle("Nearby places")
            .searchable(text: $query,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search by name")
        }
    }

    private func distanceString(from origin: CLLocationCoordinate2D?, to item: MKMapItem) -> String? {
        guard let origin else { return nil }
        let dest = item.location.coordinate
        let a = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        let b = CLLocation(latitude: dest.latitude, longitude: dest.longitude)
        let miles = a.distance(from: b) / 1609.34
        // Show miles only
        if miles >= 10 { return String(format: "%.0f mi away", round(miles)) }
        if miles >= 1  { return String(format: "%.1f mi away", miles) }
        // Under 1 mile—still miles (you asked miles-only)
        return String(format: "%.2f mi away", miles)
    }
}


private struct SheetHandle: View {
    var body: some View {
        VStack(spacing: 8) {
            Capsule().fill(.tertiary).frame(width: 36, height: 5).padding(.top, 8)
        }
    }
}

// MARK: - "You've been here" bubble (when user opens app at a saved restaurant)
private struct NearbyVisitBubbleView: View {
    let visit: VisitEntry
    let onDismiss: () -> Void

    private let bubbleAccent = Color(red: 0.95, green: 0.6, blue: 0.2)
    private let bubbleBg = Color(red: 1.0, green: 0.97, blue: 0.92)
    private let bubbleCornerRadius: CGFloat = 28

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "location.circle.fill")
                        .font(.title2)
                        .foregroundStyle(bubbleAccent)
                    Text("You've been here before")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(visit.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                if let notes = visit.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .padding(.top, 4)
                } else {
                    Text("No notes saved for this visit.")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .italic()
                        .padding(.top, 4)
                }
            }
            .padding(24)
            .frame(maxWidth: 320, alignment: .leading)
            .background(bubbleBg, in: RoundedRectangle(cornerRadius: bubbleCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: bubbleCornerRadius)
                    .stroke(bubbleAccent.opacity(0.6), lineWidth: 2)
            )
            .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 6)
        }
    }
}

// MARK: - Existing/new views

private struct KnownPlaceView: View {
    @Bindable var visit: VisitEntry
    let isNewlySaved: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isNewlySaved ? "Food Notes" : "Previously Visited")
                .font(.headline)
            Divider()
            Text("Name: \(visit.name)")
                .font(.body)
            if let n = visit.notes, !n.isEmpty {
                Text("Notes:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                Text(n)
                    .padding(.top, 2)
            } else {
                Text("No notes saved yet.")
                    .foregroundStyle(.secondary)
                    .italic()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct NewPlaceForm: View {
    let item: MKMapItem
    @Binding var notes: String
    var onSave: () -> Void
    var onCancel: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("New place").font(.headline)
            Text(item.name ?? "Unknown place")
            TextEditor(text: $notes)
                .frame(minHeight: 100)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
            HStack {
                Button("Save to My Visits", action: onSave)
                    .buttonStyle(.borderedProminent)
                if let onCancel = onCancel {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.bordered)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct EditableVisitRow: View {
    @Bindable var visit: VisitEntry
    @Environment(\.modelContext) private var ctx
    @State private var editingNotes: String = ""
    @State private var isEditing: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(visit.name)
                .font(.headline)

            if isEditing {
                TextEditor(text: $editingNotes)
                    .frame(minHeight: 60)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary, lineWidth: 1))

                HStack {
                    Button("Cancel") {
                        editingNotes = visit.notes ?? ""
                        isEditing = false
                    }
                    .buttonStyle(.bordered)

                    Button("Save") {
                        // Update the visit's notes directly
                        visit.notes = editingNotes.isEmpty ? nil : editingNotes
                        // SwiftData with @Bindable should auto-save, but we'll explicitly save to be sure
                        do {
                            try ctx.save()
                            isEditing = false
                        } catch {
                            print("Error saving notes: \(error.localizedDescription)")
                            // Even if save fails, exit edit mode
                            isEditing = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                if let notes = visit.notes, !notes.isEmpty {
                    Text(notes)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No notes")
                        .foregroundStyle(.tertiary)
                        .italic()
                }

                Button("Edit Notes") {
                    editingNotes = visit.notes ?? ""
                    isEditing = true
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.blue)

                #if targetEnvironment(simulator)
                Text("Simulator: set Location → Custom to \(String(format: "%.6f", visit.latitude)), \(String(format: "%.6f", visit.longitude))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                #endif
            }
        }
        .padding(.vertical, 4)
    }
}

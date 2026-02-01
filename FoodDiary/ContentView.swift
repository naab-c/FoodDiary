//
//  ContentView.swift
//  FoodDiary
//
//  Created by NaabC on 11/11/25.
//

import SwiftUI
import SwiftData
import MapKit

struct ContentView: View {
    var body: some View {
        TabView {
            HomeTab()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
            
            MyVisitsTab()
                .tabItem {
                    Label("My Visits", systemImage: "list.bullet")
                }
        }
    }
}

// MARK: - Home Tab
private struct HomeTab: View {
    @Environment(\.modelContext) private var ctx
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

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text(status)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button("Find nearby places") {
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
                    NewPlaceForm(item: item, notes: $notes) {
                        let pid = makePlaceId(for: item)
                        let v = VisitEntry(
                            placeId: pid,
                            name: item.name ?? "Unknown place",
                            coordinate: item.location.coordinate,
                            notes: notes.isEmpty ? nil : notes
                        )
                        ctx.insert(v)
                        try? ctx.save()
                        existing = v
                        isNewlySaved = true
                        status = "Saved \(v.name) to My Visits."
                        currentItem = nil
                        notes = ""
                    }
                    .padding(.horizontal)
                }

                Spacer()
            }
            .padding(.vertical)
            .navigationTitle("Home")
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
        if let found {
            status = "You've visited this place before: \(found.name)"
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
            } else {
                List(visits, id: \.placeId) { visit in
                    EditableVisitRow(visit: visit)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                ctx.delete(visit)
                                try? ctx.save()
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                .navigationTitle("My Visits")
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("New place").font(.headline)
            Text(item.name ?? "Unknown place")
            TextEditor(text: $notes)
                .frame(minHeight: 100)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
            Button("Save to My Visits", action: onSave)
                .buttonStyle(.borderedProminent)
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
            }
        }
        .padding(.vertical, 4)
    }
}

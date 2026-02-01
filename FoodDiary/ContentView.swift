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
    @Environment(\.modelContext) private var ctx
    @Query(sort: \VisitEntry.name) private var visits: [VisitEntry]

    @State private var locationSvc = LocationService()
    @State private var status = "Pick a place from the list."
    @State private var currentItem: MKMapItem?
    @State private var existing: VisitEntry?
    @State private var notes: String = ""

    // Picker state
    @State private var candidates: [MKMapItem] = []
    @State private var showPicker = false
    @State private var lastCoord: CLLocationCoordinate2D?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text(status).multilineTextAlignment(.center)

                Button("Find nearby places") {
                    locationSvc.requestWhenInUse()
                    status = "Getting your location…"
                    locationSvc.getOneLocation { coord in
                        lastCoord = coord
                        status = "Searching nearby places…"
                        searchNearbyPlaces(near: coord) { items in
                            candidates = items
                            showPicker = true
                            status = items.isEmpty ? "No places found." : "Pick a place from the list."
                        }
                    }
                }
                .buttonStyle(.borderedProminent)

                if let v = existing {
                    KnownPlaceView(visit: v)
                } else if let item = currentItem {
                    NewPlaceForm(item: item, notes: $notes) {
                        let pid = makePlaceId(for: item)
                        let v = VisitEntry(
                            placeId: pid,
                            name: item.name ?? "Unknown place",
                            coordinate: item.location.coordinate,     // iOS 26+: non-optional
                            notes: notes.isEmpty ? nil : notes
                        )
                        ctx.insert(v)
                        try? ctx.save()
                        existing = v
                        status = "Saved \(v.name)."
                    }
                }

                Divider().padding(.vertical, 8)

                if !visits.isEmpty {
                    Text("Saved visits").font(.headline)
                    List(visits, id: \.placeId) { v in
                        VStack(alignment: .leading) {
                            Text(v.name).bold()
                            if let n = v.notes { Text(n) }
                        }
                    }
                    .frame(height: 220)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("FoodDiary")
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
                .presentationDragIndicator(.visible)   // <-- use system grabber
            }
        }
    }

    private func select(_ item: MKMapItem) {
        currentItem = item
        let pid = makePlaceId(for: item)
        let fetch = FetchDescriptor<VisitEntry>(predicate: #Predicate { $0.placeId == pid })
        let found = try? ctx.fetch(fetch).first
        existing = found
        if let found {
            status = "You’ve visited this place before: \(found.name)"
        } else {
            status = "New place detected: \(item.name ?? "Unknown place"). Add details and Save."
            notes = ""
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
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Previously saved").font(.headline)
            Text("Name: \(visit.name)")
            if let n = visit.notes, !n.isEmpty {
                Text("Notes: \(n)")
            } else {
                Text("No notes saved yet.").foregroundStyle(.secondary)
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

//
//  FoodDiaryApp.swift
//  FoodDiary
//
//  Created by NaabC on 11/11/25.
//

import SwiftUI
import SwiftData

@main
struct FoodDiaryApp: App {
    @StateObject private var geofenceService = VisitGeofenceService()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            VisitEntry.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(geofenceService)
                .onAppear {
                    geofenceService.configure(container: sharedModelContainer)
                }
        }
        .modelContainer(sharedModelContainer)
    }
}

//
//  VisitGeofenceService.swift
//  FoodDiary
//
//  Arrival notifications when user is near a saved restaurant (requires Always location).
//  Created by NaabC on 11/11/25.
//

import Foundation
import Combine
import CoreLocation
import UserNotifications
import SwiftData

private let geofenceRadiusMeters: CLLocationDistance = 150
private let maxMonitoredRegions = 20  // iOS limit

final class VisitGeofenceService: NSObject, ObservableObject {
    private let locationManager = CLLocationManager()
    private var modelContainer: ModelContainer?
    private var isMonitoring = false

    /// When user taps an arrival notification, we set this so the app opens to Home and shows this visit's details.
    @Published var pendingPlaceIdToShow: String?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    /// Call at app launch. Requests notification permission and starts monitoring if location is Always.
    func configure(container: ModelContainer) {
        self.modelContainer = container
        UNUserNotificationCenter.current().delegate = self
        requestNotificationPermission()
        updateMonitoredRegions()
    }

    /// Call when visits are added or removed so we update monitored regions.
    func updateMonitoredRegions() {
        guard let container = modelContainer else { return }
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<VisitEntry>(sortBy: [SortDescriptor(\.name)])
        guard let visits = try? context.fetch(descriptor), !visits.isEmpty else {
            for region in locationManager.monitoredRegions { locationManager.stopMonitoring(for: region) }
            return
        }
        requestAlwaysLocationIfNeeded {
            self.startMonitoring(container: container)
        }
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func requestAlwaysLocationIfNeeded(then: @escaping () -> Void) {
        switch locationManager.authorizationStatus {
        case .authorizedAlways:
            then()
        case .authorizedWhenInUse:
            // Request upgrade to Always so we can notify when app is closed
            locationManager.requestAlwaysAuthorization()
            // Delegate will get locationManagerDidChangeAuthorization; we'll start monitoring there
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { then() }
        case .denied, .restricted, .notDetermined:
            then()  // Still try to set regions; they'll activate if they later grant Always
        @unknown default:
            then()
        }
    }

    private func startMonitoring(container: ModelContainer) {
        guard locationManager.authorizationStatus == .authorizedAlways ||
              locationManager.authorizationStatus == .authorizedWhenInUse else { return }

        let context = ModelContext(container)
        let descriptor = FetchDescriptor<VisitEntry>(sortBy: [SortDescriptor(\.name)])
        guard let visits = try? context.fetch(descriptor) else { return }

        // Stop existing regions
        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
        }

        let toMonitor = Array(visits.prefix(maxMonitoredRegions))
        for visit in toMonitor {
            let center = CLLocationCoordinate2D(latitude: visit.latitude, longitude: visit.longitude)
            let region = CLCircularRegion(center: center, radius: geofenceRadiusMeters, identifier: visit.placeId)
            region.notifyOnEntry = true
            region.notifyOnExit = false
            locationManager.startMonitoring(for: region)
        }
        isMonitoring = true
    }

    private func scheduleArrivalNotification(for visit: VisitEntry) {
        let content = UNMutableNotificationContent()
        content.title = "You've been here before"
        content.body = visit.name
        if let notes = visit.notes, !notes.isEmpty {
            let preview = String(notes.prefix(80))
            content.body += " — \(preview)\(notes.count > 80 ? "…" : "")"
        }
        content.sound = .default
        content.userInfo = ["placeId": visit.placeId]

        let request = UNNotificationRequest(
            identifier: "arrival-\(visit.placeId)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

extension VisitGeofenceService: UNUserNotificationCenterDelegate {
    /// Show the notification even when the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    /// When user taps the notification, open app and show that visit's details.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        guard let placeId = userInfo["placeId"] as? String else {
            completionHandler()
            return
        }
        DispatchQueue.main.async {
            self.pendingPlaceIdToShow = placeId
        }
        completionHandler()
    }
}

extension VisitGeofenceService: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse,
           let container = modelContainer {
            startMonitoring(container: container)
        }
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let circular = region as? CLCircularRegion,
              let container = modelContainer else { return }

        let placeId = circular.identifier
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<VisitEntry>(sortBy: [SortDescriptor(\.name)])
        guard let allVisits = try? context.fetch(descriptor),
              let visit = allVisits.first(where: { $0.placeId == placeId }) else { return }

        DispatchQueue.main.async {
            self.scheduleArrivalNotification(for: visit)
        }
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        print("Geofence monitoring failed: \(error.localizedDescription)")
    }
}

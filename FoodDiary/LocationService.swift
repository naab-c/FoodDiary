//
//  LocationService.swift
//  FoodDiary
//
//  Created by NaabC on 11/11/25.
//

import Foundation
import CoreLocation
import MapKit
import Contacts

final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var pendingHandler: ((CLLocationCoordinate2D) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    func requestWhenInUse() {
        // Request permission once; the delegate will be called when user responds
        manager.requestWhenInUseAuthorization()
    }

    func getOneLocation(_ handler: @escaping (CLLocationCoordinate2D) -> Void) {
        pendingHandler = handler
        manager.startUpdatingLocation()  // start only after permission is granted
    }

    // ✅ Called automatically when permission changes
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        case .denied, .restricted:
            print("Location permission denied.")
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coord = locations.last?.coordinate else { return }
        pendingHandler?(coord)
        pendingHandler = nil
        manager.stopUpdatingLocation()
    }
}

func searchNearbyPlaces(near coordinate: CLLocationCoordinate2D,
                        completion: @escaping ([MKMapItem]) -> Void) {
    // Distances in miles
    let milesToMeters = 1609.34
    var regionMiles: Double = 2.0        // start ~2 miles
    let maxRegionMiles: Double = 5.0     // widen to ~5 miles if sparse

    // Staged queries: tighten → widen
    let queryBatches: [[String]] = [
        ["restaurant", "cafe", "coffee", "food"],
        ["store", "grocery", "bakery"],
        ["hotel", "shopping", "mall"]
    ]

    // Accumulator lives in outer scope (no inout)
    var merged: [String: MKMapItem] = [:]

    func coord(_ item: MKMapItem) -> CLLocationCoordinate2D { item.location.coordinate }

    func distanceMiles(_ item: MKMapItem) -> Double {
        let a = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let c = coord(item)
        let b = CLLocation(latitude: c.latitude, longitude: c.longitude)
        return a.distance(from: b) / milesToMeters
    }

    func region(_ miles: Double) -> MKCoordinateRegion {
        let meters = miles * milesToMeters
        return MKCoordinateRegion(center: coordinate,
                                  latitudinalMeters: meters,
                                  longitudinalMeters: meters)
    }

    func key(for item: MKMapItem) -> String {
        let c = coord(item)
        return "\(item.name ?? "?")_\(String(format: "%.5f", c.latitude))_\(String(format: "%.5f", c.longitude))"
    }

    func finish() {
        var results = Array(merged.values)
        results.sort { distanceMiles($0) < distanceMiles($1) }

        // Prefer within 1, 2, 3.5, then 5 miles
        for miles in [1.0, 2.0, 3.5, 5.0] {
            let filtered = results.filter { distanceMiles($0) <= miles }
            if !filtered.isEmpty { completion(filtered); return }
        }

        if !results.isEmpty { completion(Array(results.prefix(50))); return }

        // Final fallback: your exact coordinate
        let loc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let pin = MKMapItem(location: loc, address: nil)
        pin.name = String(format: "Dropped Pin (%.5f, %.5f)", coordinate.latitude, coordinate.longitude)
        completion([pin])
    }

    func runBatch(_ batchIndex: Int) {
        guard batchIndex < queryBatches.count else { finish(); return }

        let labels = queryBatches[batchIndex]
        var i = 0

        func nextQuery() {
            guard i < labels.count else {
                // If still empty after this batch, widen once and try next batch
                if merged.isEmpty && regionMiles < maxRegionMiles {
                    regionMiles = maxRegionMiles
                }
                runBatch(batchIndex + 1)
                return
            }

            let req = MKLocalSearch.Request()
            req.naturalLanguageQuery = labels[i]
            req.region = region(regionMiles)
            let tag = labels[i]
            i += 1

            MKLocalSearch(request: req).start { response, error in
                let items = response?.mapItems ?? []
                print("DEBUG query '\(tag)' items:", items.count,
                      error == nil ? "" : "error: \(error!.localizedDescription)")
                for it in items { merged[key(for: it)] = it }
                nextQuery()
            }
        }

        nextQuery()
    }

    runBatch(0)
}

func findNearestPlace(near coordinate: CLLocationCoordinate2D,
                      completion: @escaping (MKMapItem?) -> Void) {

    let region = MKCoordinateRegion(center: coordinate,
                                    latitudinalMeters: 5000,
                                    longitudinalMeters: 5000)

    // helper to compute closest by straight-line distance
    func closest(from items: [MKMapItem]) -> MKMapItem? {
        guard !items.isEmpty else { return nil }

        let la: CLLocationDegrees = coordinate.latitude
        let lo: CLLocationDegrees = coordinate.longitude

        return items.min { a, b in
            // iOS 26: location is non-optional; older SDKs: fall back to placemark
            let ca: CLLocationCoordinate2D
            let cb: CLLocationCoordinate2D
            if #available(iOS 26.0, *) {
                ca = a.location.coordinate
                cb = b.location.coordinate
            } else {
                ca = a.location.coordinate
                cb = b.location.coordinate
            }
            let da = hypot(ca.latitude - la, ca.longitude - lo)
            let db = hypot(cb.latitude - la, cb.longitude - lo)
            return da < db
        }
    }

    func runSearch(_ req: MKLocalSearch.Request, next: @escaping () -> Void) {
        let r = req
        r.region = region
        MKLocalSearch(request: r).start { response, _ in
            if let items = response?.mapItems, let hit = closest(from: items) {
                completion(hit)
            } else {
                next()
            }
        }
    }

    // Build three robust attempts (no inout, no deprecated categories):
    let req1 = MKLocalSearch.Request()
    req1.resultTypes = .pointOfInterest

    let req2 = MKLocalSearch.Request()
    req2.naturalLanguageQuery = "restaurant"

    let req3 = MKLocalSearch.Request()
    req3.naturalLanguageQuery = "store"

    // Chain attempts; if all fail, synthesize a pin using modern/legacy path
    runSearch(req1) {
        runSearch(req2) {
            runSearch(req3) {
                if #available(iOS 26.0, *) {
                    let loc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                    let item = MKMapItem(location: loc, address: nil) // modern fallback
                    item.name = String(format: "Dropped Pin (%.5f, %.5f)", coordinate.latitude, coordinate.longitude)
                    completion(item)
                } else {
                    let placemark = MKPlacemark(coordinate: coordinate) // legacy fallback
                    let item = MKMapItem(placemark: placemark)
                    item.name = String(format: "Dropped Pin (%.5f, %.5f)", coordinate.latitude, coordinate.longitude)
                    completion(item)
                }
            }
        }
    }
}

func makePlaceId(for item: MKMapItem) -> String {
    let coord: CLLocationCoordinate2D =
        item.location.coordinate
    let rlat = (coord.latitude * 10_000).rounded() / 10_000
    let rlon = (coord.longitude * 10_000).rounded() / 10_000
    let baseName = (item.name?.isEmpty == false) ? item.name! : "Unknown"
    return "\(baseName)_\(rlat)_\(rlon)"
}

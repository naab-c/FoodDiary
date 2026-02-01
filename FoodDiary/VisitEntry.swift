//
//  VisitEntry.swift
//  FoodDiary
//
//  Created by NaabC on 11/11/25.
//

import SwiftData
import CoreLocation

@Model
final class VisitEntry {
    @Attribute(.unique) var placeId: String
    var name: String
    var latitude: Double
    var longitude: Double
    var notes: String?

    init(placeId: String, name: String, coordinate: CLLocationCoordinate2D, notes: String? = nil) {
        self.placeId = placeId
        self.name = name
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.notes = notes
    }
}

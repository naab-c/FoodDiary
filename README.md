# FoodDiary 📱

A native iOS app built with SwiftUI that helps you discover and track your favorite restaurants and food places. Find nearby locations, save your visits, and keep notes about your dining experiences.

## Features

### 🏠 Home Tab
- **Find Nearby Places**: Discover restaurants, cafes, coffee shops, stores, and more near your location
- **Smart Search**: Parallel queries across multiple categories (restaurants, cafes, food, stores, groceries, bakeries, hotels, shopping, malls)
- **Place Details**: View full visit history for places you've been to before
- **Quick Save**: Add notes and save new places to your visit list

### 📋 My Visits Tab
- **Visit History**: Browse all your saved food places in one organized list
- **Editable Notes**: Update your notes about each place directly in the list
- **Swipe to Delete**: Easily remove entries with native iOS swipe gestures
- **Empty State**: Friendly message when you haven't saved any visits yet


## Technologies

- **SwiftUI** - Modern declarative UI framework
- **SwiftData** - Database that stores your saved visit entries (replaces Core Data)
- **CoreLocation** - Location services for finding nearby places
- **MapKit** - Local search and place discovery
- **iOS 17+** - Built for modern iOS

## Project Structure

```
FoodDiary/
├── FoodDiary/
│   ├── ContentView.swift      # Main tab view and UI components
│   ├── LocationService.swift  # Location and place search logic
│   ├── VisitEntry.swift       # SwiftData model for visits
│   ├── FoodDiaryApp.swift     # App entry point
│   └── Info.plist             # App configuration
└── README.md
```

## Key Implementation Details

- **Parallel Search**: Optimized place search using `DispatchGroup` for concurrent queries
- **Early Termination**: Stops searching once enough results are found (30+ places)
- **SwiftData Integration**: Persistent storage with automatic model updates
- **Location Services**: Proper permission handling and location updates
- **Tab-Based Navigation**: Clean separation between discovery and history

## Future Enhancements

- [ ] Map view showing all visited places
- [ ] Filter and sort visits by date, distance, or name

## About

Personal project and portfolio piece.

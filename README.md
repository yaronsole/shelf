# Shelf

Personal iOS book recommendation app powered by Claude AI.

## Structure

| Folder | Description |
|---|---|
| [`ShelfV2/`](ShelfV2/) | iOS app (SwiftUI + SwiftData, iOS 17+) — v2 ground-up rewrite per PRD |
| [`backend/`](backend/) | FastAPI service deployed to Google Cloud Run |
| [`Shelf/`](Shelf/) | v1 iOS app (legacy, kept for reference) |

## Getting started

### iOS app
```bash
cd ShelfV2
xcodegen generate   # regenerate Shelf.xcodeproj from project.yml
open Shelf.xcodeproj
```
Build target: iPhone, iOS 17+. See [ShelfV2/Shelf/Config/APIConfig.swift](ShelfV2/Shelf/Config/APIConfig.swift) for the backend URL.

### Backend
See [backend/README.md](backend/README.md) for deploy instructions.

## Architecture

- **iOS**: SwiftUI + SwiftData, `@Observable` view models, async/await throughout
- **Backend**: FastAPI on Cloud Run, Firestore for persistence, Claude API for recommendation generation
- **Auth**: Anonymous UUID token stored in iOS Keychain, sent as Bearer token
- **Domain extensibility**: All API calls and data models tagged with a `domain` field (books today; recipes/restaurants future)

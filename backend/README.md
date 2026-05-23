# Shelf API – Backend

Python / FastAPI / Firestore / Claude API — deploys to Google Cloud Run.

## Files

| File | Purpose |
|---|---|
| `main.py` | All route handlers |
| `models.py` | Pydantic request/response models |
| `prompts.py` | Claude prompt builders |
| `requirements.txt` | Python dependencies |
| `Dockerfile` | Container definition |
| `deploy.sh` | One-command Cloud Run deploy |
| `run_local.sh` | Local dev server |

## Endpoints

| Method | Path | Description |
|---|---|---|
| POST | `/v1/seed-books` | Add a seed book |
| GET | `/v1/seed-books` | List seed books |
| DELETE | `/v1/seed-books/{id}` | Remove a seed book |
| POST | `/v1/reactions` | Save/dismiss/rate a book |
| POST | `/v1/seen-books` | Mark books as seen |
| GET | `/v1/recommendations` | Get recommendations (generates if cache empty) |
| POST | `/v1/onboarding/suggestions` | Chain discovery suggestions |
| GET | `/v1/debug/generation-info` | Last generation metadata |
| GET | `/healthz` | Health check |

## Auth

Every request must include:
```
Authorization: Bearer <anonymous-uuid-token>
```
The iOS app generates and stores this token in Keychain on first launch.

## Deploy

### 1. Prerequisites

```bash
# Install gcloud CLI if needed: https://cloud.google.com/sdk/docs/install
gcloud auth login
gcloud auth application-default login
```

### 2. Enable required GCP APIs (one-time)

```bash
gcloud services enable run.googleapis.com cloudbuild.googleapis.com \
  firestore.googleapis.com --project YOUR_PROJECT_ID
```

### 3. Create Firestore database (one-time)

In GCP Console → Firestore → Create database → Native mode → us-central1

### 4. Deploy

```bash
cd /Users/ysole/Desktop/ShelfApp/backend
export GCP_PROJECT=your-gcp-project-id
export ANTHROPIC_API_KEY=sk-ant-...
./deploy.sh
```

The script prints the Cloud Run URL at the end. Copy it.

### 5. Update the iOS app

Open `ShelfV2/Shelf/Config/APIConfig.swift` and replace:
```swift
?? "https://shelf-api.example.com"
```
with:
```swift
?? "https://YOUR-SERVICE-URL.run.app"
```

## Run locally

```bash
cd /Users/ysole/Desktop/ShelfApp/backend
pip install -r requirements.txt
export ANTHROPIC_API_KEY=sk-ant-...
./run_local.sh
# API available at http://localhost:8080
# Swagger UI at http://localhost:8080/docs
```
Firestore will use your Application Default Credentials — make sure you ran
`gcloud auth application-default login` first.

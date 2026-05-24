#!/usr/bin/env bash
# deploy.sh — builds and deploys the Shelf backend to Cloud Run
# Usage: ./deploy.sh
# Prerequisites: gcloud CLI authenticated, PROJECT_ID and ANTHROPIC_API_KEY set below.

set -euo pipefail

# ── Configure these ──────────────────────────────────────────────────────────
PROJECT_ID="${GCP_PROJECT:-}"          # or hardcode: PROJECT_ID="my-gcp-project"
REGION="${GCP_REGION:-us-central1}"
SERVICE_NAME="shelf-api"
ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}"
GOOGLE_BOOKS_API_KEY="${GOOGLE_BOOKS_API_KEY:-}"
CRON_SECRET="${CRON_SECRET:-}"
# ─────────────────────────────────────────────────────────────────────────────

if [[ -z "$PROJECT_ID" ]]; then
  echo "❌  Set GCP_PROJECT env var or hardcode PROJECT_ID in this script."
  exit 1
fi

if [[ -z "$ANTHROPIC_API_KEY" ]]; then
  echo "❌  Set ANTHROPIC_API_KEY env var."
  exit 1
fi

IMAGE="gcr.io/$PROJECT_ID/$SERVICE_NAME"

echo "▶ Building and pushing image: $IMAGE"
gcloud builds submit \
  --project "$PROJECT_ID" \
  --tag "$IMAGE" \
  .

echo "▶ Deploying to Cloud Run: $SERVICE_NAME ($REGION)"
gcloud run deploy "$SERVICE_NAME" \
  --project "$PROJECT_ID" \
  --image "$IMAGE" \
  --region "$REGION" \
  --platform managed \
  --allow-unauthenticated \
  --set-env-vars "ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY,GOOGLE_BOOKS_API_KEY=$GOOGLE_BOOKS_API_KEY,CRON_SECRET=$CRON_SECRET" \
  --memory 512Mi \
  --cpu 1 \
  --min-instances 0 \
  --max-instances 5 \
  --timeout 60

echo ""
echo "✅  Deployed. Service URL:"
gcloud run services describe "$SERVICE_NAME" \
  --project "$PROJECT_ID" \
  --region "$REGION" \
  --format "value(status.url)"

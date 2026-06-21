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
NYT_API_KEY="${NYT_API_KEY:-}"
COMMUNITY_SEED_TOKEN="${COMMUNITY_SEED_TOKEN:-}"   # device token whose taste seeds the "loved by readers" list
COMMUNITY_LIST_SIZE="${COMMUNITY_LIST_SIZE:-60}"
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

echo "▶ Resolving freshly-built image digest (avoids stale :latest resolution)"
IMAGE_DIGEST=$(gcloud container images describe "$IMAGE:latest" \
  --project "$PROJECT_ID" --format='value(image_summary.digest)')
echo "  digest: $IMAGE_DIGEST"

echo "▶ Deploying to Cloud Run: $SERVICE_NAME ($REGION)"
gcloud run deploy "$SERVICE_NAME" \
  --project "$PROJECT_ID" \
  --image "$IMAGE@$IMAGE_DIGEST" \
  --region "$REGION" \
  --platform managed \
  --allow-unauthenticated \
  --set-env-vars "ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY,GOOGLE_BOOKS_API_KEY=$GOOGLE_BOOKS_API_KEY,CRON_SECRET=$CRON_SECRET,NYT_API_KEY=$NYT_API_KEY,COMMUNITY_SEED_TOKEN=$COMMUNITY_SEED_TOKEN,COMMUNITY_LIST_SIZE=$COMMUNITY_LIST_SIZE" \
  --memory 512Mi \
  --cpu 1 \
  --min-instances 0 \
  --max-instances 5 \
  --timeout 60

# Defensive: if traffic was ever pinned to a specific revision (e.g. a past
# rollback via --to-revisions), `gcloud run deploy` creates a new revision but
# won't shift traffic to it. Force 100% to the latest so deploys always land.
echo "▶ Routing 100% traffic to the latest revision"
gcloud run services update-traffic "$SERVICE_NAME" \
  --project "$PROJECT_ID" --region "$REGION" --to-latest >/dev/null

SERVICE_URL=$(gcloud run services describe "$SERVICE_NAME" \
  --project "$PROJECT_ID" \
  --region "$REGION" \
  --format "value(status.url)")

echo ""
echo "✅  Deployed. Service URL: $SERVICE_URL"

# ── Post-deploy cover-cache warmup ───────────────────────────────────────────
# On first request to each list endpoint, the backend resolves covers via
# Open Library / Google Books (cached globally in Firestore). With ~40-60
# books per list, the first request can take 30-45s. Pre-warm so users on
# the next call see books in <2s.
echo ""
echo "▶ Pre-warming list cover caches (parallel)..."
CATALOG=$(curl -s --max-time 30 "$SERVICE_URL/v1/lists" || echo '{"lists":[]}')
SLUGS=$(echo "$CATALOG" | python3 -c "import json,sys; d=json.load(sys.stdin); print(' '.join(l['slug'] for l in d.get('lists',[])))")

if [[ -n "$SLUGS" ]]; then
  for slug in $SLUGS; do
    (
      RESULT=$(curl -s --max-time 120 -w "%{time_total}s" -o /dev/null \
        "$SERVICE_URL/v1/lists/$slug" \
        -H "Authorization: Bearer warmup-deploy")
      echo "   $slug: $RESULT"
    ) &
  done
  wait
  echo "✅  Cover caches warmed."
else
  echo "⚠️  No list slugs returned — skipping warmup."
fi

# ── Recompute the community "loved by readers" list ──────────────────────────
# Aggregates alreadyReadLiked reactions (+ the seed token's taste) into
# computed_lists/loved_by_readers, which the /v1/lists endpoints then serve.
if [[ -n "$CRON_SECRET" ]]; then
  echo ""
  echo "▶ Recomputing community list (loved_by_readers)..."
  curl -s --max-time 120 -X POST "$SERVICE_URL/v1/cron/recompute-community" \
    -H "X-Cloud-Scheduler-Auth: $CRON_SECRET"
  echo ""
fi

# To schedule daily recomputation (run once, after first deploy):
#   gcloud scheduler jobs create http shelf-community-recompute \
#     --project "$PROJECT_ID" --location "$REGION" \
#     --schedule "0 4 * * *" --time-zone "America/Los_Angeles" \
#     --uri "$SERVICE_URL/v1/cron/recompute-community" --http-method POST \
#     --headers "X-Cloud-Scheduler-Auth=$CRON_SECRET"

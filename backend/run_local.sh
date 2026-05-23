#!/usr/bin/env bash
# run_local.sh — starts the API locally for development
# Requires: pip install -r requirements.txt, ANTHROPIC_API_KEY set,
#           and gcloud Application Default Credentials (run: gcloud auth application-default login)

set -euo pipefail

export ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:?Set ANTHROPIC_API_KEY env var}"

uvicorn main:app --reload --port 8080

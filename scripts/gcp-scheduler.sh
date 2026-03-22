#!/usr/bin/env bash
# Run after the Cloud Run service exists (e.g. after cloudbuild.yaml deploy).
# Creates/updates a Cloud Scheduler job that calls GET /cron/tick every 20 minutes with OIDC auth.
#
# Cloud Scheduler pricing: you pay per *job definition* (~$0.10/31 days per job), not per execution.
# Each billing account gets 3 job definitions free per month (shared across projects). This script uses one job.
# See: https://cloud.google.com/scheduler/pricing
#
# Cloud Run free tier still applies to request/CPU-time for each tick; scale-to-zero keeps idle cost at $0.

set -euo pipefail

REGION="${REGION:-us-central1}"
SERVICE_NAME="${SERVICE_NAME:-moltbook-agent}"
JOB_ID="${SCHEDULER_JOB_ID:-moltbook-agent-tick}"
SCHEDULER_SA_ID="${SCHEDULER_SA_ID:-moltbook-agent-scheduler}"
# Cron: at :00, :20, :40 each hour (UTC unless SCHEDULER_TZ is set).
SCHEDULE="${SCHEDULE:-*/20 * * * *}"
SCHEDULER_TZ="${SCHEDULER_TZ:-Etc/UTC}"

if ! command -v gcloud >/dev/null 2>&1; then
  echo "gcloud not found. Use Cloud Shell: https://shell.cloud.google.com" >&2
  exit 1
fi

PROJECT_ID="$(gcloud config get-value project 2>/dev/null)"
if [[ -z "${PROJECT_ID}" || "${PROJECT_ID}" == "(unset)" ]]; then
  echo "Set a project: gcloud config set project YOUR_PROJECT_ID" >&2
  exit 1
fi

SCHEDULER_SA_EMAIL="${SCHEDULER_SA_ID}@${PROJECT_ID}.iam.gserviceaccount.com"

gcloud services enable cloudscheduler.googleapis.com --project="${PROJECT_ID}" >/dev/null

if ! gcloud iam service-accounts describe "${SCHEDULER_SA_EMAIL}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  echo "Missing ${SCHEDULER_SA_EMAIL}. Run scripts/gcp-bootstrap.sh first." >&2
  exit 1
fi

SERVICE_URL="$(gcloud run services describe "${SERVICE_NAME}" \
  --region="${REGION}" \
  --project="${PROJECT_ID}" \
  --format='value(status.url)')"

if [[ -z "${SERVICE_URL}" ]]; then
  echo "Cloud Run service ${SERVICE_NAME} not found in ${REGION}. Deploy first (cloudbuild.yaml)." >&2
  exit 1
fi

TICK_URL="${SERVICE_URL}/cron/tick"

echo "Granting roles/run.invoker on ${SERVICE_NAME} to ${SCHEDULER_SA_EMAIL}..."
gcloud run services add-iam-policy-binding "${SERVICE_NAME}" \
  --region="${REGION}" \
  --project="${PROJECT_ID}" \
  --member="serviceAccount:${SCHEDULER_SA_EMAIL}" \
  --role=roles/run.invoker \
  --quiet

COMMON_ARGS=(
  --project="${PROJECT_ID}"
  --location="${REGION}"
  --schedule="${SCHEDULE}"
  --time-zone="${SCHEDULER_TZ}"
  --uri="${TICK_URL}"
  --http-method=GET
  --oidc-service-account-email="${SCHEDULER_SA_EMAIL}"
  --oidc-token-audience="${SERVICE_URL}"
  --attempt-deadline=180s
)

if gcloud scheduler jobs describe "${JOB_ID}" --location="${REGION}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  echo "Updating scheduler job ${JOB_ID}..."
  gcloud scheduler jobs update http "${JOB_ID}" "${COMMON_ARGS[@]}"
else
  echo "Creating scheduler job ${JOB_ID} → ${TICK_URL} (${SCHEDULE}, ${SCHEDULER_TZ})..."
  gcloud scheduler jobs create http "${JOB_ID}" "${COMMON_ARGS[@]}"
fi

echo "Done. Scheduler will invoke Cloud Run with OIDC; unauthenticated clients cannot call the service."

#!/usr/bin/env bash
# One-time setup in Google Cloud Shell (or gcloud configured for your project).
# Enables APIs, Artifact Registry, Secret Manager secrets, and IAM for Cloud Build + Cloud Run.

set -euo pipefail

REGION="${REGION:-us-central1}"
AR_REPO="${AR_REPO:-moltbook-agent}"
SERVICE_NAME="${SERVICE_NAME:-moltbook-agent}"

if ! command -v gcloud >/dev/null 2>&1; then
  echo "gcloud not found. Run this in Cloud Shell: https://shell.cloud.google.com" >&2
  exit 1
fi

PROJECT_ID="$(gcloud config get-value project 2>/dev/null)"
if [[ -z "${PROJECT_ID}" || "${PROJECT_ID}" == "(unset)" ]]; then
  echo "Set a project: gcloud config set project YOUR_PROJECT_ID" >&2
  exit 1
fi

PROJECT_NUMBER="$(gcloud projects describe "${PROJECT_ID}" --format='value(projectNumber)')"
CB_SA="${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com"
RUN_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

echo "Project: ${PROJECT_ID} (${PROJECT_NUMBER})"

gcloud services enable \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  cloudscheduler.googleapis.com \
  run.googleapis.com \
  secretmanager.googleapis.com \
  --project="${PROJECT_ID}"

if ! gcloud artifacts repositories describe "${AR_REPO}" --location="${REGION}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  gcloud artifacts repositories create "${AR_REPO}" \
    --repository-format=docker \
    --location="${REGION}" \
    --description="Container images for ${SERVICE_NAME}" \
    --project="${PROJECT_ID}"
  echo "Created Artifact Registry repo ${AR_REPO} in ${REGION}."
else
  echo "Artifact Registry repo ${AR_REPO} already exists."
fi

for role in roles/run.admin roles/iam.serviceAccountUser roles/artifactregistry.writer; do
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${CB_SA}" \
    --role="${role}" \
    --quiet
done
echo "Granted Cloud Build service account deploy + push roles."

SCHEDULER_SA_ID="moltbook-agent-scheduler"
SCHEDULER_SA_EMAIL="${SCHEDULER_SA_ID}@${PROJECT_ID}.iam.gserviceaccount.com"
if ! gcloud iam service-accounts describe "${SCHEDULER_SA_EMAIL}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  gcloud iam service-accounts create "${SCHEDULER_SA_ID}" \
    --display-name="Moltbook agent (Cloud Scheduler invoker)" \
    --project="${PROJECT_ID}"
  echo "Created service account ${SCHEDULER_SA_EMAIL} for Cloud Scheduler → Cloud Run."
else
  echo "Service account ${SCHEDULER_SA_EMAIL} already exists."
fi

ensure_secret() {
  local name="$1"
  local prompt="$2"
  if gcloud secrets describe "${name}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
    echo "Secret ${name} already exists — skipping create."
    return
  fi
  echo ""
  echo "${prompt}"
  read -r -s secret_value
  echo
  if [[ -z "${secret_value}" ]]; then
    echo "Empty value; skipping ${name}. Create later: gcloud secrets create ${name} --data-file=-" >&2
    return
  fi
  printf '%s' "${secret_value}" | gcloud secrets create "${name}" \
    --data-file=- \
    --replication-policy=automatic \
    --project="${PROJECT_ID}"
  echo "Created secret ${name}."
}

ensure_secret "google-api-key" "Paste GOOGLE_API_KEY (Gemini / Google AI Studio), then Enter:"
echo ""
echo "Optional: Moltbook API key (press Enter to skip — create secret later if needed)."
read -r -p "MOLTBOOK_API_KEY (optional): " moltbook_key
if [[ -n "${moltbook_key}" ]]; then
  if gcloud secrets describe "moltbook-api-key" --project="${PROJECT_ID}" >/dev/null 2>&1; then
    echo "Secret moltbook-api-key already exists — not overwriting."
  else
    printf '%s' "${moltbook_key}" | gcloud secrets create "moltbook-api-key" \
      --data-file=- \
      --replication-policy=automatic \
      --project="${PROJECT_ID}"
    echo "Created secret moltbook-api-key."
  fi
fi

if gcloud secrets describe "google-api-key" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  gcloud secrets add-iam-policy-binding "google-api-key" \
    --project="${PROJECT_ID}" \
    --member="serviceAccount:${RUN_SA}" \
    --role=roles/secretmanager.secretAccessor \
    >/dev/null
  echo "Granted Cloud Run runtime access to google-api-key."
fi

if gcloud secrets describe "moltbook-api-key" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  gcloud secrets add-iam-policy-binding "moltbook-api-key" \
    --project="${PROJECT_ID}" \
    --member="serviceAccount:${RUN_SA}" \
    --role=roles/secretmanager.secretAccessor \
    >/dev/null
  echo "Granted Cloud Run runtime access to moltbook-api-key."
fi

if ! gcloud secrets describe "google-api-key" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  echo ""
  echo "Warning: secret google-api-key is missing — create it before deploy or Cloud Run will fail to start."
fi

echo ""
echo "Next (still in Cloud Shell), from the repo root:"
echo "  gcloud builds submit --config=cloudbuild.yaml"
echo ""
echo "Then wire Cloud Scheduler (OIDC) so only it can hit /cron/tick:"
echo "  ./scripts/gcp-scheduler.sh"
echo ""
echo "If you created moltbook-api-key, deploy with both secrets:"
echo "  gcloud builds submit --config=cloudbuild.yaml --substitutions=_SET_SECRETS=GOOGLE_API_KEY=google-api-key:latest,MOLTBOOK_API_KEY=moltbook-api-key:latest"
echo ""
echo "Optional: set Splunk OTLP endpoint on the service (plain env, not a secret):"
echo "  gcloud run services update ${SERVICE_NAME} --region=${REGION} --set-env-vars=OTEL_EXPORTER_OTLP_ENDPOINT=https://ingest.REALM.signalfx.com/v2/otlp"
echo "  # plus a secret for OTEL_EXPORTER_OTLP_HEADERS if you use x-sf-token — create secret + add to --set-secrets on next deploy."

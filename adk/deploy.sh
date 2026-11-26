#!/usr/bin/env bash
# Déploie l'agent ADK (API + Web UI) sur Cloud Run, branché sur le service Ollama/Gemma 4.
#   ./deploy.sh                 # service privé (accès via `gcloud run services proxy`)
#   PUBLIC=true ./deploy.sh     # accès public (attention : le GPU devient utilisable par tous)
set -euo pipefail
cd "$(dirname "$0")"

PROJECT=${PROJECT:-jlandure-demos}
REGION=${REGION:-europe-west1}
MODEL=${MODEL:-gemma4:e4b}
OLLAMA_SERVICE=${OLLAMA_SERVICE:-ollama-gemma4}
SERVICE=${SERVICE:-gemma4-adk-agent}
SA_NAME=${SA_NAME:-gemma4-adk-agent}
SA="${SA_NAME}@${PROJECT}.iam.gserviceaccount.com"

OLLAMA_URL=$(gcloud run services describe "$OLLAMA_SERVICE" \
  --project "$PROJECT" --region "$REGION" --format 'value(status.url)')
echo "Ollama : $OLLAMA_URL"

# Compte de service dédié à l'agent, autorisé à appeler le service Ollama privé.
gcloud iam service-accounts describe "$SA" --project "$PROJECT" >/dev/null 2>&1 ||
  gcloud iam service-accounts create "$SA_NAME" --project "$PROJECT" \
    --display-name "Gemma 4 ADK agent"
gcloud run services add-iam-policy-binding "$OLLAMA_SERVICE" \
  --project "$PROJECT" --region "$REGION" \
  --member "serviceAccount:${SA}" --role roles/run.invoker >/dev/null

AUTH_FLAG=--no-allow-unauthenticated
[[ "${PUBLIC:-false}" == "true" ]] && AUTH_FLAG=--allow-unauthenticated

npx adk deploy cloud_run agents/gemma4_assistant \
  --project "$PROJECT" --region "$REGION" \
  --service_name "$SERVICE" \
  --with_ui \
  -- \
  --service-account "$SA" \
  --set-env-vars "OLLAMA_HOST=${OLLAMA_URL},OLLAMA_MODEL=${MODEL}" \
  --memory 1Gi --timeout 600 --max-instances 2 \
  "$AUTH_FLAG"

#!/usr/bin/env bash
# Build + déploiement d'Ollama/Gemma 4 sur Cloud Run GPU (NVIDIA L4).
#   ./deploy.sh                      # gemma4:e4b sur GPU
#   MODEL=gemma4:26b ./deploy.sh     # MoE 26B (A4B), tient dans les 24 Go d'une L4
#   GPU=false MODEL=gemma4:e2b SERVICE=ollama-gemma4-cpu ./deploy.sh   # variante CPU
set -euo pipefail
cd "$(dirname "$0")"

PROJECT=${PROJECT:-jlandure-demos}
REGION=${REGION:-europe-west1}
MODEL=${MODEL:-gemma4:e4b}
SERVICE=${SERVICE:-ollama-gemma4}
GPU=${GPU:-true}
IMAGE="${REGION}-docker.pkg.dev/${PROJECT}/cloud-run-source-deploy/ollama-gemma4:${MODEL#gemma4:}"

if [[ "${SKIP_BUILD:-false}" != "true" ]]; then
  gcloud builds submit . \
    --project "$PROJECT" --region "$REGION" \
    --config cloudbuild.yaml \
    --substitutions "_MODEL=${MODEL},_IMAGE=${IMAGE}"
fi

if [[ "$GPU" == "true" ]]; then
  HW=(--gpu 1 --gpu-type nvidia-l4 --no-gpu-zonal-redundancy --concurrency 4
      --set-env-vars OLLAMA_NUM_PARALLEL=4)
else
  HW=(--concurrency 1)
fi

# Service privé : seuls les comptes avec roles/run.invoker (l'agent ADK, vous via
# `gcloud run services proxy`) peuvent appeler Ollama.
gcloud run deploy "$SERVICE" \
  --project "$PROJECT" --region "$REGION" \
  --image "$IMAGE" \
  "${HW[@]}" \
  --cpu 8 --memory 32Gi --no-cpu-throttling \
  --max-instances 1 --timeout 600 \
  --no-allow-unauthenticated

#!/usr/bin/env bash
# Déploiement d'Ollama + Gemma 4 sur Cloud Run GPU (NVIDIA L4).
#
# Deux façons de fournir le modèle (doc Google « Best practices: AI inference on
# Cloud Run services with GPUs ») :
#   STORAGE=image : modèle embarqué dans l'image, recommandé < 10 Go (e2b, e4b, 12b)
#   STORAGE=gcs   : modèle dans Cloud Storage monté en volume, recommandé > 10 Go (26b, 31b)
#
#   ./deploy.sh                                              # gemma4:e4b, image
#   MODEL=gemma4:26b SERVICE=ollama-gemma4-26b ./deploy.sh   # MoE 26B, GCS (auto)
#   GPU=false MODEL=gemma4:e2b SERVICE=ollama-gemma4-cpu ./deploy.sh
#   SKIP_BUILD=true ...                                      # sans rebuild de l'image / resync du bucket
#   CONTEXT_LENGTH=16384 NUM_PARALLEL=2 ...                  # moins de VRAM (ex. pour le 26b)
set -euo pipefail
cd "$(dirname "$0")"

PROJECT=${PROJECT:-jlandure-demos}
REGION=${REGION:-europe-west1}
MODEL=${MODEL:-gemma4:e4b}
SERVICE=${SERVICE:-ollama-gemma4}
GPU=${GPU:-true}
# 64k tokens : assez pour Claude Code (son prompt système dépasse 16k tokens).
CONTEXT_LENGTH=${CONTEXT_LENGTH:-65536}
NUM_PARALLEL=${NUM_PARALLEL:-4}
OLLAMA_VERSION=0.40.18
BUCKET=${BUCKET:-${PROJECT}-ollama-models}
SA_NAME=${SA_NAME:-ollama-gemma4}
SA="${SA_NAME}@${PROJECT}.iam.gserviceaccount.com"
case "$MODEL" in
  *26b* | *31b*) STORAGE=${STORAGE:-gcs} ;;
  *) STORAGE=${STORAGE:-image} ;;
esac
echo "Modèle ${MODEL} -> ${SERVICE} (stockage : ${STORAGE}, GPU : ${GPU})"

# Compte de service dédié à Ollama (il ne peut que lire le bucket de modèles).
gcloud iam service-accounts describe "$SA" --project "$PROJECT" >/dev/null 2>&1 ||
  gcloud iam service-accounts create "$SA_NAME" --project "$PROJECT" \
    --display-name "Ollama Gemma 4 (Cloud Run GPU)"

# MODEL : le modèle que entrypoint.sh précharge avant d'ouvrir le port 8080.
ENV="MODEL=${MODEL},OLLAMA_KEEP_ALIVE=-1,OLLAMA_CONTEXT_LENGTH=${CONTEXT_LENGTH}"
STORAGE_ARGS=()
REGISTRY="${REGION}-docker.pkg.dev/${PROJECT}/cloud-run-source-deploy"

if [[ "$STORAGE" == "gcs" ]]; then
  gcloud storage buckets describe "gs://${BUCKET}" --project "$PROJECT" >/dev/null 2>&1 ||
    gcloud storage buckets create "gs://${BUCKET}" --project "$PROJECT" --location "$REGION" \
      --uniform-bucket-level-access --public-access-prevention
  gcloud storage buckets add-iam-policy-binding "gs://${BUCKET}" --project "$PROJECT" \
    --member "serviceAccount:${SA}" --role roles/storage.objectViewer >/dev/null
  # Direct VPC + accès privé Google : chemin réseau rapide vers Cloud Storage.
  gcloud compute networks subnets update default --project "$PROJECT" --region "$REGION" \
    --enable-private-ip-google-access
  # Image légère (Ollama + entrypoint.sh, sans modèle) : le modèle vient du bucket.
  IMAGE="${REGISTRY}/ollama-gemma4:runtime-${OLLAMA_VERSION}"
  if [[ "${SKIP_BUILD:-false}" != "true" ]]; then
    gcloud builds submit --no-source --project "$PROJECT" --region "$REGION" \
      --config cloudbuild-gcs.yaml --substitutions "_MODEL=${MODEL},_BUCKET=${BUCKET}"
    gcloud builds submit . --project "$PROJECT" --region "$REGION" \
      --config cloudbuild.yaml --substitutions "_MODEL=${MODEL},_IMAGE=${IMAGE},_BAKE_MODEL=false"
  fi
  ENV="OLLAMA_MODELS=/models,OLLAMA_NOPRUNE=true,${ENV}"
  STORAGE_ARGS=(
    --add-volume "name=models,type=cloud-storage,bucket=${BUCKET},readonly=true,mount-options=implicit-dirs;enable-buffered-read=true"
    --add-volume-mount "volume=models,mount-path=/models"
    --network default --subnet default --vpc-egress all-traffic
  )
else
  IMAGE="${REGISTRY}/ollama-gemma4:${MODEL#gemma4:}"
  if [[ "${SKIP_BUILD:-false}" != "true" ]]; then
    gcloud builds submit . --project "$PROJECT" --region "$REGION" \
      --config cloudbuild.yaml --substitutions "_MODEL=${MODEL},_IMAGE=${IMAGE},_BAKE_MODEL=true"
  fi
fi

if [[ "$GPU" == "true" ]]; then
  HW=(--gpu 1 --gpu-type nvidia-l4 --no-gpu-zonal-redundancy --concurrency 4)
  ENV="${ENV},OLLAMA_NUM_PARALLEL=${NUM_PARALLEL}"
else
  HW=(--concurrency 1)
fi

# Service privé : seuls les comptes avec roles/run.invoker (l'agent ADK, vous via
# `gcloud run services proxy`) peuvent appeler Ollama.
# Sonde de démarrage : entrypoint.sh n'ouvre le port 8080 qu'une fois le modèle en
# mémoire. On laisse jusqu'à 15 min (90 × 10 s) au chargement, au lieu des 240 s par
# défaut, trop justes pour un modèle de 7 à 18 Go. Le déploiement attend donc que
# le modèle soit prêt, et l'ancienne révision sert le trafic en attendant.
gcloud run deploy "$SERVICE" \
  --project "$PROJECT" --region "$REGION" \
  --image "$IMAGE" \
  --service-account "$SA" \
  --set-env-vars "$ENV" \
  ${STORAGE_ARGS[@]+"${STORAGE_ARGS[@]}"} \
  "${HW[@]}" \
  --startup-probe "tcpSocket.port=8080,initialDelaySeconds=0,periodSeconds=10,timeoutSeconds=10,failureThreshold=90" \
  --cpu 8 --memory 32Gi --no-cpu-throttling \
  --max-instances 1 --timeout 600 \
  --no-allow-unauthenticated

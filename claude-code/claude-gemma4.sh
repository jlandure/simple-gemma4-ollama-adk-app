#!/usr/bin/env bash
# Lance Claude Code sur Gemma 4 servi par Ollama, via l'API compatible Anthropic d'Ollama.
#   ./claude-gemma4.sh                     # Gemma 4 sur Cloud Run GPU (ouvre le proxy gcloud si besoin)
#   LOCAL=true ./claude-gemma4.sh          # Ollama du Mac
#   ./claude-gemma4.sh -p "Résume le README"   # les arguments sont passés à `claude`
set -euo pipefail

PROJECT=${PROJECT:-jlandure-demos}
REGION=${REGION:-europe-west1}
SERVICE=${SERVICE:-ollama-gemma4}
PORT=${PORT:-11435}
MODEL=${MODEL:-gemma4:e4b}

if [[ "${LOCAL:-false}" == "true" ]]; then
  HOST=http://localhost:11434
else
  HOST="http://localhost:${PORT}"
  if ! curl -sf "${HOST}/api/version" >/dev/null; then
    echo "Ouverture du proxy gcloud vers ${SERVICE} sur le port ${PORT}…" >&2
    gcloud run services proxy "$SERVICE" --project "$PROJECT" --region "$REGION" \
      --port "$PORT" >/dev/null 2>&1 &
    PROXY_PID=$!
    trap 'kill "$PROXY_PID" 2>/dev/null' EXIT
    until curl -sf "${HOST}/api/version" >/dev/null; do sleep 1; done
  fi
fi

# Claude Code parle l'API Messages d'Anthropic ; Ollama l'expose sur /v1/messages.
export ANTHROPIC_BASE_URL="$HOST"
export ANTHROPIC_AUTH_TOKEN=ollama
export ANTHROPIC_API_KEY=""
export ANTHROPIC_MODEL="$MODEL"
export ANTHROPIC_DEFAULT_OPUS_MODEL="$MODEL"
export ANTHROPIC_DEFAULT_SONNET_MODEL="$MODEL"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="$MODEL"
export CLAUDE_CODE_SUBAGENT_MODEL="$MODEL"
# Pas d'appels annexes vers les serveurs d'Anthropic (télémétrie, mises à jour…).
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1

echo "Claude Code -> ${MODEL} @ ${HOST}" >&2
claude "$@"

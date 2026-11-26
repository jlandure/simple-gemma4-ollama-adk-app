# À SOURCER (zsh ou bash), pas à exécuter :
#
#   source claude-code/claude.sh          # Gemma 4 sur Cloud Run GPU (ouvre le proxy gcloud si besoin)
#   GEMMA_LOCAL=true source claude-code/claude.sh   # Ollama du Mac
#
# Ensuite, dans ce terminal, `claude` et `claude -p "..."` utilisent Gemma 4.
# Pour revenir aux modèles Claude : claude_gemma4_off
#
# Ce fichier ne contient AUCUN secret. Tes clés et réglages perso vont dans
# claude-code/claude.local.sh (ignoré par Git), chargé automatiquement s'il existe.

_gemma_dir=$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)
[ -f "${_gemma_dir}/claude.local.sh" ] && . "${_gemma_dir}/claude.local.sh"
unset _gemma_dir

GEMMA_PROJECT=${GEMMA_PROJECT:-jlandure-demos}
GEMMA_REGION=${GEMMA_REGION:-europe-west1}
GEMMA_SERVICE=${GEMMA_SERVICE:-ollama-gemma4}
GEMMA_PORT=${GEMMA_PORT:-11435}
GEMMA_MODEL=${GEMMA_MODEL:-gemma4:e4b}
GEMMA_CONTEXT=${GEMMA_CONTEXT:-65536}

if [ "${GEMMA_LOCAL:-false}" = "true" ]; then
  GEMMA_HOST=http://localhost:11434
else
  GEMMA_HOST="http://localhost:${GEMMA_PORT}"
  if ! curl -sf "${GEMMA_HOST}/api/version" >/dev/null 2>&1; then
    echo "Ouverture du proxy gcloud vers ${GEMMA_SERVICE} sur le port ${GEMMA_PORT}…" >&2
    # Sous-shell : le proxy tourne en arrière-plan sans être lié à ce terminal.
    ( gcloud run services proxy "$GEMMA_SERVICE" --project "$GEMMA_PROJECT" \
        --region "$GEMMA_REGION" --port "$GEMMA_PORT" >/dev/null 2>&1 & )
    _gemma_i=0
    until curl -sf "${GEMMA_HOST}/api/version" >/dev/null 2>&1 || [ "$_gemma_i" -ge 60 ]; do
      sleep 1
      _gemma_i=$((_gemma_i + 1))
    done
    unset _gemma_i
  fi
fi

# Claude Code parle l'API Messages d'Anthropic ; Ollama l'expose sur /v1/messages.
# Jeton factice (Ollama ne le vérifie pas). Une éventuelle vraie clé Anthropic est mise
# de côté pour ne jamais partir vers Ollama, puis restaurée par claude_gemma4_off.
if [ -z "${_GEMMA_ACTIVE:-}" ]; then
  _GEMMA_SAVED_API_KEY="${ANTHROPIC_API_KEY-__unset__}"
  _GEMMA_ACTIVE=1
fi
export ANTHROPIC_BASE_URL="$GEMMA_HOST"
export ANTHROPIC_AUTH_TOKEN=ollama
export ANTHROPIC_API_KEY=""
export ANTHROPIC_MODEL="$GEMMA_MODEL"
export ANTHROPIC_DEFAULT_OPUS_MODEL="$GEMMA_MODEL"
export ANTHROPIC_DEFAULT_SONNET_MODEL="$GEMMA_MODEL"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="$GEMMA_MODEL"
export CLAUDE_CODE_SUBAGENT_MODEL="$GEMMA_MODEL"
# Taille réelle du contexte Ollama (Claude Code ne connaît pas ce modèle).
export CLAUDE_CODE_MAX_CONTEXT_TOKENS="$GEMMA_CONTEXT"
# Pas d'appels annexes vers Anthropic ; pas d'avertissement de facturation du mode auto.
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
export CLAUDE_CODE_AUTO_MODE_SERVER=0

# `claude` reste la vraie commande ; on filtre seulement la ligne
# "[claude-code:unrecognized_model]" écrite sur stderr pour tout modèle non-Claude.
# Mode acceptEdits par défaut (pas le mode auto, dont le classifieur serait Gemma) ;
# un --permission-mode passé explicitement reste prioritaire.
claude() {
  case " $* " in
    *" --permission-mode"*) set -- "$@" ;;
    *) set -- --permission-mode "${GEMMA_PERMISSION_MODE:-acceptEdits}" "$@" ;;
  esac
  command claude "$@" 2> >(grep --line-buffered -v '^\[claude-code:unrecognized_model\]' >&2)
}

claude_gemma4_off() {
  unset -f claude 2>/dev/null
  unset ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY ANTHROPIC_MODEL \
    ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL \
    CLAUDE_CODE_SUBAGENT_MODEL CLAUDE_CODE_MAX_CONTEXT_TOKENS \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC CLAUDE_CODE_AUTO_MODE_SERVER
  if [ "${_GEMMA_SAVED_API_KEY:-__unset__}" != "__unset__" ]; then
    export ANTHROPIC_API_KEY="$_GEMMA_SAVED_API_KEY"
  fi
  unset _GEMMA_SAVED_API_KEY _GEMMA_ACTIVE
  pkill -f "run services proxy ${GEMMA_SERVICE} .*--port ${GEMMA_PORT}" 2>/dev/null
  echo "claude -> modèles Claude (variables retirées, proxy ${GEMMA_PORT} arrêté)"
}

if curl -sf "${GEMMA_HOST}/api/version" >/dev/null 2>&1; then
  echo "claude -> ${GEMMA_MODEL} @ ${GEMMA_HOST}   (claude_gemma4_off pour revenir à Claude)"
else
  echo "Attention : ${GEMMA_HOST} ne répond pas (proxy ou Ollama)." >&2
fi

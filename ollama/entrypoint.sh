#!/usr/bin/env bash
# Démarrage d'Ollama sur Cloud Run : le port du conteneur ne s'ouvre qu'une fois
# le modèle chargé en mémoire (GPU ou CPU).
#
# Ollama ouvre son port avant d'avoir chargé le modèle : la sonde de démarrage
# de Cloud Run croirait l'instance prête alors que la première requête attendrait
# encore plusieurs minutes. Recommandation de la doc Google « GPU best practices » :
# la sonde ne doit passer que quand le modèle est prêt. D'où :
#   1. Ollama écoute en interne sur le port 11434, que Cloud Run n'expose pas ;
#   2. le modèle est préchargé (méthode de la FAQ Ollama : `ollama run <modèle> ""`) ;
#   3. une génération de chauffe (texte long + image) paie le coût du premier calcul GPU ;
#   4. socat ouvre ensuite le port de Cloud Run et relaie vers Ollama.
set -euo pipefail

: "${MODEL:?MODEL doit indiquer le modèle à précharger (ex. gemma4:e4b)}"
PORT=${PORT:-8080}
INTERNAL_PORT=${OLLAMA_INTERNAL_PORT:-11434}
# Le client `ollama` (list, run) parle au serveur en local.
export OLLAMA_HOST="127.0.0.1:${INTERNAL_PORT}"

# Le serveur écoute sur 0.0.0.0 et non 127.0.0.1 : sur une adresse de loopback,
# Ollama refuse (HTTP 403) toute requête dont l'en-tête Host n'est pas local, or
# socat relaie le Host d'origine (xxx.run.app). Seul le port 8080 est exposé par Cloud Run.
OLLAMA_HOST="0.0.0.0:${INTERNAL_PORT}" ollama serve &
ollama_pid=$!
socat_pid=

# Cloud Run envoie SIGTERM avant d'arrêter l'instance : on le transmet.
trap 'kill -TERM "$ollama_pid" ${socat_pid:+"$socat_pid"} 2>/dev/null || true' TERM INT

until ollama list >/dev/null 2>&1; do
  if ! kill -0 "$ollama_pid" 2>/dev/null; then
    echo "ollama serve s'est arrêté avant d'être prêt" >&2
    exit 1
  fi
  sleep 1
done

echo "Chargement de ${MODEL} en mémoire…"
start=$SECONDS
# L'animation de chargement d'`ollama run` polluerait les logs : on ne l'affiche qu'en cas d'échec.
if ! ollama run "$MODEL" "" </dev/null >/dev/null 2>/tmp/preload.log; then
  echo "Échec du chargement de ${MODEL} :" >&2
  cat /tmp/preload.log >&2
  exit 1
fi
echo "${MODEL} chargé en $((SECONDS - start)) s"

# Chauffe : le tout premier calcul sur le GPU est très lent (57 s mesurées pour les
# 512 premiers tokens d'un prompt sur L4, 40 s pour la première image), puis tout est
# rapide. Un prompt vide ne calcule rien : on lance une vraie génération, avec plus de
# 512 tokens de texte (même chemin de calcul qu'un vrai prompt) et une image.
WARMUP_IMAGE=${WARMUP_IMAGE:-/usr/local/share/ollama/warmup.jpg}
filler=$(printf 'Gemma 4 tourne sur Cloud Run avec un GPU NVIDIA L4. %.0s' {1..60})
warmup_prompt="${filler} Réponds seulement OK."
[[ -f "$WARMUP_IMAGE" ]] && warmup_prompt="${warmup_prompt} ${WARMUP_IMAGE}"
echo "Chauffe de ${MODEL}…"
start=$SECONDS
if ollama run "$MODEL" --think=false "$warmup_prompt" </dev/null >/dev/null 2>/tmp/warmup.log; then
  echo "Chauffe terminée en $((SECONDS - start)) s, ouverture du port ${PORT}"
else
  # Le modèle est chargé : on sert quand même, les premières requêtes seront juste plus lentes.
  echo "Chauffe en échec, ouverture du port ${PORT} quand même :" >&2
  cat /tmp/warmup.log >&2
fi

socat "TCP-LISTEN:${PORT},fork,reuseaddr,nodelay" "TCP:127.0.0.1:${INTERNAL_PORT},nodelay" &
socat_pid=$!

# Si Ollama ou socat s'arrête, le conteneur s'arrête aussi et Cloud Run le remplace.
status=0
wait -n "$ollama_pid" "$socat_pid" || status=$?
kill -TERM "$ollama_pid" "$socat_pid" 2>/dev/null || true
wait || true
exit "$status"

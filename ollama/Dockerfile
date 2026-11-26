# Ollama + Gemma 4, prêt pour Cloud Run (GPU NVIDIA L4 ou CPU).
# STORAGE=image : les poids du modèle sont embarqués dans l'image, pas de téléchargement au démarrage.
# STORAGE=gcs   : image sans modèle (BAKE_MODEL=false), le modèle vient du volume Cloud Storage.
FROM ollama/ollama:0.40.18

# socat ouvre le port de Cloud Run une fois le modèle chargé (voir entrypoint.sh).
RUN apt-get update \
    && apt-get install -y --no-install-recommends socat \
    && rm -rf /var/lib/apt/lists/*

# Modèle à embarquer et à précharger : gemma4:e2b | gemma4:e4b | gemma4:12b | gemma4:26b | gemma4:31b
ARG MODEL=gemma4:e4b
ARG BAKE_MODEL=true

ENV OLLAMA_MODELS=/models \
    OLLAMA_DEBUG=false \
    # Ne jamais décharger le modèle de la mémoire GPU
    OLLAMA_KEEP_ALIVE=-1 \
    # Contexte suffisant pour Claude Code (surchargé par deploy.sh)
    OLLAMA_CONTEXT_LENGTH=65536 \
    MODEL=${MODEL}

RUN if [ "$BAKE_MODEL" = "true" ]; then \
      ollama serve & \
      until ollama list >/dev/null 2>&1; do sleep 1; done && \
      ollama pull "$MODEL"; \
    fi

# Image de la génération de chauffe (voir entrypoint.sh).
COPY warmup.jpg /usr/local/share/ollama/warmup.jpg
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 755 /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# Ollama + Gemma 4, prêt pour Cloud Run (GPU NVIDIA L4 ou CPU).
# Les poids du modèle sont embarqués dans l'image : pas de téléchargement au démarrage.
FROM ollama/ollama:0.40.18

# Modèle à embarquer : gemma4:e2b | gemma4:e4b | gemma4:12b | gemma4:26b | gemma4:31b
ARG MODEL=gemma4:e4b

ENV OLLAMA_HOST=0.0.0.0:8080 \
    OLLAMA_MODELS=/models \
    OLLAMA_DEBUG=false \
    # Ne jamais décharger le modèle de la mémoire GPU
    OLLAMA_KEEP_ALIVE=-1 \
    # Contexte suffisant pour Claude Code (surchargé par deploy.sh)
    OLLAMA_CONTEXT_LENGTH=65536 \
    MODEL=${MODEL}

RUN ollama serve & \
    until ollama list >/dev/null 2>&1; do sleep 1; done && \
    ollama pull "$MODEL"

ENTRYPOINT ["ollama", "serve"]

# Gemma 4 × ADK × Cloud Run GPU

Un agent [ADK pour TypeScript](https://github.com/google/adk-js) propulsé par **Gemma 4**, servi par **Ollama** : en local sur un Mac, puis sur **Cloud Run GPU** (NVIDIA L4).

Suite de [simple-gemma3-ollama-langchainjs-app](https://github.com/jlandure/simple-gemma3-ollama-langchainjs-app) : Gemma 3 devient Gemma 4, et LangChain.js est remplacé par l'Agent Development Kit de Google.

```text
                    ┌───────────────────────────────┐
 ADK Web / demo ──▶ │ adk/ LlmAgent                 │── OllamaLlm ──▶ Ollama + Gemma 4
                    │  ├ get_current_time, weather  │                (Mac, ou Cloud Run L4)
                    │  └ MCPToolset ─▶ Context7 MCP │
                    └───────────────────────────────┘
```

## Structure

- [adk/](adk/README.md) : l'agent ADK (TypeScript), son connecteur Ollama, ses outils, le MCP Context7, une démo scriptée et le déploiement Cloud Run.
- [ollama/](ollama/README.md) : Ollama + Gemma 4 sur Cloud Run GPU (modèle dans l'image ou dans Cloud Storage).
- [AGENTS.md](AGENTS.md) : tout le contexte pour un agent de code (Claude Code, Gemini CLI, Copilot…).

## Démarrage rapide (Mac)

```bash
ollama pull gemma4:e4b
```

```bash
cd adk && npm install && npm run demo
```

```bash
npm run web
```

## Sur Cloud Run (projet `jlandure-demos`)

```bash
./ollama/deploy.sh
```

```bash
./adk/deploy.sh
```

En bonus, le MoE 26B (plus de qualité, pas plus rapide) :

```bash
MODEL=gemma4:26b SERVICE=ollama-gemma4-26b ./ollama/deploy.sh
```

```bash
MODEL=gemma4:26b OLLAMA_SERVICE=ollama-gemma4-26b ./adk/deploy.sh
```

```bash
gcloud run services proxy gemma4-adk-agent --project jlandure-demos --region europe-west1 --port 8080
```

Puis ouvrir http://localhost:8080/dev-ui/.

| Service Cloud Run | Rôle | Modèle |
| --- | --- | --- |
| `ollama-gemma4` | Ollama, GPU L4 | `gemma4:e4b` dans l'image |
| `ollama-gemma4-26b` | Ollama, GPU L4 | `gemma4:26b` (MoE) dans Cloud Storage, monté en volume |
| `gemma4-adk-agent` | ADK API server + Web UI | appelle `ollama-gemma4` (e4b) |

**Tout est privé.** Les services Ollama n'acceptent que le compte de service de l'agent (`gemma4-adk-agent`, rôle `roles/run.invoker`) et les utilisateurs du projet via `gcloud run services proxy`. L'agent s'authentifie auprès d'Ollama avec un ID token Google, sans clé ni secret.

## Ce que montre la démo

1. **Traduction** FR -> EN.
2. **Multimodal** : description d'une photo de la tour Eiffel (`npm run demo -- chemin/image.jpg` pour une autre).
3. **Function calling** : heure et météo à Las Vegas, deux outils appelés en parallèle.
4. **MCP** : Gemma 4 interroge le serveur MCP distant Context7 pour trouver la dernière version de Google ADK.

## Gemma 4 en bref

| Modèle Ollama | Usage conseillé |
| --- | --- |
| `gemma4:e2b` | CPU, appareils modestes |
| `gemma4:e4b` | Mac Apple Silicon et GPU L4 (le plus rapide pour la démo) |
| `gemma4:26b` | MoE (4B actifs), meilleure qualité, tient sur une L4 |
| `gemma4:31b` | dense, le plus gros |

Tous gèrent texte + image, function calling et un mode « thinking ».

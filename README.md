# Gemma 4 × ADK × Cloud Run GPU

Un agent [ADK pour TypeScript](https://github.com/google/adk-js) propulsé par **Gemma 4**, servi par **Ollama** : en local sur un Mac, puis sur **Cloud Run GPU** (NVIDIA L4).

Suite de [simple-gemma3-ollama-langchainjs-app](https://github.com/jlandure/simple-gemma3-ollama-langchainjs-app) : Gemma 3 devient Gemma 4, et LangChain.js est remplacé par l'Agent Development Kit de Google.

```text
                  ┌──────────────────────────┐
 ADK Web / demo ─▶│  adk/  (LlmAgent + tools) │── OllamaLlm ──▶ Ollama + gemma4:e4b
                  └──────────────────────────┘                 (Mac ou Cloud Run L4)
```

## Structure

- [adk/](adk/README.md) : l'agent ADK (TypeScript), son connecteur Ollama, ses outils, une démo scriptée et le déploiement Cloud Run.
- [ollama/](ollama/README.md) : l'image Ollama avec Gemma 4 embarqué et son déploiement sur Cloud Run GPU.

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

## Ce que montre la démo

1. **Traduction** FR -> EN.
2. **Multimodal** : description d'une capture d'écran.
3. **Function calling** : Gemma 4 appelle `get_current_time` et `get_weather` (Open-Meteo, sans clé), en parallèle.

## Gemma 4 en bref

| Modèle Ollama | Usage conseillé |
| --- | --- |
| `gemma4:e2b` | CPU, appareils modestes |
| `gemma4:e4b` | défaut : Mac (Apple Silicon) et GPU L4 |
| `gemma4:26b` | MoE (4B actifs), meilleure qualité, tient sur une L4 |
| `gemma4:31b` | dense, le plus gros |

Tous gèrent texte + image, function calling et un mode « thinking ».

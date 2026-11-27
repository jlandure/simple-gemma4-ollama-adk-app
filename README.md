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
- [claude-code/](claude-code/README.md) : démo bonus, Claude Code qui utilise Gemma 4 sur Cloud Run comme modèle (voir plus bas).
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
4. **MCP** : Gemma 4 interroge le serveur MCP distant Context7 (librairie `/google/adk-js`) pour expliquer comment installer ADK pour TypeScript et lancer son interface web.

## Démo bonus : Claude Code sur Gemma 4

**Claude Code** (l'agent de code en terminal d'Anthropic) peut utiliser Gemma 4 sur Cloud Run à la place des modèles Claude : Ollama expose une API compatible Anthropic (`/v1/messages`), et Claude Code accepte une autre URL d'API avec `ANTHROPIC_BASE_URL`.

```text
 claude (terminal) ──▶ localhost:11435 ── gcloud run services proxy ──▶ Cloud Run "ollama-gemma4"
                       API Messages d'Anthropic                         gemma4:e4b sur NVIDIA L4, contexte 64k
```

```bash
source claude-code/claude.sh
```

```bash
cd adk && claude -p "Liste les outils définis dans agents/gemma4_assistant/tools.ts"
```

`claude_gemma4_off` remet le terminal sur les modèles Claude. Le fichier ne contient aucun secret ; les réglages perso vont dans `claude-code/claude.local.sh`, ignoré par Git. Variante tout-en-un : `cd adk && ../claude-code/claude-gemma4.sh`.

Le lanceur ouvre le proxy `gcloud`, oriente tous les rôles de Claude Code (principal, rapide, sous-agents) vers `gemma4:e4b`, déclare le contexte de 64k, lance en mode `acceptEdits` et coupe les messages parasites au démarrage. Détails, variables et scénario : [claude-code/README.md](claude-code/README.md).

Testé le 26/11/2026 (Claude Code 2.1.318, Ollama 0.40.18, L4) :

| Demande | Tours | Durée | Résultat |
| --- | --- | --- | --- |
| « Liste les outils de tools.ts » | 2 | 7,8 s | réponse juste |
| « Ajoute un FunctionTool get_moon_phase et branche-le dans agent.ts » | 5 | 50 s | 2 fichiers modifiés, `tsc` OK, mais calcul de la lune naïf (basé sur le jour du mois) |

### Limites à annoncer

- **Gemma 4 e4b n'est pas Claude** : très bien pour lire et expliquer du code ; il sait modifier plusieurs fichiers, mais la qualité de la logique générée est inégale (voir la phase de lune ci-dessus, un bon exemple à montrer). Le `gemma4:26b` (`SERVICE=ollama-gemma4-26b PORT=11436 MODEL=gemma4:26b`) est plus solide, mais plus lent et limité en contexte sur une L4.
- Chaque démarrage d'instance charge le modèle en VRAM (2 à 4 minutes). Le déploiement attend que le modèle soit prêt, mais après un passage à zéro instance, le premier appel attend ce chargement : passer à `--min-instances 1` avant de monter sur scène.
- Les fonctions propres aux modèles Claude (cache de prompt, recherche web côté serveur, etc.) ne sont pas disponibles.

## Gemma 4 en bref

| Modèle Ollama | Usage conseillé |
| --- | --- |
| `gemma4:e2b` | CPU, appareils modestes |
| `gemma4:e4b` | Mac Apple Silicon et GPU L4 (le plus rapide pour la démo) |
| `gemma4:12b` | taille intermédiaire (juin 2026), annoncé proche du 26B pour moins de la moitié de la mémoire, entrée audio |
| `gemma4:26b` | MoE (4B actifs), meilleure qualité, tient sur une L4 |
| `gemma4:31b` | dense, le plus gros |

Tous gèrent texte + image, function calling et un mode « thinking ». Ollama propose aussi des variantes QAT (`-it-qat`, entraînées pour la quantification 4 bits, plus légères) et MTP (`-mtp-`, décodage spéculatif annoncé jusqu'à 3 fois plus rapide), non testées dans ce dépôt.

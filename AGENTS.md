# AGENTS.md

Guide pour les agents de code (Claude Code, Gemini CLI, Copilot…) qui travaillent sur ce dépôt.

## Le projet

Démo de conférence : un agent **Google ADK pour TypeScript** (`@google/adk` 2.5) propulsé par **Gemma 4**, servi par **Ollama**, en local sur un Mac Apple Silicon puis sur **Cloud Run GPU** (NVIDIA L4) dans le projet GCP `jlandure-demos` (région `europe-west1`).

Ancienne version (Gemma 3 + LangChain.js) : https://github.com/jlandure/simple-gemma3-ollama-langchainjs-app

## Arborescence

```text
adk/                              # l'agent (Node.js ≥ 22, ESM, TypeScript exécuté par tsx / adk CLI)
  agents/gemma4_assistant/
    agent.ts                      # rootAgent (LlmAgent) + MCPToolset Context7 + filtre de logs MCP
    ollama_llm.ts                 # OllamaLlm extends BaseLlm -> POST {OLLAMA_HOST}/api/chat
    tools.ts                      # FunctionTool get_current_time, get_weather (Open-Meteo, sans clé)
  demo.ts                         # démo scriptée en 4 étapes (traduction, image, outils, MCP)
  images/                         # images de démo (tour-eiffel.jpg par défaut, holzmarkt-infos.png)
  deploy.sh                       # adk deploy cloud_run + compte de service gemma4-adk-agent
  .npmrc                          # force registry.npmjs.org (le ~/.npmrc global pointe vers un Artifactory client)
ollama/
  Dockerfile                      # Ollama 0.40.18 + modèle embarqué (mode STORAGE=image)
  cloudbuild.yaml                 # build de l'image avec modèle embarqué
  cloudbuild-gcs.yaml             # ollama pull puis rsync vers gs://jlandure-demos-ollama-models
  deploy.sh                       # déploiement Cloud Run GPU, STORAGE=image|gcs
```

## Commandes

Toutes depuis `adk/` :

| Commande | Effet |
| --- | --- |
| `npm install` | dépendances (registre npm public via `.npmrc`) |
| `npm run typecheck` | `tsc` sans émission, à lancer après chaque modification |
| `npm run demo [-- chemin/image]` | démo scriptée contre `$OLLAMA_HOST` |
| `npm run web` | ADK Web UI sur http://localhost:8000 |
| `npm run chat` | conversation en terminal |
| `npm run api` | ADK API server |
| `./deploy.sh` | déploie l'agent sur Cloud Run |

Depuis `ollama/` : `./deploy.sh` (voir variables plus bas).

## Variables d'environnement de l'agent

| Variable | Défaut | Rôle |
| --- | --- | --- |
| `OLLAMA_HOST` | `http://localhost:11434` | serveur Ollama (le schéma `http://` est ajouté s'il manque) |
| `OLLAMA_MODEL` | `gemma4:e4b` | modèle Ollama |
| `OLLAMA_THINK` | `false` | active le raisonnement de Gemma 4 (parts `thought: true`) |
| `OLLAMA_AUTH` | auto | `none` désactive l'ID token vers `*.run.app` |
| `OLLAMA_ID_TOKEN` | — | ID token fourni à la main (sinon serveur de métadonnées) |
| `CONTEXT7_API_KEY` | — | clé Context7 optionnelle (en-tête `CONTEXT7_API_KEY`) |
| `CONTEXT7_MCP_URL` | `https://mcp.context7.com/mcp` | serveur MCP Streamable HTTP |
| `DEMO_IMAGE` | `images/tour-eiffel.jpg` | image de l'étape 2 de la démo |

## Architecture Cloud Run

| Service | Contenu | Accès |
| --- | --- | --- |
| `ollama-gemma4` | Ollama + `gemma4:e4b` **embarqué dans l'image** (9,6 Go) | privé |
| `ollama-gemma4-26b` | Ollama + `gemma4:26b` (MoE, ~18 Go) **dans Cloud Storage**, monté en volume FUSE en lecture seule | privé |
| `gemma4-adk-agent` | ADK API server + Web UI (`adk deploy cloud_run --with_ui`) | privé |

- **Chargement du modèle** (doc Google « GPU best practices ») : image conteneur pour les modèles < 10 Go, Cloud Storage au-delà. Le mode GCS utilise Direct VPC (`default`, egress `all-traffic`), l'accès privé Google sur le sous-réseau `default` d'`europe-west1`, et l'option FUSE `enable-buffered-read`. `OLLAMA_NOPRUNE=true` car le volume est en lecture seule.
- **Comptes de service** : `ollama-gemma4@` (lecture du bucket), `gemma4-adk-agent@` (`roles/run.invoker` sur les services Ollama).
- **Authentification** : l'agent appelle Ollama avec un ID token (audience = URL du service) obtenu par `google-auth-library`. Depuis un poste, on passe par `gcloud run services proxy <service> --port <port>`.
- **GPU** : 1 L4, 8 vCPU, 32 Gio, `--no-gpu-zonal-redundancy`, `--max-instances 1`, `OLLAMA_NUM_PARALLEL=4`, `OLLAMA_KEEP_ALIVE=-1`, `OLLAMA_CONTEXT_LENGTH=16384`.
- **Coûts** : `deploy.sh` ne fixe pas `--min-instances` (0 par défaut). Passer à 1 avant une démo avec `gcloud run services update <service> --min-instances 1`, puis revenir à 0 : une L4 chaude est facturée en continu.

## Conventions et pièges connus

- ADK JS n'a pas d'intégration Ollama : `OllamaLlm` étend `BaseLlm` et est enregistré via `LLMRegistry.register` (le nom `ollama/<modèle>` fonctionne aussi). Les schémas Gemini (`type: 'OBJECT'`) sont convertis en JSON Schema minuscule pour Ollama.
- `adk web` / `adk deploy` prennent un dossier d'agents : chaque sous-dossier avec un `agent.ts` qui exporte `rootAgent` est une app. Ne pas mettre de script exécutable (comme `demo.ts`) dans `agents/`.
- `@modelcontextprotocol/sdk` est une dépendance pair optionnelle d'ADK : elle doit rester dans `dependencies`.
- ADK ferme la session MCP après chaque appel, ce qui logue une fausse erreur « MCP transport error … aborted » : `agent.ts` la rétrograde en `debug`.
- Context7 n'indexe pas de numéro de version pour ADK JS (seulement Python et Go) : ne pas promettre la version npm exacte dans la démo.
- `adk deploy cloud_run` (adk-devtools 2.5.0) transmet à `gcloud` tout argument qui n'est pas une option ADK, y compris les valeurs séparées par un espace et le séparateur `--` : écrire **toutes** les options en `--option=valeur`, sans `--`, et le chemin de l'agent en premier.
- Ollama 0.40 fait un `MkdirAll` sur `$OLLAMA_MODELS/manifests-v2` au chargement d'un modèle : le bucket doit contenir `manifests-v2/.keep` (créé par `cloudbuild-gcs.yaml`) et le volume est monté avec `implicit-dirs`.
- Démarrage à froid sur L4 : ~2 min 30 pour `e4b` (image), plus pour `26b` (GCS). Toute mise à jour du service crée une révision et recharge le modèle : faire un appel de chauffe après chaque déploiement.
- Temps mesurés à chaud, Ollama 0.40.18 (démo complète, image = tour Eiffel) :

  | Cible | Traduction | Image | Outils | MCP |
  | --- | --- | --- | --- | --- |
  | Mac M1 Pro, `e4b` | 5,2 s | 12,3 s | 8,1 s | 11,0 s |
  | Cloud Run L4, `e4b` | 1,9 s | 4,3 s | 2,9 s | 5,0 s |
  | Cloud Run L4, `26b` | 17,8 s | 28,7 s* | 4,9 s | 5,8 s |

  *mesuré avec holzmarkt-infos.png (3,4 Mo). Le `26b` apporte de la qualité, pas de la vitesse : pour une démo rapide, rester sur `e4b`.
- `gemma4:e4b-mlx` (Apple Silicon, Ollama ≥ 0.31) : aucun gain sur M1 Pro (33,7 vs 34,5 tok/s en génération, prompt plus lent). Garder `gemma4:e4b` par défaut.
- Imports TypeScript avec extension `.js` (résolution `nodenext`).
- Code et commentaires : commentaires en français, identifiants en anglais.
- Commits : gitmoji + description courte en anglais, terminer par `Co-authored-by: Claude Code (TechTown)`.

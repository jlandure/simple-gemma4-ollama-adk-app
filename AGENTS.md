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
claude-code/
  claude.sh                       # à sourcer : `claude` du terminal -> Gemma 4 en acceptEdits ; claude_gemma4_off pour revenir
  claude.local.sh.example         # modèle pour claude.local.sh (ignoré par Git : clés et réglages perso)
  claude-gemma4.sh                # lanceur tout-en-un (acceptEdits, filtre stderr)
  README.md                       # démo Claude Code + Gemma 4 Cloud Run
ollama/
  Dockerfile                      # Ollama 0.40.18 + socat + entrypoint.sh, modèle embarqué si BAKE_MODEL=true
  entrypoint.sh                   # précharge et chauffe le modèle, puis seulement ouvre le port 8080 (socat -> port interne 11434)
  cloudbuild.yaml                 # build de l'image (_BAKE_MODEL=true : avec modèle ; false : image légère pour GCS)
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
| `ollama-gemma4` | Ollama + `gemma4:e4b` **embarqué dans l'image** (~6,6 Go) | privé |
| `ollama-gemma4-26b` | Ollama + `gemma4:26b` (MoE, ~18 Go) **dans Cloud Storage**, monté en volume FUSE en lecture seule | privé |
| `gemma4-adk-agent` | ADK API server + Web UI (`adk deploy cloud_run --with_ui`), branché sur `ollama-gemma4` (e4b), app `agent` | privé |

- **Chargement du modèle** (doc Google « GPU best practices ») : image conteneur pour les modèles < 10 Go, Cloud Storage au-delà. Le mode GCS utilise Direct VPC (`default`, egress `all-traffic`), l'accès privé Google sur le sous-réseau `default` d'`europe-west1`, et l'option FUSE `enable-buffered-read`. `OLLAMA_NOPRUNE=true` car le volume est en lecture seule.
- **Comptes de service** : `ollama-gemma4@` (lecture du bucket), `gemma4-adk-agent@` (`roles/run.invoker` sur les services Ollama).
- **Authentification** : l'agent appelle Ollama avec un ID token (audience = URL du service) obtenu par `google-auth-library`. Depuis un poste, on passe par `gcloud run services proxy <service> --port <port>`.
- **GPU** : 1 L4, 8 vCPU, 32 Gio, `--no-gpu-zonal-redundancy`, `--max-instances 1`, `OLLAMA_NUM_PARALLEL=4`, `OLLAMA_KEEP_ALIVE=-1`, `OLLAMA_CONTEXT_LENGTH=65536` (variable `CONTEXT_LENGTH` de `ollama/deploy.sh`, nécessaire pour Claude Code).
- **Coûts** : `deploy.sh` ne fixe pas `--min-instances` (0 par défaut). Passer à 1 avant une démo avec `gcloud run services update <service> --min-instances 1`, puis revenir à 0 : une L4 chaude est facturée en continu.

## Coûts et nettoyage après une démo

Ordre de grandeur (tarif public `europe-west1`, sans redondance zonale) : une instance Ollama (L4 + 8 vCPU + 32 Gio) coûte **~1,42 $/h**, facturée tant qu'elle tourne. Exemple réel : `ollama-gemma4` et `ollama-gemma4-26b` laissés à `min-instances 1` du 26/11/2026 ~9h40 au 27/11 ~19h = ~50 h d'instance, **~71 $**. Vérifier les deux services Ollama, pas seulement celui de la démo.

1. **Remettre tout à zéro** (chaque commande crée une révision et démarre une instance, qui s'éteint après ~15 min sans requête) :

   ```bash
   for s in ollama-gemma4 ollama-gemma4-26b gemma4-adk-agent; do gcloud run services update $s --project jlandure-demos --region europe-west1 --min-instances 0; done
   ```

2. **Vérifier** : `minScale` vide = 0.

   ```bash
   for s in ollama-gemma4 ollama-gemma4-26b gemma4-adk-agent; do gcloud run services describe $s --project jlandure-demos --region europe-west1 --format="value(metadata.name,spec.template.metadata.annotations.'autoscaling.knative.dev/minScale')"; done
   ```

   Temps d'instance facturable des dernières 48 h, par service (métrique Cloud Monitoring `run.googleapis.com/container/billable_instance_time`, via l'API REST) :

   ```bash
   curl -s -G "https://monitoring.googleapis.com/v3/projects/jlandure-demos/timeSeries" -H "Authorization: Bearer $(gcloud auth print-access-token)" --data-urlencode 'filter=metric.type="run.googleapis.com/container/billable_instance_time" AND resource.type="cloud_run_revision"' --data-urlencode "interval.startTime=$(date -u -v-2d +%Y-%m-%dT%H:%M:%SZ)" --data-urlencode "interval.endTime=$(date -u +%Y-%m-%dT%H:%M:%SZ)" --data-urlencode "aggregation.alignmentPeriod=172800s" --data-urlencode "aggregation.perSeriesAligner=ALIGN_SUM" --data-urlencode "aggregation.crossSeriesReducer=REDUCE_SUM" --data-urlencode "aggregation.groupByFields=resource.label.service_name"
   ```

   Valeurs en secondes. La facture réelle arrive dans la console (Facturation > Rapports) avec jusqu'à 24 h de retard.

3. **Nettoyer Artifact Registry.** Chaque build de `ollama/` pousse une image de ~9,3 Go (`ollama-gemma4`) et l'ancienne perd son tag mais reste stockée (~0,10 $/Go/mois). Le dépôt `europe-west1-docker.pkg.dev/jlandure-demos/cloud-run-source-deploy` est **partagé avec d'autres projets** (merch4you, mcp-registry…) : ne supprimer que les paquets `ollama-gemma4` et `gemma4-adk-agent`, et **garder l'image de la révision en service**, sinon Cloud Run ne peut plus démarrer d'instance (une révision référence son image par empreinte). Supprimer une image empêche aussi tout retour arrière vers les révisions qui l'utilisaient.

   ```bash
   REPO=europe-west1-docker.pkg.dev/jlandure-demos/cloud-run-source-deploy
   for pkg in ollama-gemma4 gemma4-adk-agent; do
     keep=$(gcloud run revisions describe "$(gcloud run services describe "$pkg" --project jlandure-demos --region europe-west1 --format='value(status.latestReadyRevisionName)')" --project jlandure-demos --region europe-west1 --format='value(status.imageDigest)')
     for d in $(gcloud artifacts docker images list "$REPO/$pkg" --format='value(version)'); do
       [[ "$keep" == *"$d" ]] && echo "garde $pkg@$d" && continue
       gcloud artifacts docker images delete "$REPO/$pkg@$d" --delete-tags --quiet
     done
   done
   ```

   Ce script suppose que tout le trafic va à la dernière révision prête (`gcloud run services describe <service> --format='value(status.traffic)'` pour le vérifier). `ollama-gemma4-26b` utilise l'image Ollama publique tant qu'il n'a pas été redéployé avec le `deploy.sh` actuel ; ensuite son image légère s'appelle `ollama-gemma4:runtime-<version>` et se nettoie de la même façon. Le 27/11/2026, ce nettoyage a supprimé 5 images `ollama-gemma4` et 2 images `gemma4-adk-agent` (~47 Go).

4. **Le bucket** `gs://jlandure-demos-ollama-models` garde le modèle 26b (~18 Go, ~0,40 $/mois) : le conserver tant que le service `ollama-gemma4-26b` existe, il en a besoin pour démarrer.

## Conventions et pièges connus

- ADK JS n'a pas d'intégration Ollama : `OllamaLlm` étend `BaseLlm` et est enregistré via `LLMRegistry.register` (le nom `ollama/<modèle>` fonctionne aussi). Les schémas Gemini (`type: 'OBJECT'`) sont convertis en JSON Schema minuscule pour Ollama.
- `adk web` / `adk deploy` prennent un dossier d'agents : chaque sous-dossier avec un `agent.ts` qui exporte `rootAgent` est une app. Ne pas mettre de script exécutable (comme `demo.ts`) dans `agents/`.
- `@modelcontextprotocol/sdk` est une dépendance pair optionnelle d'ADK : elle doit rester dans `dependencies`.
- ADK ferme la session MCP après chaque appel, ce qui logue une fausse erreur « MCP transport error … aborted » : `agent.ts` la rétrograde en `debug`.
- Context7 n'indexe pas de numéro de version pour ADK JS (seulement Python et Go) : ne pas promettre la version npm exacte dans la démo.
- Dans Context7, ADK JS officiel = `/google/adk-js`. `resolve-library-id` ne le propose pas et met en avant ADK-TS d'IQAI (`/braindao/adk-ts`, `/websites/adk_iqai`), un autre framework, mieux noté : la démo donne l'ID directement pour que Gemma appelle `query-docs` sans passer par la recherche. Ne pas écrire « Avec Context7 (librairie …) » dans la question : Gemma lance alors `resolve-library-id("Context7")` en plus (+10 s). La formulation « Cherche dans la documentation de la librairie /google/adk-js : … » donne un seul appel `query-docs` (3 essais sur 3, 15 à 22 s sur M1 Pro).
- `adk deploy cloud_run` (adk-devtools 2.5.0) transmet à `gcloud` tout argument qui n'est pas une option ADK, y compris les valeurs séparées par un espace et le séparateur `--` : écrire **toutes** les options en `--option=valeur`, sans `--`, et le chemin de l'agent en premier.
- Le serveur ADK refuse toute origine non déclarée (`403 Forbidden: origin not allowed`, affiché « Failed to create session » dans l'UI) : `adk/deploy.sh` passe `--allow_origins` avec `http://localhost:8080` (proxy) et l'URL Cloud Run du service. Variable `ALLOW_ORIGINS` pour en ajouter.
- Ollama 0.40 fait un `MkdirAll` sur `$OLLAMA_MODELS/manifests-v2` au chargement d'un modèle : le bucket doit contenir `manifests-v2/.keep` (créé par `cloudbuild-gcs.yaml`) et le volume est monté avec `implicit-dirs`.
- Démarrage à froid sur L4 : ~2 min 30 pour `e4b` (image), plus pour `26b` (GCS). Toute mise à jour du service crée une révision et recharge le modèle.
- Ollama ouvre son port avant d'avoir chargé le modèle : la sonde TCP de Cloud Run passerait trop tôt. `ollama/entrypoint.sh` lance Ollama sur le port interne 11434, précharge `$MODEL` (`ollama run $MODEL ""`), lance une génération de chauffe (prompt de plus de 512 tokens + `warmup.jpg`), puis ouvre le port 8080 avec socat. Sans cette chauffe, le premier calcul GPU coûte ~57 s sur L4 (et ~40 s pour la première image), même modèle chargé : un prompt vide ne calcule rien. Avec elle, la première traduction de la démo passe de 74 s à 2 s, mais la première image reste à ~21 s (17 s de calcul du prompt, image placée après ~1 700 tokens de contexte ADK) ; une image de chauffe en taille réelle n'y change rien. Toujours rediriger stdin (`</dev/null`) : hors terminal, `ollama run` lit stdin et attendrait indéfiniment. `deploy.sh` règle la sonde de démarrage à 15 min (`failureThreshold=90`, `periodSeconds=10`) : le défaut de 240 s est trop court. La variable `MODEL` est obligatoire dans le service. Le serveur interne doit écouter sur `0.0.0.0` : lié à `127.0.0.1`, Ollama répond 403 à toute requête dont l'en-tête `Host` n'est pas local, ce qui est le cas derrière socat (`xxx.run.app`).
- Temps mesurés à chaud, Ollama 0.40.18 (démo complète, image = tour Eiffel) :

  | Cible | Traduction | Image | Outils | MCP |
  | --- | --- | --- | --- | --- |
  | Mac M1 Pro, `e4b` | 5,2 s | 12,3 s | 8,1 s | 11,0 s |
  | Cloud Run L4, `e4b` | 1,9 s | 4,3 s | 2,9 s | 5,0 s |
  | Cloud Run L4, `26b` | 17,8 s | 28,7 s* | 4,9 s | 5,8 s |

  *mesuré avec holzmarkt-infos.png (3,4 Mo). Le `26b` apporte de la qualité, pas de la vitesse : pour une démo rapide, rester sur `e4b`.
- `gemma4:e4b-mlx` (Apple Silicon, Ollama ≥ 0.31) : aucun gain sur M1 Pro (33,7 vs 34,5 tok/s en génération, prompt plus lent). Garder `gemma4:e4b` par défaut.
- Claude Code fonctionne sur Gemma 4 via l'API compatible Anthropic d'Ollama (`/v1/messages`) : `claude-code/claude-gemma4.sh`. Son prompt système fait ~16 400 tokens, d'où le contexte à 64k. Le script fixe `CLAUDE_CODE_AUTO_MODE_SERVER=0`, `CLAUDE_CODE_MAX_CONTEXT_TOKENS`, le mode `acceptEdits` (pas de mode auto : le classifieur serait Gemma) et filtre la ligne stderr `[claude-code:unrecognized_model]`, qu'aucun réglage ne coupe. Testé : lecture de code OK (2 tours, 8 s), modification multi-fichiers OK (5 tours, 50 s) mais logique générée parfois naïve.
- Jamais de secret dans le repo : clés perso dans `claude-code/claude.local.sh` ou `adk/.env.local` (ignorés par Git, motifs `*.local.sh` et `.env.*`).
- `gcloud run services proxy` s'arrête quand le service est redéployé : le relancer après chaque `deploy.sh`.
- Imports TypeScript avec extension `.js` (résolution `nodenext`).
- Code et commentaires : commentaires en français, identifiants en anglais.
- Commits : gitmoji + description courte en anglais, terminer par `Co-authored-by: Claude Code (TechTown)`.

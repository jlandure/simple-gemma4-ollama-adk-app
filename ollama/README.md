# Ollama + Gemma 4 sur Cloud Run GPU

Ollama 0.40.18 et Gemma 4 sur Cloud Run, avec un GPU NVIDIA L4 (24 Go de VRAM).

## Où stocker le modèle ?

La doc Google « [Best practices: AI inference on Cloud Run services with GPUs](https://cloud.google.com/run/docs/configuring/services/gpu-best-practices) » recommande l'image conteneur pour les modèles de moins de 10 Go, et Cloud Storage au-delà. Dans les deux cas, le modèle n'est **jamais** téléchargé depuis internet au démarrage.

| Mode | Modèles | Comment |
| --- | --- | --- |
| `STORAGE=image` | `e2b`, `e4b`, `12b` | `ollama pull` pendant le build ([cloudbuild.yaml](cloudbuild.yaml)), poids dans l'image Artifact Registry |
| `STORAGE=gcs` | `26b`, `31b` | `ollama pull` puis `gcloud storage rsync` vers `gs://jlandure-demos-ollama-models` ([cloudbuild-gcs.yaml](cloudbuild-gcs.yaml)), bucket monté en volume Cloud Storage FUSE en lecture seule sur `/models` |

Le mode `gcs` suit les recommandations réseau de Google : Direct VPC (réseau `default`, egress `all-traffic`), accès privé Google sur le sous-réseau et option FUSE `enable-buffered-read`. L'image est `ollama/ollama:0.40.18` telle quelle. Le script choisit le mode selon la taille du modèle ; `STORAGE=…` force l'autre.

## Déploiement

```bash
./deploy.sh
```

```bash
MODEL=gemma4:26b SERVICE=ollama-gemma4-26b ./deploy.sh
```

| Variable | Défaut | Rôle |
| --- | --- | --- |
| `MODEL` | `gemma4:e4b` | modèle Ollama |
| `SERVICE` | `ollama-gemma4` | nom du service Cloud Run |
| `STORAGE` | selon le modèle | `image` ou `gcs` |
| `GPU` | `true` | `false` pour une variante CPU |
| `SKIP_BUILD` | `false` | redéployer sans rebuild de l'image ni resync du bucket |
| `PROJECT`, `REGION`, `BUCKET` | `jlandure-demos`, `europe-west1`, `<projet>-ollama-models` | cible |

Chaque service : 1 GPU L4, 8 vCPU, 32 Gio, 4 requêtes en parallèle, 1 instance max, compte de service dédié `ollama-gemma4@` (lecture du bucket seulement), **pas d'accès public**.

| Modèle | Taille | Où |
| --- | --- | --- |
| `gemma4:e2b` | ~7 Go | CPU ou GPU, le plus rapide |
| `gemma4:e4b` (défaut) | ~10 Go | Mac et GPU L4 |
| `gemma4:12b` | ~8 Go | GPU L4 |
| `gemma4:26b` (MoE, 4B actifs) | ~18 Go | GPU L4, meilleure qualité pour un coût d'inférence proche d'un 4B |
| `gemma4:31b` | ~20 Go | GPU L4 (contexte limité) |

## Accès depuis le Mac

Les services sont privés : on passe par le proxy authentifié de `gcloud`, qui utilise ton compte Google.

```bash
gcloud run services proxy ollama-gemma4-26b --project jlandure-demos --region europe-west1 --port 11435
```

Puis, dans un autre terminal :

```bash
time OLLAMA_HOST=http://localhost:11435 ollama run gemma4:26b "traduis en anglais sans rien ajouter : Je suis heureux de déployer Gemma 4 sur un GPU serverless"
```

```bash
OLLAMA_HOST=http://localhost:11435 OLLAMA_MODEL=gemma4:26b npm --prefix ../adk run demo
```

## Avant une démo

Le premier appel charge le modèle en VRAM (10 à 18 Go). Avant de monter sur scène, garde une instance chaude et fais un premier appel :

```bash
gcloud run services update ollama-gemma4-26b --project jlandure-demos --region europe-west1 --min-instances 1
```

Après la démo, repasse à 0 : le GPU est facturé tant qu'une instance tourne.

```bash
gcloud run services update ollama-gemma4-26b --project jlandure-demos --region europe-west1 --min-instances 0
```

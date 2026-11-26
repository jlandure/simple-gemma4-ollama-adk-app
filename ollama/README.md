# Ollama + Gemma 4 sur Cloud Run

Image Ollama avec les poids de Gemma 4 embarqués, déployée sur Cloud Run GPU (NVIDIA L4, 24 Go de VRAM).

## Déploiement

```bash
./deploy.sh
```

Le script :

1. builde l'image avec Cloud Build ([cloudbuild.yaml](cloudbuild.yaml), timeout 1 h, le modèle est téléchargé pendant le build) ;
2. la pousse dans Artifact Registry (`europe-west1-docker.pkg.dev/jlandure-demos/cloud-run-source-deploy/ollama-gemma4:<taille>`) ;
3. déploie le service **privé** `ollama-gemma4` : 1 GPU L4, 8 vCPU, 32 Gio, 4 requêtes en parallèle, 1 instance max.

Variables : `PROJECT`, `REGION`, `MODEL`, `SERVICE`, `GPU`, `SKIP_BUILD=true` (redéployer sans rebuilder).

| Modèle | Taille | Où |
| --- | --- | --- |
| `gemma4:e2b` | ~7 Go | CPU ou GPU, le plus rapide |
| `gemma4:e4b` (défaut) | ~10 Go | Mac et GPU L4 |
| `gemma4:12b` | ~8 Go | GPU L4 |
| `gemma4:26b` (MoE, 4B actifs) | ~18 Go | GPU L4, meilleure qualité |
| `gemma4:31b` | ~20 Go | GPU L4 (contexte limité) |

```bash
MODEL=gemma4:26b SERVICE=ollama-gemma4-26b ./deploy.sh
GPU=false MODEL=gemma4:e2b SERVICE=ollama-gemma4-cpu ./deploy.sh
```

## Utilisation

Le service est privé : on passe par le proxy authentifié de `gcloud`.

```bash
gcloud run services proxy ollama-gemma4 --project jlandure-demos --region europe-west1 --port 11435
```

Puis, dans un autre terminal :

```bash
time OLLAMA_HOST=http://localhost:11435 ollama run gemma4:e4b "traduis en anglais sans rien ajouter : Je suis heureux de déployer Gemma 4 sur un GPU serverless"
```

```bash
OLLAMA_HOST=http://localhost:11435 npm --prefix ../adk run demo
```

## Avant une démo

Le démarrage à froid charge ~10 Go en VRAM. Pour une démo, gardez une instance chaude, puis remettez à 0 après (le GPU est facturé tant qu'une instance tourne) :

```bash
gcloud run services update ollama-gemma4 --project jlandure-demos --region europe-west1 --min-instances 1
```

```bash
gcloud run services update ollama-gemma4 --project jlandure-demos --region europe-west1 --min-instances 0
```

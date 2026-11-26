# Agent ADK + Gemma 4 (`adk/`)

Agent écrit avec [ADK pour TypeScript](https://github.com/google/adk-js) (`@google/adk`), qui utilise Gemma 4 servi par [Ollama](https://ollama.com/), sur le Mac ou sur Cloud Run GPU.

## Structure

```text
adk/
├── agents/gemma4_assistant/
│   ├── agent.ts        # rootAgent : LlmAgent + outils + MCP Context7
│   ├── ollama_llm.ts   # OllamaLlm : BaseLlm ADK -> API /api/chat d'Ollama
│   └── tools.ts        # FunctionTool : get_current_time, get_weather (Open-Meteo)
├── demo.ts             # démo scriptée en 4 étapes
├── images/             # images pour la démo multimodale
└── deploy.sh           # déploiement Cloud Run (adk deploy cloud_run)
```

### Les outils de l'agent

| Outil | Type | Rôle |
| --- | --- | --- |
| `get_current_time` | `FunctionTool` | heure dans un fuseau IANA |
| `get_weather` | `FunctionTool` | météo actuelle via Open-Meteo (sans clé) |
| `resolve-library-id`, `query-docs` | `MCPToolset` | documentation à jour via le serveur MCP distant [Context7](https://context7.com) (Streamable HTTP) |

Le serveur MCP Context7 marche sans clé. Pour des limites plus hautes, définir `CONTEXT7_API_KEY`.

### Pourquoi un `OllamaLlm` maison ?

ADK JS embarque `Gemini`, `ApigeeLlm`, `ChromeBuiltInLlm` et `Claude` (dans `@google/adk-integrations`), mais pas Ollama. La documentation recommande d'étendre `BaseLlm`, d'implémenter `generateContentAsync` et d'enregistrer la classe avec `LLMRegistry.register(...)`. C'est ce que fait [ollama_llm.ts](agents/gemma4_assistant/ollama_llm.ts), qui gère :

- texte, images (multimodal) et instruction système ;
- appels de fonctions (tools), y compris plusieurs appels en parallèle ;
- streaming (ADK Web) et mode « thinking » de Gemma 4 (`OLLAMA_THINK=true`) ;
- sortie structurée (`outputSchema` -> `format` d'Ollama) ;
- authentification par ID token quand Ollama est un service Cloud Run privé.

Une fois le module importé, on peut aussi écrire `model: 'ollama/gemma4:e4b'` dans un `LlmAgent`.

## Prérequis

- Node.js 22 ou plus
- Ollama avec Gemma 4 : `ollama pull gemma4:e4b`

```bash
npm install
```

Le projet contient un `.npmrc` qui force le registre npm public.

## En local sur le Mac

```bash
npm run demo     # traduction, image, heure + météo à Las Vegas, MCP Context7
```

```bash
npm run demo -- images/tour-eiffel.jpg   # avec une autre image
```

```bash
npm run web      # ADK Web UI sur http://localhost:8000
```

```bash
npm run chat     # conversation dans le terminal
```

Variables d'environnement (voir [.env.example](.env.example)) : `OLLAMA_HOST`, `OLLAMA_MODEL`, `OLLAMA_THINK`, `CONTEXT7_API_KEY`, `DEMO_IMAGE`.

Sur Apple Silicon, la variante `gemma4:e4b-mlx` (Ollama ≥ 0.31) est plus rapide :

```bash
OLLAMA_MODEL=gemma4:e4b-mlx npm run demo
```

## Avec Ollama sur Cloud Run

Les services Ollama sont privés. Le proxy `gcloud` les expose sur ton Mac en s'authentifiant avec ton compte Google :

```bash
gcloud run services proxy ollama-gemma4-26b --project jlandure-demos --region europe-west1 --port 11435
```

```bash
OLLAMA_HOST=http://localhost:11435 OLLAMA_MODEL=gemma4:26b npm run demo
```

## Déployer l'agent sur Cloud Run

```bash
MODEL=gemma4:26b OLLAMA_SERVICE=ollama-gemma4-26b ./deploy.sh
```

Le script :

1. crée le compte de service `gemma4-adk-agent` ;
2. lui donne `roles/run.invoker` sur le service Ollama ciblé, et rien d'autre ;
3. lance `adk deploy cloud_run --with_ui` avec `OLLAMA_HOST` et `OLLAMA_MODEL`.

Sur Cloud Run, `OllamaLlm` voit que `OLLAMA_HOST` est une URL `https://*.run.app` et ajoute un ID token obtenu auprès du serveur de métadonnées : aucune clé à gérer.

## Sécurité et accès

| Service | Qui peut l'appeler |
| --- | --- |
| `ollama-gemma4`, `ollama-gemma4-26b` | le compte de service `gemma4-adk-agent`, et toi via `gcloud run services proxy` |
| `gemma4-adk-agent` | toi via `gcloud run services proxy` (ou tout le monde avec `PUBLIC=true ./deploy.sh`) |

Rien n'est public par défaut : un endpoint GPU ouvert peut être utilisé par n'importe qui, à tes frais. Pour ouvrir l'UI ADK de l'agent déployé :

```bash
gcloud run services proxy gemma4-adk-agent --project jlandure-demos --region europe-west1 --port 8080
```

Puis ouvrir http://localhost:8080/dev-ui/.

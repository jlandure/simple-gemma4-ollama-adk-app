# Agent ADK + Gemma 4 (`adk/`)

Agent écrit avec [ADK pour TypeScript](https://github.com/google/adk-js) (`@google/adk`), qui utilise Gemma 4 servi par [Ollama](https://ollama.com/), sur le Mac ou sur Cloud Run GPU.

## Structure

```text
adk/
├── agents/gemma4_assistant/
│   ├── agent.ts        # rootAgent : LlmAgent + instructions + outils
│   ├── ollama_llm.ts   # OllamaLlm : BaseLlm ADK -> API /api/chat d'Ollama
│   └── tools.ts        # FunctionTool : get_current_time, get_weather (Open-Meteo)
├── demo.ts             # démo scriptée : traduction, image, function calling
├── holzmarkt-infos.png
└── deploy.sh           # déploiement Cloud Run (adk deploy cloud_run)
```

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
npm run demo     # traduction + description d'image + outils
```

```bash
npm run web      # ADK Web UI sur http://localhost:8000
```

```bash
npm run chat     # conversation dans le terminal
```

Variables d'environnement (voir [.env.example](.env.example)) : `OLLAMA_HOST`, `OLLAMA_MODEL`, `OLLAMA_THINK`.

## Avec Ollama sur Cloud Run

```bash
gcloud run services proxy ollama-gemma4 --project jlandure-demos --region europe-west1 --port 11435
```

```bash
OLLAMA_HOST=http://localhost:11435 npm run demo
```

## Déployer l'agent sur Cloud Run

```bash
./deploy.sh
```

Le script crée un compte de service `gemma4-adk-agent`, lui donne `roles/run.invoker` sur le service Ollama, puis lance `adk deploy cloud_run --with_ui` avec `OLLAMA_HOST` pointant vers Ollama. L'agent obtient son ID token via le serveur de métadonnées.

Le service est privé par défaut. Pour ouvrir l'UI ADK :

```bash
gcloud run services proxy gemma4-adk-agent --project jlandure-demos --region europe-west1 --port 8080
```

Puis ouvrir http://localhost:8080/dev-ui/.

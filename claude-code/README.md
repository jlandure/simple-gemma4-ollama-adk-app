# Démo : Claude Code sur Gemma 4 (Cloud Run GPU)

Faire tourner **Claude Code** (l'agent de code en terminal d'Anthropic) avec **Gemma 4** comme modèle, servi par **Ollama** sur **Cloud Run GPU**, au lieu des modèles Claude.

```text
 claude (terminal)
   │  API Messages d'Anthropic
   ▼
 localhost:11435 ── gcloud run services proxy (ton compte Google) ──▶ Cloud Run "ollama-gemma4"
                                                                     Ollama /v1/messages
                                                                     gemma4:e4b sur NVIDIA L4
```

## Pourquoi ça marche

- Claude Code accepte une autre URL d'API avec `ANTHROPIC_BASE_URL`.
- Ollama expose une API compatible Anthropic sur `/v1/messages` : texte, streaming et appels d'outils.
- Le service Ollama est privé ; `gcloud run services proxy` s'occupe de l'authentification.
- Le contexte d'Ollama est réglé à **65 536 tokens** : le prompt système et les définitions d'outils de Claude Code dépassent à eux seuls 16 000 tokens.

## Prérequis

- Claude Code installé (`claude --version`).
- `gcloud` connecté avec un compte qui a `roles/run.invoker` sur `ollama-gemma4` (projet `jlandure-demos`).
- Le service `ollama-gemma4` déployé avec 64k de contexte : `./ollama/deploy.sh` (défaut).

## Lancer la démo avec un `claude` normal (recommandé)

Dans ton terminal, depuis la racine du repo :

```bash
source claude-code/claude.sh
```

```bash
cd adk && claude -p "Liste les outils définis dans agents/gemma4_assistant/tools.ts"
```

`source` exporte les variables ci-dessous dans **ce terminal uniquement** et ouvre le proxy `gcloud` s'il ne tourne pas. `claude` et `claude -p` utilisent ensuite Gemma 4. Pour revenir aux modèles Claude dans le même terminal :

```bash
claude_gemma4_off
```

**Aucun secret dans [claude.sh](claude.sh)** : `ANTHROPIC_AUTH_TOKEN=ollama` est un jeton factice qu'Ollama ne vérifie pas, et une éventuelle vraie `ANTHROPIC_API_KEY` est mise de côté (vidée pour ne jamais partir vers Ollama) puis restaurée par `claude_gemma4_off`. Tes réglages ou clés perso vont dans `claude-code/claude.local.sh`, ignoré par Git et chargé automatiquement (modèle : [claude.local.sh.example](claude.local.sh.example)).

Options (à exporter avant le `source`) : `GEMMA_MODEL`, `GEMMA_SERVICE`, `GEMMA_PORT`, `GEMMA_CONTEXT`, `GEMMA_PROJECT`, `GEMMA_REGION`, `GEMMA_PERMISSION_MODE`, `GEMMA_LOCAL=true`.

`claude` est lancé en `--permission-mode acceptEdits` (les éditions de fichiers sont validées, les commandes demandent confirmation) plutôt qu'en mode auto, dont le classifieur de sécurité serait Gemma lui-même. Un `--permission-mode` passé explicitement reste prioritaire ; `GEMMA_PERMISSION_MODE` change le défaut.

## Variante : le lanceur tout-en-un

```bash
cd adk
```

```bash
../claude-code/claude-gemma4.sh
```

Le script ouvre le proxy `gcloud` s'il ne tourne pas déjà, règle les variables ci-dessous puis lance `claude`. Tous les arguments sont passés à `claude`.

| Variable | Valeur | Rôle |
| --- | --- | --- |
| `ANTHROPIC_BASE_URL` | `http://localhost:11435` | envoie les requêtes à Ollama via le proxy |
| `ANTHROPIC_AUTH_TOKEN` | `ollama` | jeton factice (Ollama ne le vérifie pas) |
| `ANTHROPIC_API_KEY` | vide | évite d'utiliser une vraie clé Anthropic |
| `ANTHROPIC_MODEL`, `ANTHROPIC_DEFAULT_*_MODEL`, `CLAUDE_CODE_SUBAGENT_MODEL` | `gemma4:e4b` | tous les rôles (principal, rapide, sous-agents) utilisent Gemma 4 |
| `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` | `1` | pas d'appels annexes vers Anthropic |
| `CLAUDE_CODE_MAX_CONTEXT_TOKENS` | `65536` | taille réelle du contexte, que Claude Code ne peut pas deviner pour ce modèle |
| `CLAUDE_CODE_AUTO_MODE_SERVER` | `0` | supprime l'avertissement « auto mode … classifier requests are billed as before » (Ollama n'implémente pas les safeguards serveur du mode auto) |

Le script lance aussi Claude Code en `--permission-mode acceptEdits` (modifiable avec `PERMISSION_MODE=manual`, ou en passant `--permission-mode` toi-même) : en mode auto, le classifieur de sécurité qui valide les actions serait Gemma 4 lui-même, ce qui n'est pas fiable. Enfin, il filtre la ligne `[claude-code:unrecognized_model]` que Claude Code écrit sur stderr pour tout modèle non-Claude, faute de réglage pour la couper.

Options du script : `MODEL`, `SERVICE`, `PORT`, `PROJECT`, `REGION`, `PERMISSION_MODE`, `CONTEXT_LENGTH`, et `LOCAL=true` pour utiliser l'Ollama du Mac.

## Scénario de démo

Dans le dossier `adk/` :

1. « Explique ce que fait ce projet en 5 lignes. » : Claude Code lit les fichiers avec ses outils `Read` / `Glob`.
2. « Que fait la classe OllamaLlm ? » : lecture ciblée de `agents/gemma4_assistant/ollama_llm.ts`.
3. « Ajoute un outil get_moon_phase dans tools.ts. » : Claude Code propose une modification, que tu valides.

Le mode non interactif marche aussi :

```bash
../claude-code/claude-gemma4.sh -p "Liste les outils de l'agent dans agents/gemma4_assistant/tools.ts" --allowedTools "Read,Glob,Grep"
```

## En local sur le Mac

```bash
LOCAL=true ../claude-code/claude-gemma4.sh
```

Augmente d'abord le contexte d'Ollama sur le Mac (64k) : dans les réglages de l'app Ollama (« Context length »), ou en lançant le serveur avec `OLLAMA_CONTEXT_LENGTH=65536 ollama serve`.

## Ce qui a été testé (26/11/2026, Claude Code 2.1.318, Ollama 0.40.18, L4)

| Test | Tours | Durée | Résultat |
| --- | --- | --- | --- |
| « Liste les outils de tools.ts » (outils `Read`, `Glob`, `Grep`) | 2 | 7,8 s (51 s au tout premier appel) | réponse juste |
| « Ajoute un FunctionTool get_moon_phase et branche-le dans agent.ts » (`acceptEdits`) | 5 | 50 s | 2 fichiers modifiés, `tsc` OK, mais calcul de la lune naïf (basé sur le jour du mois) |

Le prompt envoyé par Claude Code pèse environ **16 400 tokens** avant même la question : avec l'ancien réglage de 16 384 tokens, il était tronqué.

## Limites à annoncer

- **Gemma 4 e4b n'est pas Claude** : très bien pour lire et expliquer du code ; il sait modifier plusieurs fichiers, mais la qualité de la logique générée est inégale (voir la phase de lune ci-dessus, un bon exemple à montrer). Le `gemma4:26b` (`SERVICE=ollama-gemma4-26b PORT=11436 MODEL=gemma4:26b`) est plus solide, mais plus lent et limité en contexte sur une L4.
- Le premier appel après un déploiement charge le modèle en VRAM (environ 4 minutes) : chauffer le service avant de monter sur scène.
- Les fonctions propres aux modèles Claude (cache de prompt, recherche web côté serveur, etc.) ne sont pas disponibles.

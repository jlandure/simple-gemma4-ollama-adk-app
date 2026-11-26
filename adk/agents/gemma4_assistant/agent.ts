/**
 * Agent ADK propulsé par Gemma 4, servi par Ollama
 * (en local sur le Mac, ou sur Cloud Run GPU).
 *
 *   npm run web    -> ADK Web UI (http://localhost:8000)
 *   npm run chat   -> conversation dans le terminal
 *   npm run demo   -> traduction + description d'image + appels d'outils
 */
import {getLogger, LlmAgent, MCPToolset, setLogger, type Logger} from '@google/adk';
import {OllamaLlm} from './ollama_llm.js';
import {getCurrentTime, getWeather} from './tools.js';

export const MODEL = process.env.OLLAMA_MODEL ?? 'gemma4:e4b';

// ADK ferme la session MCP après chaque appel, ce qui coupe le flux SSE et logue
// une fausse erreur "MCP transport error: ... aborted". On ne masque que celle-là.
const adkLogger = getLogger();
const isMcpAbort = (args: unknown[]) =>
  /MCP transport error: .*abort/i.test(args.map(String).join(' '));
setLogger({
  log: (level, ...args) => adkLogger.log(level, ...args),
  debug: (...args) => adkLogger.debug(...args),
  info: (...args) => adkLogger.info(...args),
  warn: (...args) => adkLogger.warn(...args),
  error: (...args) => (isMcpAbort(args) ? adkLogger.debug(...args) : adkLogger.error(...args)),
  setLogLevel: (level) => adkLogger.setLogLevel(level),
} satisfies Logger);

// Serveur MCP distant Context7 (doc à jour des librairies), en Streamable HTTP.
// Clé optionnelle (limites plus hautes) : https://context7.com/dashboard
const context7ApiKey = process.env.CONTEXT7_API_KEY;
export const context7 = new MCPToolset({
  type: 'StreamableHTTPConnectionParams',
  url: process.env.CONTEXT7_MCP_URL ?? 'https://mcp.context7.com/mcp',
  ...(context7ApiKey && {
    transportOptions: {requestInit: {headers: {CONTEXT7_API_KEY: context7ApiKey}}},
  }),
});

export const rootAgent = new LlmAgent({
  name: 'gemma4_assistant',
  description: 'Assistant multimodal et multilingue propulsé par Gemma 4 via Ollama.',
  model: new OllamaLlm({model: MODEL}),
  instruction: `You are a friendly assistant running on Gemma 4 (open model by Google DeepMind), served by Ollama.
- Answer in the user's language unless they ask for a translation.
- When asked to translate, return only the translation, with no extra text.
- When given an image, describe it precisely (layout, text, colors, purpose).
- Use the get_current_time tool for any question about the current time or date.
- Use the get_weather tool for any question about the weather. Never invent weather data.
- For any question about a library, SDK, framework or its latest version, use the Context7 tools:
  first resolve-library-id to find the library ID, then query-docs with that ID. Never guess versions.
  For Google products, prefer official library IDs starting with /google/ or /websites/adk_dev.
  Versions, when known, are listed in the "Versions" field of resolve-library-id results.
- Keep answers concise.`,
  tools: [getCurrentTime, getWeather, context7],
  generateContentConfig: {temperature: 0.2},
});

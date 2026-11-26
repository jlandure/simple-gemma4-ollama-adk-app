/**
 * Agent ADK propulsé par Gemma 4, servi par Ollama
 * (en local sur le Mac, ou sur Cloud Run GPU).
 *
 *   npm run web    -> ADK Web UI (http://localhost:8000)
 *   npm run chat   -> conversation dans le terminal
 *   npm run demo   -> traduction + description d'image + appels d'outils
 */
import {LlmAgent} from '@google/adk';
import {OllamaLlm} from './ollama_llm.js';
import {getCurrentTime, getWeather} from './tools.js';

export const MODEL = process.env.OLLAMA_MODEL ?? 'gemma4:e4b';

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
- Keep answers concise.`,
  tools: [getCurrentTime, getWeather],
  generateContentConfig: {temperature: 0.2},
});

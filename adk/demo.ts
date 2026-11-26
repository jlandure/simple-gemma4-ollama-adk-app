/**
 * Démo scriptée (équivalent du index.js LangChain de la version Gemma 3) :
 *   1. traduction FR -> EN
 *   2. description d'une capture d'écran (multimodal)
 *   3. function calling : heure + météo via les outils ADK
 *
 * Usage : npm run demo
 *         OLLAMA_HOST=http://localhost:11435 npm run demo   # via le proxy Cloud Run
 */
import {InMemoryRunner, isFinalResponse, type Event} from '@google/adk';
import type {Content} from '@google/genai';
import * as fs from 'node:fs/promises';
import {MODEL, rootAgent} from './agents/gemma4_assistant/agent.js';

const runner = new InMemoryRunner({agent: rootAgent, appName: 'gemma4_demo'});

async function ask(title: string, message: Content): Promise<string> {
  console.log(`\n=== ${title} ===`);
  const start = performance.now();
  let answer = '';
  for await (const event of runner.runEphemeral({userId: 'demo', newMessage: message})) {
    logToolActivity(event);
    if (event.errorCode) throw new Error(`${event.errorCode}: ${event.errorMessage}`);
    if (isFinalResponse(event)) {
      answer = (event.content?.parts ?? [])
        .filter((p) => p.text && !p.thought)
        .map((p) => p.text)
        .join('');
    }
  }
  console.log(answer);
  console.log(`(${((performance.now() - start) / 1000).toFixed(1)} s)`);
  return answer;
}

function logToolActivity(event: Event) {
  for (const part of event.content?.parts ?? []) {
    if (part.functionCall) {
      console.log(`  -> ${part.functionCall.name}(${JSON.stringify(part.functionCall.args)})`);
    }
    if (part.functionResponse) {
      console.log(`  <- ${part.functionResponse.name}: ${JSON.stringify(part.functionResponse.response)}`);
    }
  }
}

console.log(`Modèle : ${MODEL} @ ${process.env.OLLAMA_HOST ?? 'http://localhost:11434'}`);

await ask('Traduction', {
  role: 'user',
  parts: [
    {
      text:
        'Translate the following from French into English. Just the translation, no other text:\n' +
        'Bonjour, je suis ravi de vous présenter Gemma 4 avec ADK, en local sur mon Mac puis sur Cloud Run GPU !',
    },
  ],
});

const image = await fs.readFile(new URL('./holzmarkt-infos.png', import.meta.url));
await ask('Description d’image', {
  role: 'user',
  parts: [
    {text: 'What do you see in this webpage? Describe it in English. Be detailed and precise.'},
    {inlineData: {mimeType: 'image/png', data: image.toString('base64')}},
  ],
});

await ask('Function calling', {
  role: 'user',
  parts: [{text: 'Quelle heure est-il à Tokyo et quel temps fait-il à Nantes en ce moment ?'}],
});

await runner.close();

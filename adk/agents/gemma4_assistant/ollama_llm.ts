/**
 * OllamaLlm — connecteur ADK (BaseLlm) vers l'API /api/chat d'Ollama.
 *
 * ADK pour TypeScript n'a pas (encore) d'intégration Ollama native : la bonne
 * pratique documentée est d'étendre `BaseLlm`, d'implémenter
 * `generateContentAsync` et d'enregistrer la classe dans `LLMRegistry`.
 *
 * Gère : instructions système, texte, images (multimodal), appels de fonctions
 * (tools), streaming, mode "thinking" de Gemma 4 et sortie JSON structurée.
 *
 * Si OLLAMA_HOST pointe vers un service Cloud Run privé (https://*.run.app),
 * un ID token Google est ajouté automatiquement (compte de service de
 * l'instance Cloud Run, ou OLLAMA_ID_TOKEN en local).
 */
import {
  BaseLlm,
  BaseLlmConnection,
  LLMRegistry,
  LlmRequest,
  LlmResponse,
} from '@google/adk';
import type {Content, GenerateContentConfig, Part} from '@google/genai';
import {GoogleAuth} from 'google-auth-library';

type JsonObject = Record<string, unknown>;

interface OllamaToolCall {
  function: {name: string; arguments?: JsonObject};
}

interface OllamaMessage {
  role: 'system' | 'user' | 'assistant' | 'tool';
  content: string;
  images?: string[];
  tool_calls?: OllamaToolCall[];
  tool_name?: string;
}

interface OllamaChunk {
  message?: {content?: string; thinking?: string; tool_calls?: OllamaToolCall[]};
  done?: boolean;
  done_reason?: string;
  prompt_eval_count?: number;
  eval_count?: number;
  error?: string;
}

export interface OllamaLlmOptions {
  /** Nom du modèle Ollama, avec ou sans préfixe `ollama/` (ex. `gemma4:e4b`). */
  model: string;
  /** URL du serveur Ollama. Défaut : $OLLAMA_HOST ou http://localhost:11434. */
  host?: string;
  /** Active le raisonnement ("thinking") de Gemma 4. Défaut : $OLLAMA_THINK === 'true'. */
  think?: boolean;
  /** Durée de maintien du modèle en mémoire (ex. '30m', -1). */
  keepAlive?: string | number;
}

export class OllamaLlm extends BaseLlm {
  /** Permet `model: 'ollama/gemma4:e4b'` dans un LlmAgent. */
  static override readonly supportedModels = [/^ollama\/.+/];

  readonly host: string;
  private readonly think: boolean;
  private readonly keepAlive?: string | number;
  private auth?: GoogleAuth;

  constructor({model, host, think, keepAlive}: OllamaLlmOptions) {
    super({model: model.replace(/^ollama\//, '')});
    this.host = normalizeHost(
      host ?? process.env.OLLAMA_HOST ?? 'http://localhost:11434',
    );
    this.think = think ?? process.env.OLLAMA_THINK === 'true';
    this.keepAlive = keepAlive;
  }

  async *generateContentAsync(
    llmRequest: LlmRequest,
    stream = false,
    abortSignal?: AbortSignal,
  ): AsyncGenerator<LlmResponse, void> {
    const config = llmRequest.config;
    const body = {
      model: this.model,
      messages: toOllamaMessages(llmRequest),
      tools: toOllamaTools(config),
      format: toOllamaFormat(config),
      options: toOllamaOptions(config),
      think: this.think,
      keep_alive: this.keepAlive,
      stream,
    };

    let res: Response;
    try {
      res = await fetch(`${this.host}/api/chat`, {
        method: 'POST',
        headers: await this.headers(),
        body: JSON.stringify(body),
        signal: abortSignal,
      });
    } catch (e) {
      yield errorResponse('OLLAMA_UNREACHABLE', `${this.host}: ${(e as Error).message}`);
      return;
    }
    if (!res.ok || !res.body) {
      yield errorResponse(String(res.status), await res.text());
      return;
    }

    let text = '';
    let thinking = '';
    const toolCalls: OllamaToolCall[] = [];
    let last: OllamaChunk = {};

    for await (const chunk of readNdjson(res.body)) {
      if (chunk.error) {
        yield errorResponse('OLLAMA_ERROR', chunk.error);
        return;
      }
      const msg = chunk.message ?? {};
      if (msg.thinking) {
        thinking += msg.thinking;
        if (stream) yield partial({text: msg.thinking, thought: true});
      }
      if (msg.content) {
        text += msg.content;
        if (stream) yield partial({text: msg.content});
      }
      if (msg.tool_calls) toolCalls.push(...msg.tool_calls);
      if (chunk.done) last = chunk;
    }

    const parts: Part[] = [];
    if (thinking) parts.push({text: thinking, thought: true});
    if (text) parts.push({text});
    for (const call of toolCalls) {
      parts.push({
        functionCall: {name: call.function.name, args: call.function.arguments ?? {}},
      });
    }
    if (parts.length === 0) parts.push({text: ''});

    const promptTokenCount = last.prompt_eval_count ?? 0;
    const candidatesTokenCount = last.eval_count ?? 0;
    yield {
      content: {role: 'model', parts},
      partial: false,
      turnComplete: true,
      finishReason: (last.done_reason === 'length'
        ? 'MAX_TOKENS'
        : 'STOP') as LlmResponse['finishReason'],
      usageMetadata: {
        promptTokenCount,
        candidatesTokenCount,
        totalTokenCount: promptTokenCount + candidatesTokenCount,
      },
      modelVersion: this.model,
    };
  }

  async connect(_llmRequest: LlmRequest): Promise<BaseLlmConnection> {
    throw new Error(`Live (bidi) connection is not supported for Ollama model ${this.model}.`);
  }

  /** En-têtes HTTP, avec ID token si Ollama tourne sur un Cloud Run privé. */
  private async headers(): Promise<Record<string, string>> {
    const headers: Record<string, string> = {'Content-Type': 'application/json'};
    const url = new URL(this.host);
    const isCloudRun = url.protocol === 'https:' && url.hostname.endsWith('.run.app');
    if (!isCloudRun || process.env.OLLAMA_AUTH === 'none') return headers;

    let token = process.env.OLLAMA_ID_TOKEN;
    if (!token) {
      this.auth ??= new GoogleAuth();
      const client = await this.auth.getIdTokenClient(url.origin);
      token = await client.idTokenProvider.fetchIdToken(url.origin);
    }
    headers.Authorization = `Bearer ${token}`;
    return headers;
  }
}

LLMRegistry.register(OllamaLlm);

// ---------------------------------------------------------------------------
// Conversion ADK (format Gemini `Content`) -> Ollama
// ---------------------------------------------------------------------------

function toOllamaMessages(llmRequest: LlmRequest): OllamaMessage[] {
  const messages: OllamaMessage[] = [];
  const system = contentText(llmRequest.config?.systemInstruction);
  if (system) messages.push({role: 'system', content: system});

  for (const content of llmRequest.contents) {
    const texts: string[] = [];
    const images: string[] = [];
    const toolCalls: OllamaToolCall[] = [];

    for (const part of content.parts ?? []) {
      if (part.thought) continue; // on ne renvoie pas le raisonnement au modèle
      if (part.text) {
        texts.push(part.text);
      } else if (part.inlineData?.data && part.inlineData.mimeType?.startsWith('image/')) {
        images.push(part.inlineData.data);
      } else if (part.functionCall?.name) {
        toolCalls.push({
          function: {name: part.functionCall.name, arguments: part.functionCall.args ?? {}},
        });
      } else if (part.functionResponse?.name) {
        messages.push({
          role: 'tool',
          tool_name: part.functionResponse.name,
          content: JSON.stringify(part.functionResponse.response ?? {}),
        });
      }
    }

    if (texts.length || images.length || toolCalls.length) {
      messages.push({
        role: content.role === 'model' ? 'assistant' : 'user',
        content: texts.join('\n'),
        ...(images.length && {images}),
        ...(toolCalls.length && {tool_calls: toolCalls}),
      });
    }
  }
  return messages;
}

function toOllamaTools(config?: GenerateContentConfig) {
  const declarations = (config?.tools ?? []).flatMap((tool) =>
    'functionDeclarations' in tool && tool.functionDeclarations ? tool.functionDeclarations : [],
  );
  if (declarations.length === 0) return undefined;
  return declarations.map((d) => ({
    type: 'function',
    function: {
      name: d.name,
      description: d.description ?? '',
      parameters: d.parametersJsonSchema ??
        toJsonSchema(d.parameters) ?? {type: 'object', properties: {}},
    },
  }));
}

function toOllamaFormat(config?: GenerateContentConfig) {
  if (config?.responseJsonSchema) return config.responseJsonSchema;
  if (config?.responseSchema) return toJsonSchema(config.responseSchema);
  if (config?.responseMimeType === 'application/json') return 'json';
  return undefined;
}

function toOllamaOptions(config?: GenerateContentConfig) {
  if (!config) return undefined;
  const options: JsonObject = {
    temperature: config.temperature,
    top_p: config.topP,
    top_k: config.topK,
    num_predict: config.maxOutputTokens,
    stop: config.stopSequences,
    seed: config.seed,
  };
  for (const key of Object.keys(options)) {
    if (options[key] === undefined) delete options[key];
  }
  return Object.keys(options).length ? options : undefined;
}

/** Schéma Gemini (`type: 'OBJECT'`) -> JSON Schema (`type: 'object'`). */
function toJsonSchema(schema: unknown): unknown {
  if (schema === undefined || schema === null) return undefined;
  if (Array.isArray(schema)) return schema.map(toJsonSchema);
  if (typeof schema !== 'object') return schema;
  const out: JsonObject = {};
  for (const [key, value] of Object.entries(schema)) {
    if (value === undefined || value === null) continue;
    out[key] = key === 'type' && typeof value === 'string' ? value.toLowerCase() : toJsonSchema(value);
  }
  return out;
}

function contentText(instruction: unknown): string {
  if (!instruction) return '';
  if (typeof instruction === 'string') return instruction;
  if (Array.isArray(instruction)) return instruction.map(contentText).join('\n');
  const obj = instruction as Content & Part;
  if (obj.parts) return obj.parts.map((p) => p.text ?? '').join('\n');
  return obj.text ?? '';
}

// ---------------------------------------------------------------------------
// Utilitaires
// ---------------------------------------------------------------------------

function normalizeHost(host: string): string {
  const withScheme = /^https?:\/\//.test(host) ? host : `http://${host}`;
  return withScheme.replace(/\/+$/, '');
}

function partial(part: Part): LlmResponse {
  return {content: {role: 'model', parts: [part]}, partial: true};
}

function errorResponse(errorCode: string, errorMessage: string): LlmResponse {
  return {errorCode, errorMessage, turnComplete: true};
}

/** Lit une réponse NDJSON (streaming) ou JSON simple (non streaming). */
async function* readNdjson(body: ReadableStream<Uint8Array>): AsyncGenerator<OllamaChunk> {
  const decoder = new TextDecoder();
  let buffer = '';
  for await (const bytes of body as unknown as AsyncIterable<Uint8Array>) {
    buffer += decoder.decode(bytes, {stream: true});
    let newline: number;
    while ((newline = buffer.indexOf('\n')) >= 0) {
      const line = buffer.slice(0, newline).trim();
      buffer = buffer.slice(newline + 1);
      if (line) yield JSON.parse(line) as OllamaChunk;
    }
  }
  if (buffer.trim()) yield JSON.parse(buffer) as OllamaChunk;
}

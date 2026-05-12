import { describe, it, expect } from "vitest";
import { MiniMaxClient, rerankWithTimeout } from "../src/ai/minimaxClient.js";
import { DEFAULT_INSTRUCTION } from "../src/ai/llmClient.js";

function baseReq() {
  return {
    compressedTokens: ["i", "wa"],
    wordCandidates: [{ token: "i", selected: "i", candidates: ["i"], confidence: 1 }],
    contextBefore: "",
    contextAfter: "",
    domain: "general",
    instruction: DEFAULT_INSTRUCTION,
  };
}

describe("MiniMaxClient", () => {
  it("reports unavailable when no baseUrl is configured", () => {
    const c = new MiniMaxClient({ baseUrl: undefined, apiKey: undefined, model: "x", timeoutMs: 200 });
    expect(c.available()).toBe(false);
  });

  it("returns null when the adapter is not configured", async () => {
    const c = new MiniMaxClient({ baseUrl: undefined, apiKey: undefined, model: "x", timeoutMs: 200 });
    const r = await c.rerank(baseReq(), new AbortController().signal);
    expect(r).toBeNull();
  });

  it("parses an OpenAI-style chat completion JSON content", async () => {
    const mockFetch = (async () =>
      new Response(JSON.stringify({
        choices: [
          { message: { content: JSON.stringify({ prediction: "i want", alternatives: ["i went"] }) } },
        ],
      }), { status: 200 })) as unknown as typeof fetch;
    const c = new MiniMaxClient({
      baseUrl: "http://mock.local", apiKey: "k", model: "abab", timeoutMs: 200, fetchImpl: mockFetch,
    });
    const r = await c.rerank(baseReq(), new AbortController().signal);
    expect(r?.prediction).toBe("i want");
    expect(r?.alternatives).toEqual(["i went"]);
  });

  it("also accepts MiniMax's `reply` field shape", async () => {
    const mockFetch = (async () =>
      new Response(JSON.stringify({
        reply: JSON.stringify({ prediction: "the quick brown fox" }),
      }), { status: 200 })) as unknown as typeof fetch;
    const c = new MiniMaxClient({
      baseUrl: "http://mock.local", apiKey: undefined, model: "abab", timeoutMs: 200, fetchImpl: mockFetch,
    });
    const r = await c.rerank(baseReq(), new AbortController().signal);
    expect(r?.prediction).toBe("the quick brown fox");
  });

  it("returns null on non-2xx", async () => {
    const mockFetch = (async () => new Response("err", { status: 500 })) as unknown as typeof fetch;
    const c = new MiniMaxClient({
      baseUrl: "http://mock.local", apiKey: undefined, model: "abab", timeoutMs: 200, fetchImpl: mockFetch,
    });
    const r = await c.rerank(baseReq(), new AbortController().signal);
    expect(r).toBeNull();
  });

  it("returns null on invalid JSON content", async () => {
    const mockFetch = (async () =>
      new Response(JSON.stringify({ choices: [{ message: { content: "not json" } }] }), { status: 200 })) as unknown as typeof fetch;
    const c = new MiniMaxClient({
      baseUrl: "http://mock.local", apiKey: undefined, model: "abab", timeoutMs: 200, fetchImpl: mockFetch,
    });
    const r = await c.rerank(baseReq(), new AbortController().signal);
    expect(r).toBeNull();
  });

  it("aborts at 200ms timeout via rerankWithTimeout", async () => {
    const mockFetch = ((_url: unknown, init?: { signal?: AbortSignal }) =>
      new Promise<Response>((_resolve, reject) => {
        init?.signal?.addEventListener("abort", () => reject(new Error("aborted")));
      })) as unknown as typeof fetch;
    const c = new MiniMaxClient({
      baseUrl: "http://mock.local", apiKey: undefined, model: "abab", timeoutMs: 50, fetchImpl: mockFetch,
    });
    const start = Date.now();
    const r = await rerankWithTimeout(c, baseReq(), 50);
    const elapsed = Date.now() - start;
    expect(r).toBeNull();
    expect(elapsed).toBeLessThan(400); // some headroom for slow CI
  });

  it("sets Authorization header when apiKey is present", async () => {
    let captured: Record<string, string> = {};
    const mockFetch = (async (_url: unknown, init?: { headers?: Record<string, string> }) => {
      captured = init?.headers ?? {};
      return new Response(JSON.stringify({ choices: [{ message: { content: JSON.stringify({ prediction: "x" }) } }] }), { status: 200 });
    }) as unknown as typeof fetch;
    const c = new MiniMaxClient({
      baseUrl: "http://mock.local", apiKey: "tok", model: "abab", timeoutMs: 200, fetchImpl: mockFetch,
    });
    await c.rerank(baseReq(), new AbortController().signal);
    expect(captured.authorization).toBe("Bearer tok");
  });
});

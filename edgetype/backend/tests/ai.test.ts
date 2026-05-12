import { describe, it, expect, beforeEach } from "vitest";
import { callAI, type AIClientConfig } from "../src/ai/client.js";
import { resetCandidatesCache } from "../src/prediction/candidates.js";
import { resetDictionaryCache } from "../src/prediction/dictionary.js";

beforeEach(() => {
  resetCandidatesCache();
  resetDictionaryCache();
});

const wordCandidates = [
  { token: "te", candidates: ["the", "time"] },
  { token: "qk", candidates: ["quick"] },
];

function configWithFetch(fetchImpl: typeof fetch): AIClientConfig {
  return {
    baseUrl: "http://mock.local",
    apiKey: undefined,
    timeoutMs: 150,
    fetchImpl,
  };
}

describe("callAI", () => {
  it("returns null when baseUrl is unset", async () => {
    const result = await callAI(["te", "qk"], wordCandidates, "", {
      baseUrl: undefined,
      apiKey: undefined,
      timeoutMs: 150,
    });
    expect(result).toBeNull();
  });

  it("returns the AI prediction on a 200 response", async () => {
    const mockFetch = (async () =>
      new Response(JSON.stringify({ prediction: "the quick", alternatives: ["time quick"] }), {
        status: 200,
        headers: { "content-type": "application/json" },
      })) as unknown as typeof fetch;
    const result = await callAI(["te", "qk"], wordCandidates, "", configWithFetch(mockFetch));
    expect(result?.prediction).toBe("the quick");
    expect(result?.alternatives).toContain("time quick");
    expect(result?.mismatchedWords).toEqual([]);
  });

  it("flags mismatched words against the edge-letter constraint", async () => {
    const mockFetch = (async () =>
      new Response(JSON.stringify({ prediction: "the queen" }), {
        status: 200,
        headers: { "content-type": "application/json" },
      })) as unknown as typeof fetch;
    const result = await callAI(["te", "qk"], wordCandidates, "", configWithFetch(mockFetch));
    expect(result?.prediction).toBe("the queen");
    expect(result?.mismatchedWords).toEqual([1]); // "queen" doesn't end in k
  });

  it("falls back to null on non-2xx", async () => {
    const mockFetch = (async () => new Response("err", { status: 500 })) as unknown as typeof fetch;
    const result = await callAI(["te", "qk"], wordCandidates, "", configWithFetch(mockFetch));
    expect(result).toBeNull();
  });

  it("falls back to null on timeout", async () => {
    const mockFetch = ((_url: unknown, init?: { signal?: AbortSignal }) =>
      new Promise<Response>((_resolve, reject) => {
        init?.signal?.addEventListener("abort", () => reject(new Error("aborted")));
        // Never resolves — must abort.
      })) as unknown as typeof fetch;
    const config: AIClientConfig = {
      baseUrl: "http://mock.local",
      apiKey: undefined,
      timeoutMs: 30,
      fetchImpl: mockFetch,
    };
    const result = await callAI(["te", "qk"], wordCandidates, "", config);
    expect(result).toBeNull();
  });

  it("sends Authorization header when apiKey is set", async () => {
    let captured: Record<string, string> = {};
    const mockFetch = (async (_url: unknown, init?: { headers?: Record<string, string> }) => {
      captured = init?.headers ?? {};
      return new Response(JSON.stringify({ prediction: "the quick" }), { status: 200 });
    }) as unknown as typeof fetch;
    await callAI(["te", "qk"], wordCandidates, "", {
      baseUrl: "http://mock.local",
      apiKey: "secret-token",
      timeoutMs: 150,
      fetchImpl: mockFetch,
    });
    expect(captured.authorization).toBe("Bearer secret-token");
  });
});

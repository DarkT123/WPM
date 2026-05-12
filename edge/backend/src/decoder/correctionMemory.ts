import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs";
import { dirname } from "node:path";
import type { Domain } from "../../../shared/types.js";
import { PhraseMemory } from "./phraseMemory.js";

// Bumped when the file schema changes incompatibly. On version mismatch we
// start with empty stores rather than try to migrate — corrections are cheap
// to rebuild and the old "edge token" boosts (wt/pn/etc.) wouldn't help the
// new prefix decoder anyway.
const SCHEMA_VERSION = 2;

export interface CorrectionsFile {
  version?: number;
  /** Exact compressed-pattern → corrected sentence, per domain. */
  exactPatterns: Partial<Record<Domain, Record<string, string>>>;
  /** Token (prefix) → word → boost count, per domain. */
  wordBoosts: Partial<Record<Domain, Record<string, Record<string, number>>>>;
  /** "prev|prefix|word" → count, per domain. */
  prefixSuccessors: Partial<Record<Domain, Record<string, number>>>;
  /** Snapshot of learned phrase memory. */
  phraseSnapshot?: ReturnType<PhraseMemory["snapshot"]>;
}

const DOMAINS: Domain[] = ["general", "school", "business", "coding", "texting", "research"];

function successorKey(prev: string, prefix: string, word: string): string {
  return `${prev}|${prefix}|${word}`;
}

export class CorrectionMemory {
  private exact: Record<Domain, Map<string, string>>;
  private boosts: Record<Domain, Map<string, Map<string, number>>>;
  private successors: Record<Domain, Map<string, number>>;

  constructor(private readonly filePath: string, private readonly phrases: PhraseMemory) {
    this.exact = Object.fromEntries(DOMAINS.map((d) => [d, new Map<string, string>()])) as typeof this.exact;
    this.boosts = Object.fromEntries(DOMAINS.map((d) => [d, new Map<string, Map<string, number>>()])) as typeof this.boosts;
    this.successors = Object.fromEntries(DOMAINS.map((d) => [d, new Map<string, number>()])) as typeof this.successors;
    this.load();
  }

  private resetStores(): void {
    for (const d of DOMAINS) {
      this.exact[d] = new Map();
      this.boosts[d] = new Map();
      this.successors[d] = new Map();
    }
  }

  private load(): void {
    if (!existsSync(this.filePath)) return;
    try {
      const raw = readFileSync(this.filePath, "utf8");
      const parsed = JSON.parse(raw) as Partial<CorrectionsFile>;
      if ((parsed.version ?? 1) !== SCHEMA_VERSION) {
        // Old schema (first/last-letter edge tokens). Drop it cleanly.
        this.resetStores();
        return;
      }
      for (const d of DOMAINS) {
        const ex = parsed.exactPatterns?.[d] ?? {};
        this.exact[d] = new Map(Object.entries(ex));
        const wb = parsed.wordBoosts?.[d] ?? {};
        const inner = new Map<string, Map<string, number>>();
        for (const [tok, m] of Object.entries(wb)) {
          inner.set(tok, new Map(Object.entries(m)));
        }
        this.boosts[d] = inner;
        const ps = parsed.prefixSuccessors?.[d] ?? {};
        this.successors[d] = new Map(Object.entries(ps));
      }
      if (parsed.phraseSnapshot) this.phrases.restore(parsed.phraseSnapshot);
    } catch {
      // Corrupted file: start fresh.
      this.resetStores();
    }
  }

  private persist(): void {
    mkdirSync(dirname(this.filePath), { recursive: true });
    const out: CorrectionsFile = {
      version: SCHEMA_VERSION,
      exactPatterns: {},
      wordBoosts: {},
      prefixSuccessors: {},
      phraseSnapshot: this.phrases.snapshot(),
    };
    for (const d of DOMAINS) {
      out.exactPatterns![d] = Object.fromEntries(this.exact[d]);
      const wb: Record<string, Record<string, number>> = {};
      for (const [tok, m] of this.boosts[d]) wb[tok] = Object.fromEntries(m);
      out.wordBoosts![d] = wb;
      out.prefixSuccessors![d] = Object.fromEntries(this.successors[d]);
    }
    writeFileSync(this.filePath, JSON.stringify(out, null, 2), "utf8");
  }

  exactMatch(compressed: string, domain: Domain): string | null {
    return this.exact[domain].get(compressed.toLowerCase()) ?? null;
  }

  /** boost for (token, word) in a domain. Falls back to general. */
  wordBoost(token: string, word: string, domain: Domain): number {
    const t = token.toLowerCase();
    const w = word.toLowerCase();
    const fromDomain = this.boosts[domain].get(t)?.get(w) ?? 0;
    const fromGeneral = domain === "general" ? 0 : this.boosts.general.get(t)?.get(w) ?? 0;
    return fromDomain + fromGeneral * 0.5;
  }

  /**
   * Contextual boost for (prev word → prefix → word) in a domain. This is the
   * strongest local signal for a prefix decoder: confirmed `(i, wa) → was`
   * should dominate `(he, wa) → walked`. Falls back to general.
   */
  prefixSuccessorBoost(prev: string, prefix: string, word: string, domain: Domain): number {
    const p = prev.toLowerCase();
    const pre = prefix.toLowerCase();
    const w = word.toLowerCase();
    const key = successorKey(p, pre, w);
    const fromDomain = this.successors[domain].get(key) ?? 0;
    const fromGeneral = domain === "general" ? 0 : this.successors.general.get(key) ?? 0;
    return fromDomain + fromGeneral * 0.5;
  }

  record(compressed: string, corrected: string, domain: Domain): void {
    const tokens = compressed.toLowerCase().trim().split(/\s+/).filter(Boolean);
    const words = corrected.trim().split(/\s+/);
    if (tokens.length === 0 || tokens.length !== words.length) {
      throw new Error(
        `correction shape mismatch: ${tokens.length} tokens vs ${words.length} words`
      );
    }

    this.exact[domain].set(tokens.join(" "), words.join(" "));

    for (let i = 0; i < tokens.length; i++) {
      const t = tokens[i]!;
      const w = words[i]!.toLowerCase();
      let tBucket = this.boosts[domain].get(t);
      if (!tBucket) { tBucket = new Map(); this.boosts[domain].set(t, tBucket); }
      tBucket.set(w, (tBucket.get(w) ?? 0) + 1);

      const prev = i > 0 ? words[i - 1]!.toLowerCase() : "";
      const key = successorKey(prev, t, w);
      this.successors[domain].set(key, (this.successors[domain].get(key) ?? 0) + 1);
    }

    this.phrases.learn(words, domain);
    this.persist();
  }
}

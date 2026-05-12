import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs";
import { dirname } from "node:path";

export interface CorrectionsFile {
  exactPatterns: Record<string, string>;
  wordBoosts: Record<string, Record<string, number>>;
  learnedBigrams: Record<string, number>;
}

const EMPTY: CorrectionsFile = {
  exactPatterns: {},
  wordBoosts: {},
  learnedBigrams: {},
};

export class CorrectionsStore {
  private state: CorrectionsFile = { ...EMPTY, exactPatterns: {}, wordBoosts: {}, learnedBigrams: {} };

  constructor(private readonly filePath: string) {
    this.load();
  }

  private load(): void {
    if (!existsSync(this.filePath)) return;
    try {
      const raw = readFileSync(this.filePath, "utf8");
      const parsed = JSON.parse(raw) as Partial<CorrectionsFile>;
      this.state = {
        exactPatterns: parsed.exactPatterns ?? {},
        wordBoosts: parsed.wordBoosts ?? {},
        learnedBigrams: parsed.learnedBigrams ?? {},
      };
    } catch {
      // Corrupted file: start fresh rather than crashing the server.
      this.state = { exactPatterns: {}, wordBoosts: {}, learnedBigrams: {} };
    }
  }

  private persist(): void {
    mkdirSync(dirname(this.filePath), { recursive: true });
    writeFileSync(this.filePath, JSON.stringify(this.state, null, 2), "utf8");
  }

  exactMatch(compressed: string): string | null {
    return this.state.exactPatterns[compressed.toLowerCase()] ?? null;
  }

  wordBoosts(): Readonly<Record<string, Readonly<Record<string, number>>>> {
    return this.state.wordBoosts;
  }

  learnedBigrams(): Readonly<Record<string, number>> {
    return this.state.learnedBigrams;
  }

  record(compressed: string, corrected: string): void {
    const tokens = compressed.toLowerCase().trim().split(/\s+/).filter(Boolean);
    const words = corrected.trim().split(/\s+/);
    if (tokens.length === 0 || tokens.length !== words.length) {
      throw new Error(
        `correction shape mismatch: ${tokens.length} tokens vs ${words.length} words`
      );
    }

    this.state.exactPatterns[tokens.join(" ")] = words.join(" ");

    for (let i = 0; i < tokens.length; i++) {
      const t = tokens[i]!;
      const w = words[i]!.toLowerCase();
      const tBucket = (this.state.wordBoosts[t] ??= {});
      tBucket[w] = (tBucket[w] ?? 0) + 1;

      if (i > 0) {
        const prev = words[i - 1]!.toLowerCase();
        const key = `${prev} ${w}`;
        this.state.learnedBigrams[key] = (this.state.learnedBigrams[key] ?? 0) + 1;
      }
    }

    this.persist();
  }

  snapshot(): CorrectionsFile {
    return JSON.parse(JSON.stringify(this.state)) as CorrectionsFile;
  }
}

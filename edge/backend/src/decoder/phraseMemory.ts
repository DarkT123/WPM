import type { Domain } from "../../../shared/types.js";

/**
 * Phrase memory stores natural-language n-grams (bigrams + trigrams), partitioned by
 * domain so the decoder can prefer "market research" in business mode and
 * "compile function" in coding mode without polluting general English. Learned
 * phrases from correction submissions are merged in alongside the curated
 * defaults.
 */

type Counts = Map<string, number>;
type DomainTable = { bigrams: Counts; trigrams: Counts };

function emptyTable(): DomainTable {
  return { bigrams: new Map(), trigrams: new Map() };
}

const STARTER_BIGRAMS_GENERAL: Record<string, number> = {
  "i want": 18, "want to": 25, "to make": 20, "to be": 15,
  "to go": 12, "to do": 14, "to see": 10, "to take": 8,
  "make a": 14, "make sure": 6, "make it": 7,
  "a prediction": 6, "the prediction": 5,
  "a good": 12, "a great": 10, "a long": 8, "a new": 9,
  "the quick": 5, "quick brown": 8, "brown fox": 8,
  "we are": 12, "are going": 14, "going to": 18, "to the": 18,
  "the place": 4, "the store": 5, "the school": 5,
  "it was": 14, "was a": 10, "good day": 6, "good morning": 5,
  "of the": 22, "in the": 22, "on the": 18, "for the": 14,
  "and the": 16, "with the": 12, "from the": 12, "at the": 16,
  "i am": 12, "you are": 10, "he is": 8, "she is": 8,
  "they are": 9, "we will": 7, "will be": 9, "have been": 9,
  "has been": 8, "had been": 6, "i think": 8, "i know": 7,
  "do you": 8, "can you": 6, "thank you": 8, "see you": 7,
  "this is": 9, "that is": 9, "there is": 8, "there are": 8,
  "is a": 12, "is the": 12, "is not": 8, "do not": 7,
  "the same": 9, "the other": 8, "the only": 7, "the first": 9,
  "the last": 9, "the next": 8, "right now": 6, "every day": 8,
  "all the": 10, "look at": 6, "going home": 4, "come back": 4,
  "find out": 5, "get back": 4,
  "very good": 5, "really good": 4, "going on": 5, "going down": 4,
  "i went": 5, // weaker than "i want" so "wt" prefers "want" after "i"
  "i wait": 1, "i wrote": 2, "i was": 12,
  "prediction market": 18, "market research": 16, "research app": 10,
};

const STARTER_TRIGRAMS_GENERAL: Record<string, number> = {
  "i want to": 24, "i went to": 12, "i had to": 10, "i need to": 12,
  "want to make": 14, "want to be": 10, "want to go": 12, "want to see": 8,
  "to make a": 16, "make a prediction": 8, "make a difference": 4,
  "make a decision": 4, "a prediction market": 14, "prediction market research": 14,
  "market research app": 12, "to be a": 8, "to do a": 4,
  "is going to": 10, "we are going": 10, "are going to": 14,
  "going to the": 12, "going to be": 10, "going to make": 6,
  "to the store": 6, "to the school": 5, "to the place": 4,
  "thank you for": 6, "what do you": 7, "what are you": 6,
  "where are you": 6, "do you want": 6, "do you know": 7,
};

const STARTER_BIGRAMS_BUSINESS: Record<string, number> = {
  "prediction market": 30, "market research": 25, "research app": 12,
  "business plan": 12, "data analysis": 10, "product market": 8,
  "growth plan": 6, "venture capital": 8, "go to market": 8,
  "make a product": 4, "make a report": 4, "the report": 6,
};

const STARTER_BIGRAMS_RESEARCH: Record<string, number> = {
  "prediction market": 35, "market research": 28, "research app": 15,
  "research paper": 18, "data set": 8, "data analysis": 14,
  "literature review": 10, "case study": 8, "results show": 6,
};

const STARTER_BIGRAMS_CODING: Record<string, number> = {
  "function call": 8, "string literal": 5, "object oriented": 4,
  "code review": 10, "pull request": 12, "merge conflict": 6,
  "package json": 6, "server side": 5, "client side": 5,
  "compile error": 5, "run time": 6, "type check": 4,
};

const STARTER_BIGRAMS_SCHOOL: Record<string, number> = {
  "school day": 6, "this week": 8, "the test": 6, "the exam": 6,
  "to school": 8, "from school": 6, "do homework": 6, "do the homework": 5,
  "the class": 6, "the teacher": 7,
};

const STARTER_BIGRAMS_TEXTING: Record<string, number> = {
  "see you": 12, "talk to you": 8, "see you later": 8, "later tonight": 4,
  "on my way": 10, "be there": 6, "running late": 5, "let me know": 8,
  "love you": 10, "miss you": 7, "thank you": 9,
};

function toCounts(rec: Record<string, number>): Counts {
  return new Map(Object.entries(rec));
}

function merge(base: Counts, extra: Counts): Counts {
  const out = new Map(base);
  for (const [k, v] of extra) out.set(k, (out.get(k) ?? 0) + v);
  return out;
}

export class PhraseMemory {
  private starter: Record<Domain, DomainTable>;
  private learned: Record<Domain, DomainTable>;

  constructor() {
    this.starter = {
      general: { bigrams: toCounts(STARTER_BIGRAMS_GENERAL), trigrams: toCounts(STARTER_TRIGRAMS_GENERAL) },
      school: { bigrams: toCounts(STARTER_BIGRAMS_SCHOOL), trigrams: new Map() },
      business: { bigrams: toCounts(STARTER_BIGRAMS_BUSINESS), trigrams: new Map() },
      coding: { bigrams: toCounts(STARTER_BIGRAMS_CODING), trigrams: new Map() },
      texting: { bigrams: toCounts(STARTER_BIGRAMS_TEXTING), trigrams: new Map() },
      research: { bigrams: toCounts(STARTER_BIGRAMS_RESEARCH), trigrams: new Map() },
    };
    this.learned = {
      general: emptyTable(), school: emptyTable(), business: emptyTable(),
      coding: emptyTable(), texting: emptyTable(), research: emptyTable(),
    };
  }

  /** Domain-specific score for a bigram (prev, current). Falls back to general. */
  bigramScore(prev: string, current: string, domain: Domain): number {
    if (!prev || !current) return 0;
    const key = `${prev.toLowerCase()} ${current.toLowerCase()}`;
    const dom = this.lookup("bigrams", key, domain);
    const gen = domain === "general" ? 0 : this.lookup("bigrams", key, "general");
    return dom + gen * 0.6;
  }

  trigramScore(prev2: string, prev1: string, current: string, domain: Domain): number {
    if (!prev2 || !prev1 || !current) return 0;
    const key = `${prev2.toLowerCase()} ${prev1.toLowerCase()} ${current.toLowerCase()}`;
    const dom = this.lookup("trigrams", key, domain);
    const gen = domain === "general" ? 0 : this.lookup("trigrams", key, "general");
    return dom + gen * 0.6;
  }

  private lookup(kind: "bigrams" | "trigrams", key: string, domain: Domain): number {
    const s = this.starter[domain][kind].get(key) ?? 0;
    const l = this.learned[domain][kind].get(key) ?? 0;
    // Learned phrases outweigh curated once confirmed.
    return s + l * 3;
  }

  /** Add a learned phrase observed in a user correction. */
  learn(words: string[], domain: Domain): void {
    const ws = words.map((w) => w.toLowerCase());
    for (let i = 0; i + 1 < ws.length; i++) {
      const key = `${ws[i]} ${ws[i + 1]}`;
      const m = this.learned[domain].bigrams;
      m.set(key, (m.get(key) ?? 0) + 1);
    }
    for (let i = 0; i + 2 < ws.length; i++) {
      const key = `${ws[i]} ${ws[i + 1]} ${ws[i + 2]}`;
      const m = this.learned[domain].trigrams;
      m.set(key, (m.get(key) ?? 0) + 1);
    }
  }

  snapshot(): { bigrams: Record<Domain, Record<string, number>>; trigrams: Record<Domain, Record<string, number>> } {
    const out = { bigrams: {} as Record<Domain, Record<string, number>>, trigrams: {} as Record<Domain, Record<string, number>> };
    for (const d of Object.keys(this.learned) as Domain[]) {
      out.bigrams[d] = Object.fromEntries(this.learned[d].bigrams);
      out.trigrams[d] = Object.fromEntries(this.learned[d].trigrams);
    }
    return out;
  }

  restore(snap: { bigrams?: Record<Domain, Record<string, number>>; trigrams?: Record<Domain, Record<string, number>> }): void {
    for (const d of Object.keys(this.learned) as Domain[]) {
      this.learned[d].bigrams = new Map(Object.entries(snap.bigrams?.[d] ?? {}));
      this.learned[d].trigrams = new Map(Object.entries(snap.trigrams?.[d] ?? {}));
    }
  }
}

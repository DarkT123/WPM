// Hand-picked common English bigrams with relative weights. Used to nudge
// beam search toward sentences with natural word adjacency. Augmented at
// runtime by adjacency stats from user corrections (see learning/store.ts).
const STARTER_BIGRAMS: Record<string, number> = {
  "the quick": 5,
  "quick brown": 6,
  "brown fox": 6,
  "the fox": 2,
  "we are": 5,
  "are going": 5,
  "going to": 6,
  "to the": 6,
  "the place": 3,
  "it was": 6,
  "was a": 5,
  "a good": 5,
  "good day": 4,
  "of the": 8,
  "in the": 8,
  "on the": 6,
  "for the": 5,
  "to be": 5,
  "i am": 4,
  "you are": 4,
  "he is": 3,
  "she is": 3,
  "they are": 4,
  "we will": 3,
  "will be": 4,
  "have been": 4,
  "has been": 4,
  "had been": 3,
  "i think": 3,
  "i know": 3,
  "do you": 3,
  "can you": 3,
  "would you": 2,
  "thank you": 4,
  "let me": 2,
  "let us": 2,
  "the best": 3,
  "at the": 5,
  "with the": 4,
  "from the": 4,
  "by the": 3,
  "and the": 5,
  "but the": 3,
  "or the": 2,
  "is a": 4,
  "is the": 5,
  "this is": 4,
  "that is": 4,
  "there is": 3,
  "there are": 3,
  "going home": 2,
  "right now": 2,
  "long time": 2,
  "every day": 3,
  "next time": 2,
  "first time": 3,
  "last time": 3,
  "good morning": 3,
  "good night": 3,
  "see you": 3,
  "going back": 2,
  "come back": 2,
  "make sure": 2,
  "find out": 2,
  "look for": 2,
  "look at": 3,
  "take care": 2,
  "took care": 2,
  "get back": 2,
  "in time": 2,
  "on time": 3,
  "all the": 5,
  "of a": 4,
  "to a": 3,
  "in a": 4,
  "for a": 3,
  "is not": 3,
  "do not": 3,
  "can not": 2,
  "will not": 2,
  "going on": 3,
  "going down": 2,
  "going up": 2,
  "right here": 2,
  "right there": 2,
  "very good": 3,
  "so good": 2,
  "too good": 1,
  "the same": 4,
  "the other": 3,
  "the only": 3,
  "the first": 4,
  "the last": 4,
  "the next": 3,
  "prediction markets": 4,
  "are changing": 3,
  "changing finance": 3,
};

export interface BigramSource {
  starter: Readonly<Record<string, number>>;
  learned: Readonly<Record<string, number>>;
}

export function bigramScore(prev: string, current: string, source: BigramSource): number {
  if (!prev) return 0;
  const key = `${prev.toLowerCase()} ${current.toLowerCase()}`;
  const starter = source.starter[key] ?? 0;
  const learned = source.learned[key] ?? 0;
  // Learned bigrams should outweigh hand-tuned ones once they've been
  // confirmed by enough corrections.
  return starter + learned * 3;
}

export function getStarterBigrams(): Readonly<Record<string, number>> {
  return STARTER_BIGRAMS;
}

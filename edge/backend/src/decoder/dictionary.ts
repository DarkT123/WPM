import { readFileSync, existsSync } from "node:fs";
import { join } from "node:path";

export interface WordEntry {
  word: string;
  freq: number;
}

// Curated frequency list. Heavier than EdgeType's starter dict so the
// example sentence "I want to make a prediction market research app"
// reconstructs cleanly without an external word list. Drop a tab- or
// space-separated `data/words.txt` to merge in a real corpus (SUBTLEX,
// Google Books, etc.) — see README.
const STARTER: ReadonlyArray<readonly [string, number]> = [
  // function words
  ["the", 22000000], ["of", 12000000], ["and", 11000000], ["to", 10500000],
  ["a", 10000000], ["in", 8500000], ["is", 5500000], ["it", 5400000],
  ["you", 5300000], ["that", 5200000], ["he", 4900000], ["was", 4800000],
  ["for", 4700000], ["on", 4600000], ["are", 4500000], ["as", 4300000],
  ["with", 4200000], ["his", 4000000], ["they", 3900000], ["i", 3800000],
  ["at", 3700000], ["be", 3600000], ["this", 3500000], ["have", 3400000],
  ["from", 3300000], ["or", 3200000], ["one", 3100000], ["had", 3000000],
  ["by", 2900000], ["word", 2800000], ["but", 2700000], ["not", 2650000],
  ["what", 2600000], ["all", 2550000], ["were", 2500000], ["we", 2450000],
  ["when", 2400000], ["your", 2350000], ["can", 2300000], ["said", 2250000],
  ["there", 2200000], ["use", 2150000], ["an", 2100000], ["each", 2050000],
  ["which", 2000000], ["she", 1950000], ["do", 1900000], ["how", 1850000],
  ["their", 1800000], ["if", 1750000], ["will", 1700000], ["up", 1650000],
  ["other", 1600000], ["about", 1550000], ["out", 1500000], ["many", 1450000],
  ["then", 1400000], ["them", 1380000], ["these", 1350000], ["so", 1330000],
  ["some", 1310000], ["her", 1290000], ["would", 1270000], ["make", 1500000],
  ["like", 1230000], ["him", 1210000], ["into", 1190000], ["time", 1170000],
  ["has", 1150000], ["look", 1130000], ["two", 1110000], ["more", 1090000],
  ["write", 1070000], ["go", 1050000], ["see", 1030000], ["number", 1010000],
  ["no", 990000], ["way", 970000], ["could", 950000], ["people", 930000],
  ["my", 910000], ["than", 890000], ["first", 870000], ["been", 850000],
  ["call", 830000], ["who", 810000], ["its", 790000], ["now", 770000],
  ["find", 750000], ["long", 730000], ["down", 710000], ["day", 690000],
  ["did", 670000], ["get", 650000], ["come", 630000], ["made", 610000],
  ["may", 590000], ["part", 570000], ["over", 550000], ["new", 530000],
  ["sound", 510000], ["take", 490000], ["only", 470000], ["little", 450000],
  ["work", 430000], ["know", 410000], ["place", 390000], ["years", 370000],
  ["live", 350000], ["me", 340000], ["back", 330000], ["give", 320000],
  ["most", 310000], ["very", 300000], ["after", 290000], ["thing", 280000],
  ["our", 270000], ["just", 260000], ["name", 250000], ["good", 240000],
  ["want", 1700000], // bumped: "I want to ___" is the canonical demo
  ["sentence", 230000], ["man", 225000], ["think", 220000], ["say", 215000],
  ["great", 210000], ["where", 205000], ["help", 200000], ["through", 195000],
  ["much", 190000], ["before", 185000], ["line", 180000], ["right", 175000],
  ["too", 170000], ["means", 165000], ["old", 160000], ["any", 155000],
  ["same", 150000], ["tell", 145000], ["boy", 140000], ["follow", 135000],
  ["came", 130000], ["went", 250000], // common alt for "wt"
  ["show", 120000], ["also", 118000], ["around", 116000], ["form", 114000],
  ["three", 112000], ["small", 110000], ["set", 108000], ["put", 106000],
  ["end", 104000], ["does", 102000], ["another", 100000], ["well", 98000],
  ["large", 96000], ["must", 94000], ["big", 92000], ["even", 90000],
  ["such", 88000], ["because", 86000], ["turn", 84000], ["here", 82000],
  ["why", 80000], ["asked", 78000], ["men", 74000], ["read", 72000],
  ["need", 70000], ["land", 68000], ["different", 66000], ["home", 64000],
  ["us", 62000], ["move", 60000], ["try", 58000], ["kind", 56000],
  ["hand", 54000], ["picture", 52000], ["again", 50000], ["change", 48000],
  ["off", 46000], ["play", 44000], ["spell", 42000], ["air", 40000],
  ["away", 38000], ["animal", 36000], ["house", 34000], ["point", 32000],
  ["page", 30000], ["letter", 29000], ["mother", 28000], ["answer", 27000],
  ["found", 26000], ["study", 25000], ["still", 24500], ["learn", 24000],
  ["should", 23500], ["world", 22500], ["high", 22000], ["every", 21500],
  ["near", 21000], ["add", 20500], ["food", 20000], ["between", 19800],
  ["own", 19600], ["below", 19400], ["country", 19200], ["plant", 19000],
  ["last", 18800], ["school", 18600], ["father", 18400], ["keep", 18200],
  ["tree", 18000], ["never", 17800], ["started", 17600], ["city", 17400],
  ["earth", 17200], ["eyes", 17000], ["light", 16800], ["thought", 16600],
  ["head", 16400], ["under", 16200], ["story", 16000], ["saw", 15800],
  ["left", 15600], ["few", 15200], ["while", 15000], ["along", 14800],
  ["might", 14600], ["close", 14400], ["something", 14200], ["seemed", 14000],
  ["next", 13800], ["hard", 13600], ["open", 13400], ["example", 13200],
  ["begin", 13000], ["life", 12800], ["always", 12600], ["those", 12400],
  ["both", 12200], ["paper", 12000], ["together", 11800], ["got", 11600],
  ["group", 11400], ["often", 11200], ["run", 11000], ["important", 10800],
  ["until", 10600], ["children", 10400], ["side", 10200], ["feet", 10000],
  ["car", 9800], ["miles", 9600], ["night", 9400], ["walked", 9200],
  ["white", 9000], ["sea", 8800], ["began", 8600], ["grow", 8400],
  ["river", 8200], ["four", 8000], ["carry", 7900], ["state", 7800],
  ["once", 7700], ["book", 7600], ["hear", 7500], ["stop", 7400],
  ["without", 7300], ["second", 7200], ["later", 7100], ["miss", 7000],
  ["idea", 6900], ["enough", 6800], ["eat", 6700], ["face", 6600],
  ["watch", 6500], ["far", 6400], ["really", 6200], ["almost", 6100],
  ["let", 6000], ["above", 5900], ["girl", 5800], ["sometimes", 5700],
  ["mountains", 5600], ["cut", 5500], ["young", 5400], ["talk", 5300],
  ["soon", 5200], ["list", 5100], ["song", 5000], ["being", 4950],
  ["leave", 4900], ["family", 4850], ["body", 4800], ["music", 4750],
  ["color", 4700], ["stand", 4650], ["sun", 4600], ["questions", 4550],
  ["fish", 4500], ["area", 4450], ["mark", 4400], ["dog", 4350],
  ["horse", 4300], ["birds", 4250], ["problem", 4200], ["complete", 4150],
  ["room", 4100], ["knew", 4050], ["since", 4000], ["ever", 3950],
  ["piece", 3900], ["told", 3850], ["usually", 3800], ["friends", 3700],
  ["easy", 3650], ["heard", 3600], ["order", 3550], ["red", 3500],
  ["door", 3450], ["sure", 3400], ["become", 3350], ["top", 3300],
  ["ship", 3250], ["across", 3200], ["today", 3150], ["during", 3100],
  ["short", 3050], ["better", 3000], ["best", 2950], ["however", 2900],
  ["low", 2850], ["hours", 2800], ["black", 2750], ["products", 2700],
  ["happened", 2650], ["whole", 2600], ["measure", 2550], ["remember", 2500],
  ["early", 2450], ["waves", 2400], ["reached", 2350], ["listen", 2300],
  ["wind", 2250], ["rock", 2200], ["space", 2150], ["covered", 2100],
  ["fast", 2050], ["several", 2000], ["hold", 1980], ["himself", 1960],
  ["toward", 1940], ["five", 1920], ["step", 1900], ["morning", 1880],
  ["passed", 1860], ["true", 1820], ["hundred", 1800], ["against", 1780],
  ["pattern", 1760], ["table", 1720], ["north", 1700], ["slowly", 1680],
  ["money", 1660], ["map", 1640], ["pulled", 1600], ["draw", 1580],
  ["voice", 1560], ["seen", 1540], ["cold", 1520], ["cried", 1500],
  ["plan", 1480], ["notice", 1460], ["south", 1440], ["sing", 1420],
  ["war", 1400], ["ground", 1380], ["fall", 1360], ["king", 1340],
  ["town", 1320], ["unit", 1280], ["figure", 1260], ["certain", 1240],
  ["field", 1220], ["travel", 1200], ["wood", 1180], ["fire", 1160],
  ["upon", 1140], ["done", 1120], ["English", 1100], ["road", 1080],
  ["ten", 1040], ["machine", 1020], ["note", 1000], ["wait", 350000],
  ["plane", 960], ["box", 940], ["finally", 920], ["round", 900],
  ["born", 880], ["dark", 860], ["ball", 840], ["material", 820],
  ["special", 800], ["heavy", 780], ["fine", 760], ["pair", 740],
  ["circle", 720], ["include", 700], ["built", 680], ["common", 660],
  ["gold", 640], ["possible", 620], ["age", 580], ["dry", 560],
  ["wonder", 540], ["laughed", 520], ["thousand", 500], ["ago", 490],
  ["ran", 480], ["check", 470], ["game", 460], ["shape", 450],
  ["yes", 440], ["hot", 430], ["brought", 410], ["heat", 400],
  ["snow", 390], ["tire", 380], ["bring", 370], ["yet", 360],
  ["fill", 350], ["east", 340], ["weight", 330], ["language", 320],
  ["among", 310], ["fox", 2000], ["quick", 1800], ["brown", 1700],
  ["jumps", 50], ["lazy", 45],

  // domain words for the canonical Edge example
  ["prediction", 30000], ["predict", 9000], ["predicted", 4000],
  ["predicting", 3000], ["predictive", 2000],
  ["market", 40000], ["markets", 18000], ["marketing", 9000],
  ["research", 25000], ["researched", 1000], ["researcher", 2500],
  ["app", 28000], ["apps", 9000], ["application", 8000], ["apple", 4000],
  ["asleep", 1200], ["atop", 500],
  ["data", 22000], ["analysis", 6000], ["report", 6500], ["product", 11000],
  ["business", 15000], ["finance", 9000], ["finance", 9000],
  ["software", 7000], ["hardware", 1800], ["startup", 1500],
  ["code", 14000], ["coding", 1200], ["function", 5000], ["variable", 1500],
  ["string", 1500], ["number", 9500], ["array", 600], ["object", 2500],
  ["server", 1900], ["client", 2200], ["request", 1900],
  ["compile", 80], ["package", 1500],

  // common short words across letter pairs
  ["bank", 1900], ["task", 1500], ["walk", 4000], ["test", 28000],
  ["love", 6000], ["hope", 3000], ["am", 200000], ["pm", 200],
  ["fix", 8500], ["mix", 250], ["six", 700], ["tax", 600],
  ["max", 300], ["bat", 200], ["bet", 250], ["bit", 600], ["bot", 100],
  ["mat", 80], ["met", 4000], ["mit", 30], ["mut", 5], ["mot", 5],
  ["ms", 200], ["mr", 1000], ["mt", 1], ["pn", 1], ["rh", 1],
  ["fast", 2050], ["last", 18800], ["list", 5100], ["lost", 5000],
  ["learn", 24000], ["learned", 3000], ["learning", 4000],
  ["look", 1130000], ["loop", 600], ["leap", 200], ["loud", 600],
  ["reach", 3000], ["reached", 2350], ["rich", 2500], ["roach", 30],
  ["both", 12200], ["bath", 800], ["beth", 50], ["broth", 30],

  // common verbs and adjectives that fall in commonly-typed buckets
  ["bring", 370], ["browse", 200], ["brown", 1700], ["bridge", 1800],
  ["beg", 50], ["bag", 800], ["big", 92000], ["bog", 30],
  ["any", 155000], ["nay", 30], ["nail", 80], ["nice", 4000],
  ["pretend", 250], ["pen", 800], ["pan", 800], ["plan", 1480],
  ["pin", 500], ["pun", 50], ["plain", 800], ["plain", 800],
];

let cachedEntries: WordEntry[] | null = null;

function dedupe(rows: ReadonlyArray<readonly [string, number]>): Map<string, number> {
  const map = new Map<string, number>();
  for (const [w, f] of rows) {
    const key = w.toLowerCase();
    const prev = map.get(key);
    if (prev === undefined || f > prev) map.set(key, f);
  }
  return map;
}

function loadExternal(): Map<string, number> {
  const out = new Map<string, number>();
  const path = join(process.cwd(), "data", "words.txt");
  if (!existsSync(path)) return out;
  const raw = readFileSync(path, "utf8");
  for (const line of raw.split(/\r?\n/)) {
    if (!line.trim() || line.startsWith("#")) continue;
    const [word, freqStr] = line.split(/\t|\s+/);
    if (!word) continue;
    const freq = Number(freqStr ?? 1);
    if (!Number.isFinite(freq) || freq <= 0) continue;
    out.set(word.toLowerCase(), freq);
  }
  return out;
}

export function loadDictionary(): WordEntry[] {
  if (cachedEntries) return cachedEntries;
  const merged = dedupe(STARTER);
  for (const [w, f] of loadExternal()) merged.set(w, Math.max(merged.get(w) ?? 0, f));
  cachedEntries = [...merged.entries()]
    .map(([word, freq]) => ({ word, freq }))
    .sort((a, b) => b.freq - a.freq);
  return cachedEntries;
}

export function resetDictionaryCache(): void {
  cachedEntries = null;
}

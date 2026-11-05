// Tests for TranslateModel.js. QML's `.pragma library` header isn't JavaScript,
// so the file is loaded as source with that line dropped.
//
//   node test/model.test.mjs

import { readFileSync } from "node:fs"
import assert from "node:assert/strict"

const source = readFileSync(new URL("../TranslateModel.js", import.meta.url), "utf8").replace(/^\.pragma library$/m, "")
const names = [...source.matchAll(/^function (\w+)/gm)].map((m) => m[1])
const M = new Function(`${source}\nreturn { ${names.join(", ")}, HISTORY_LIMIT, MAX_SOURCE }`)()

const crow = (from, translations) => JSON.stringify({
  source: "text",
  source_language: from,
  source_language_name: from.toUpperCase(),
  translations: translations.map(([language, text]) => ({ language, language_name: language.toUpperCase(), text })),
})

const tests = {
  "languages come from settings, deduped and validated"() {
    assert.deepEqual(M.languages({ languages: ["he", "en", "he", "x; rm -rf /"] }, "en"), ["he", "en"])
    assert.deepEqual(M.languages({ languages: ["he"] }, "en"), ["he", "en"])
    assert.deepEqual(M.languages({ languages: ["en"] }, "en"), ["en", "es"])
  },
  "languages fall back to the UI language plus English"() {
    assert.deepEqual(M.languages({}, "de"), ["de", "en"])
    assert.deepEqual(M.languages({}, "pt-BR"), ["pt", "en"])
    assert.deepEqual(M.languages(null, "en"), ["en", "es"])
  },
  "parseSettings tolerates junk"() {
    assert.deepEqual(M.parseSettings("not json"), {})
    assert.deepEqual(M.parseSettings("[1]"), {})
    assert.deepEqual(M.parseSettings('{"copy":false}'), { copy: false })
  },
  "cleanSource trims and caps the selection"() {
    assert.equal(M.cleanSource("  hi\r\nthere \u0000 "), "hi\nthere")
    assert.equal(M.cleanSource("a".repeat(M.MAX_SOURCE + 50)).length, M.MAX_SOURCE)
    assert.equal(M.cleanSource(undefined), "")
  },
  "pickResult prefers the first wanted language that isn't the source"() {
    const r = M.pickResult(crow("en", [["he", "שלום"], ["en", "hello"]]), ["he", "en"])
    assert.equal(r.to, "he")
    assert.equal(r.translation, "שלום")
    assert.equal(r.from, "en")
  },
  "pickResult falls to the next language when text is already in the first"() {
    const r = M.pickResult(crow("he", [["he", "שלום"], ["en", "hello"]]), ["he", "en"])
    assert.equal(r.to, "en")
    assert.equal(r.translation, "hello")
  },
  "pickResult rejects broken output"() {
    assert.equal(M.pickResult("", ["he"]), null)
    assert.equal(M.pickResult("Detecting fastest instance", ["he"]), null)
    assert.equal(M.pickResult(JSON.stringify({ translations: "x" }), ["he"]), null)
    assert.equal(M.pickResult(crow("en", [["he", "   "]]), ["he"]), null)
  },
  "markup-shaped text stays a plain string"() {
    const evil = '<img src="https://example.invalid/t">'
    const r = M.pickResult(crow("en", [["he", evil]]), ["he"])
    assert.equal(r.translation, evil)
  },
  "addEntry puts newest first, dedupes by text+target, and caps"() {
    const a = { source: "a", translation: "A", to: "he", at: 1 }
    const b = { source: "b", translation: "B", to: "he", at: 2 }
    let h = M.addEntry([], a, 10)
    h = M.addEntry(h, b, 10)
    h = M.addEntry(h, { ...a, at: 3 }, 10)
    assert.deepEqual(h.map((e) => e.source), ["a", "b"])
    assert.equal(h[0].at, 3)
    assert.equal(M.addEntry(h, { source: "c", translation: "C", to: "he" }, 2).length, 2)
    assert.equal(M.addEntry(h, { source: "a", translation: "A", to: "en" }, 10).length, 3)
  },
  "parseHistory drops invalid entries"() {
    const raw = JSON.stringify([{ source: "a", translation: "A", to: "he" }, { source: "", translation: "x" }, 5, null])
    assert.equal(M.parseHistory(raw).length, 1)
    assert.deepEqual(M.parseHistory("{"), [])
  },
  "removeEntryAt ignores out-of-range indexes"() {
    const h = [{ source: "a" }, { source: "b" }]
    assert.deepEqual(M.removeEntryAt(h, 0).map((e) => e.source), ["b"])
    assert.equal(M.removeEntryAt(h, 9).length, 2)
  },
  "displayRows filters both sides case-insensitively"() {
    const h = M.parseHistory(JSON.stringify([
      { source: "Good morning", translation: "בוקר טוב", to: "he" },
      { source: "שלום", translation: "Hello", to: "en" },
    ]))
    assert.equal(M.displayRows(h, "").length, 2)
    assert.deepEqual(M.displayRows(h, "MORNING").map((r) => r.historyIndex), [0])
    assert.deepEqual(M.displayRows(h, "hell").map((r) => r.historyIndex), [1])
    assert.deepEqual(M.displayRows(h, "בוקר").map((r) => r.historyIndex), [0])
  },
  "popupDuration is bounded"() {
    assert.equal(M.popupDuration(""), 5000)
    assert.equal(M.popupDuration("x".repeat(10000)), 20000)
  },
  "placeCard sits below the pointer, flips above near the bottom, stays on screen"() {
    assert.deepEqual(M.placeCard(500, 300, 200, 100, 1920, 1080, 20), { x: 460, y: 320 })
    assert.deepEqual(M.placeCard(500, 1050, 200, 100, 1920, 1080, 20), { x: 460, y: 930 })
    assert.equal(M.placeCard(1915, 300, 200, 100, 1920, 1080, 20).x, 1712)
    assert.equal(M.placeCard(0, 300, 200, 100, 1920, 1080, 20).x, 8)
  },
}

let failed = 0
for (const [name, fn] of Object.entries(tests)) {
  try {
    fn()
    console.log(`ok   ${name}`)
  } catch (e) {
    failed++
    console.log(`FAIL ${name}\n     ${e.message}`)
  }
}
console.log(failed ? `\n${failed} failed` : `\nall ${Object.keys(tests).length} passed`)
process.exit(failed ? 1 : 0)

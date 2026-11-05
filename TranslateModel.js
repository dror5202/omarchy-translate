.pragma library

// Pure helpers for drorko.translate: settings, crow output, and history.
// Kept free of QML so test/model.test.mjs can exercise them under node.

var MAX_SOURCE = 5000
var MAX_FIELD = 20000
var HISTORY_LIMIT = 300

function languageCode(value) {
  var code = String(value || "").trim()
  return /^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})?$/.test(code) ? code : ""
}

// Target languages, most wanted first. Text already in the first one is
// translated to the next. Falls back to the Omarchy UI language plus English.
function languages(settings, uiLanguage) {
  var list = []
  var configured = settings && Array.isArray(settings.languages) ? settings.languages : []
  for (var i = 0; i < configured.length; i++) {
    var code = languageCode(configured[i])
    if (code && list.indexOf(code) < 0) list.push(code)
  }
  if (list.length > 0) {
    if (list.length === 1) list.push(list[0] === "en" ? "es" : "en")
    return list.slice(0, 5)
  }

  var ui = languageCode(String(uiLanguage || "").split("-")[0]) || "en"
  return ui === "en" ? ["en", "es"] : [ui, "en"]
}

function parseSettings(raw) {
  try {
    var parsed = JSON.parse(String(raw || "{}"))
    return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : {}
  } catch (e) {
    return {}
  }
}

function cleanSource(text) {
  var value = String(text || "").replace(/\r\n?/g, "\n").replace(/\u0000/g, "")
  value = value.replace(/^\s+|\s+$/g, "")
  return value.length > MAX_SOURCE ? value.slice(0, MAX_SOURCE) : value
}

function clip(value, max) {
  var text = String(value === undefined || value === null ? "" : value)
  return text.length > max ? text.slice(0, max) : text
}

// crow -j -t a+b+c prints one translation per requested language. Pick the
// first wanted language that differs from the detected source language.
function pickResult(raw, wanted) {
  var data
  try {
    data = JSON.parse(String(raw || ""))
  } catch (e) {
    return null
  }
  if (!data || typeof data !== "object" || !Array.isArray(data.translations)) return null

  var from = languageCode(data.source_language) || "auto"
  var byLanguage = {}
  for (var i = 0; i < data.translations.length; i++) {
    var t = data.translations[i]
    if (t && typeof t === "object" && languageCode(t.language) && String(t.text || "").trim())
      byLanguage[t.language] = t
  }

  var order = Array.isArray(wanted) ? wanted : []
  var chosen = null
  for (var j = 0; j < order.length && !chosen; j++) {
    if (order[j] !== from && byLanguage[order[j]]) chosen = byLanguage[order[j]]
  }
  for (var k = 0; k < order.length && !chosen; k++) {
    if (byLanguage[order[k]]) chosen = byLanguage[order[k]]
  }
  if (!chosen) return null

  return {
    source: clip(data.source, MAX_FIELD),
    translation: clip(String(chosen.text).replace(/^\s+|\s+$/g, ""), MAX_FIELD),
    from: from,
    fromName: clip(data.source_language_name || from, 60),
    to: chosen.language,
    toName: clip(chosen.language_name || chosen.language, 60)
  }
}

function normalizeEntry(value) {
  if (!value || typeof value !== "object") return null
  var source = clip(value.source, MAX_FIELD)
  var translation = clip(value.translation, MAX_FIELD)
  if (!source.trim() || !translation.trim()) return null
  var at = Number(value.at)
  return {
    source: source,
    translation: translation,
    from: languageCode(value.from) || "auto",
    fromName: clip(value.fromName || value.from || "", 60),
    to: languageCode(value.to) || "",
    toName: clip(value.toName || value.to || "", 60),
    at: isFinite(at) && at > 0 ? Math.floor(at) : 0
  }
}

function entryKey(entry) {
  return entry ? entry.to + "\u0001" + entry.source : ""
}

function parseHistory(raw) {
  try {
    var parsed = JSON.parse(String(raw || "[]"))
    if (!Array.isArray(parsed)) return []
    var next = []
    for (var i = 0; i < parsed.length && next.length < HISTORY_LIMIT; i++) {
      var entry = normalizeEntry(parsed[i])
      if (entry) next.push(entry)
    }
    return next
  } catch (e) {
    return []
  }
}

// Newest first; translating the same text into the same language again moves
// it to the top instead of duplicating it.
function addEntry(history, entry, limit) {
  var normalized = normalizeEntry(entry)
  var values = Array.isArray(history) ? history : []
  var max = Math.max(0, Number(limit === undefined ? HISTORY_LIMIT : limit) || 0)
  if (!normalized) return values.slice(0, max)
  if (max === 0) return []

  var key = entryKey(normalized)
  var next = [normalized]
  for (var i = 0; i < values.length && next.length < max; i++) {
    if (entryKey(values[i]) !== key) next.push(values[i])
  }
  return next
}

function removeEntryAt(history, index) {
  var values = Array.isArray(history) ? history.slice() : []
  if (index >= 0 && index < values.length) values.splice(index, 1)
  return values
}

function oneLine(text, max) {
  var line = String(text || "").replace(/\s+/g, " ").replace(/^ | $/g, "")
  return line.length > max ? line.slice(0, max - 1) + "…" : line
}

// Rows for the history list, filtered case-insensitively on either side.
function displayRows(history, filter) {
  var needle = String(filter || "").toLowerCase()
  var rows = []
  var values = Array.isArray(history) ? history : []
  for (var i = 0; i < values.length; i++) {
    var e = values[i]
    if (needle && e.source.toLowerCase().indexOf(needle) < 0 && e.translation.toLowerCase().indexOf(needle) < 0)
      continue
    rows.push({
      historyIndex: i,
      source: e.source,
      translation: e.translation,
      sourceLine: oneLine(e.source, 160),
      translationLine: oneLine(e.translation, 160),
      fromName: e.fromName,
      toName: e.toName,
      at: e.at
    })
  }
  return rows
}

// How long the popup stays: long enough to read, never forever.
function popupDuration(text) {
  var length = String(text || "").length
  return Math.min(20000, Math.max(5000, 3000 + length * 60))
}

// Place a card of w×h near the pointer (px, py) inside an area of aw×ah:
// below and slightly right of the pointer so it doesn't cover the line just
// selected, flipping above when there is no room below.
function placeCard(px, py, w, h, aw, ah, gap) {
  var margin = 8
  var x = Math.max(margin, Math.min(aw - w - margin, px - Math.min(w / 4, 40)))
  var below = py + gap
  var above = py - gap - h
  var y = below + h <= ah - margin ? below : (above >= margin ? above : Math.max(margin, ah - h - margin))
  return { x: Math.round(x), y: Math.round(y) }
}

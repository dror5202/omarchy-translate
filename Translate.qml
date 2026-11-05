import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "TranslateModel.js" as Model

// Translate the selected text with Crow Translate and show the result in a
// small card next to the mouse pointer. Every translation is kept in a
// history overlay, the way the clipboard manager keeps copies.
//
//   omarchy-shell drorko.translate translate   translate the selection
//   omarchy-shell drorko.translate history     open / close the history
Item {
  id: root

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (root.home + "/.local/state")) + "/omarchy"
  readonly property string historyPath: root.stateDir + "/translate-history.json"
  readonly property string settingsPath: (Quickshell.env("XDG_CONFIG_HOME") || (root.home + "/.config")) + "/omarchy/translate.json"

  property var settings: ({})
  readonly property var languages: Model.languages(root.settings, Commons.I18n.language)
  readonly property bool copyResult: root.settings.copy !== false
  property var history: []

  // Popup state: "loading", "done" or "error".
  property bool popupOpened: false
  property string popupState: "loading"
  property string popupSource: ""
  property var popupResult: null
  property string popupError: ""
  property bool popupHovered: false
  property real pointerX: 0
  property real pointerY: 0
  property string queuedText: ""

  property bool historyOpened: false

  // ── Translating ──────────────────────────────────────────────────────────

  function translateSelection() {
    if (!grabProc.running) grabProc.running = true
  }

  function onGrabbed(raw) {
    var data = {}
    try { data = JSON.parse(raw) || {} } catch (e) {}
    var cursor = data.cursor && typeof data.cursor === "object" ? data.cursor : null
    var text = Model.cleanSource(data.text)

    // Same selection again while its card is up: treat the key as "dismiss".
    if (root.popupOpened && root.popupState === "done" && text === root.popupSource) {
      root.closePopup()
      return
    }

    root.showAt(cursor ? Number(cursor.x) : NaN, cursor ? Number(cursor.y) : NaN)
    if (!text) {
      root.popupSource = ""
      root.popupResult = null
      root.popupError = "nothing"
      root.popupState = "error"
      return
    }

    root.popupSource = text
    root.popupResult = null
    root.popupError = ""
    root.popupState = "loading"
    root.startCrow(text)
  }

  function startCrow(text) {
    if (crowProc.running) {
      // A newer selection wins; the old run is dropped when it exits.
      root.queuedText = text
      crowProc.running = false
      return
    }
    root.queuedText = ""
    crowProc.requestedText = text
    crowProc.command = ["timeout", "25", "crow", "-j", "-t", root.languages.join("+"), "--", text]
    crowProc.running = true
  }

  function onCrowExited(code) {
    if (root.queuedText) {
      var next = root.queuedText
      Qt.callLater(function() { root.startCrow(next) })
      return
    }
    if (crowProc.requestedText !== root.popupSource) return

    var result = code === 0 ? Model.pickResult(crowOut.text, root.languages) : null
    if (!result) {
      root.popupError = code === 124 ? "timeout" : "failed"
      root.popupState = "error"
      return
    }

    result.source = root.popupSource
    result.at = Date.now()
    root.popupResult = result
    root.popupState = "done"
    root.addHistory(result)
    if (root.copyResult) root.copyText(result.translation)
  }

  function copyText(text) {
    if (text) Quickshell.execDetached(["wl-copy", "--", text])
  }

  // ── Popup placement ──────────────────────────────────────────────────────

  function focusedScreen() {
    var monitor = Hyprland.focusedMonitor
    var name = monitor ? monitor.name : ""
    for (var i = 0; i < Quickshell.screens.length; i++)
      if (Quickshell.screens[i].name === name) return Quickshell.screens[i]
    return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
  }

  // hyprctl reports the pointer in layout coordinates, the same space the
  // screens' x/y/width/height live in.
  function showAt(x, y) {
    var screen = null
    if (isFinite(x) && isFinite(y)) {
      for (var i = 0; i < Quickshell.screens.length && !screen; i++) {
        var s = Quickshell.screens[i]
        if (x >= s.x && x < s.x + s.width && y >= s.y && y < s.y + s.height) screen = s
      }
    }
    if (!screen) {
      screen = root.focusedScreen()
      if (!screen) return
      x = screen.x + screen.width / 2
      y = screen.y + screen.height / 3
    }
    popup.screen = screen
    root.pointerX = x - screen.x
    root.pointerY = y - screen.y
    root.popupHovered = false
    root.popupOpened = true
  }

  function closePopup() {
    root.popupOpened = false
    root.popupHovered = false
  }

  // ── History ──────────────────────────────────────────────────────────────

  function addHistory(entry) {
    root.history = Model.addEntry(root.history, entry, Model.HISTORY_LIMIT)
    root.saveHistory()
  }

  function removeHistoryAt(index) {
    root.history = Model.removeEntryAt(root.history, index)
    root.saveHistory()
  }

  function clearHistory() {
    root.history = []
    root.saveHistory()
  }

  function saveHistory() {
    historyFile.setText(JSON.stringify(root.history, null, 2) + "\n")
  }

  function toggleHistory() {
    if (root.historyOpened) root.historyOpened = false
    else {
      root.closePopup()
      root.historyOpened = true
    }
  }

  // ── IPC, files, processes ────────────────────────────────────────────────

  ShellIpc {
    target: "drorko.translate"
    function translate(): string { root.translateSelection(); return "ok" }
    function history(): string { root.toggleHistory(); return "ok" }
    function close(): string { root.closePopup(); root.historyOpened = false; return "ok" }
    // For a "dismiss notification" key: closes the card and says whether
    // there was one, so the key can fall through to notifications otherwise.
    function dismiss(): string {
      if (!root.popupOpened) return "none"
      root.closePopup()
      return "closed"
    }
    function ping(): string { return "ok" }
  }

  FileView {
    id: historyFile
    path: root.historyPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.history = Model.parseHistory(text())
    onLoadFailed: root.history = []
    onFileChanged: reload()
  }

  FileView {
    path: root.settingsPath
    watchChanges: true
    printErrors: false
    onLoaded: root.settings = Model.parseSettings(text())
    onLoadFailed: root.settings = ({})
    onFileChanged: reload()
  }

  // Selection (primary, falling back to the clipboard) and pointer position,
  // read together so the card opens where the text was selected. The script is
  // fixed; the selected text only ever travels as data.
  Process {
    id: grabProc
    command: ["bash", "-c", [
      "t=$(timeout 2 wl-paste --primary --type text --no-newline 2>/dev/null | head -c 20000)",
      "[[ -n ${t//[[:space:]]/} ]] || t=$(timeout 2 wl-paste --type text --no-newline 2>/dev/null | head -c 20000)",
      "c=$(hyprctl -j cursorpos 2>/dev/null)",
      "jq -e 'type == \"object\"' >/dev/null 2>&1 <<<\"$c\" || c=null",
      "jq -cn --arg t \"$t\" --argjson c \"$c\" '{text: $t, cursor: $c}'"
    ].join("\n")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.onGrabbed(text)
    }
  }

  Process {
    id: crowProc
    property string requestedText: ""
    stdout: StdioCollector { id: crowOut; waitForEnd: true }
    onExited: function(exitCode) { Qt.callLater(function() { root.onCrowExited(exitCode) }) }
  }

  Timer {
    id: hideTimer
    interval: root.popupState === "done"
      ? Model.popupDuration(root.popupResult ? root.popupResult.translation : "")
      : 3500
    running: root.popupOpened && !root.popupHovered && root.popupState !== "loading"
    onTriggered: root.closePopup()
  }

  // ── Popup card next to the pointer ───────────────────────────────────────

  PanelWindow {
    id: popup
    visible: root.popupOpened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "drorko-translate"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    // Only the card takes clicks; everything around it reaches the windows below.
    mask: Region { item: card }

    TranslatePopup {
      id: card
      strings: strings
      phase: root.popupState
      source: root.popupSource
      result: root.popupResult
      error: root.popupError
      copied: root.copyResult
      readonly property var spot: Model.placeCard(root.pointerX, root.pointerY, width, height,
        popup.width, popup.height, Style.space(22))
      x: spot.x
      y: spot.y
      onHoveredChanged: root.popupHovered = hovered
      onCopyRequested: {
        if (root.popupResult) root.copyText(root.popupResult.translation)
        root.closePopup()
      }
      onDismissRequested: root.closePopup()
    }
  }

  // ── History overlay ──────────────────────────────────────────────────────

  HistoryOverlay {
    strings: strings
    opened: root.historyOpened
    history: root.history
    onCloseRequested: root.historyOpened = false
    onCopyRequested: function(text) {
      root.historyOpened = false
      root.copyText(text)
    }
    onRemoveRequested: function(index) { root.removeHistoryAt(index) }
    onClearRequested: root.clearHistory()
  }
}

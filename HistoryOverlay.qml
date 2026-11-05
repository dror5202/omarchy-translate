import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "TranslateModel.js" as Model

// Translation history, laid out like the clipboard manager: a filterable list
// on one side, the selected entry in full on the other.
//
//   type      filter        Enter        copy translation
//   ↑ ↓       move          Shift+Enter  copy original
//   Delete    remove        Shift+Delete clear all
Item {
  id: root

  property var strings
  property bool opened: false
  property var history: []

  signal closeRequested()
  signal copyRequested(string text)
  signal removeRequested(int index)
  signal clearRequested()

  property string filterText: ""
  property int selectedIndex: 0
  property bool clearConfirmOpen: false

  readonly property color background: Commons.Color.menu.background
  readonly property color foreground: Commons.Color.menu.text
  readonly property color border: Commons.Color.menu.border
  readonly property color selectedBackground: Commons.Color.menu.selectedBackground
  readonly property color selectedText: Commons.Color.menu.selectedText
  readonly property string fontFamily: Style.font.menuFamily
  readonly property int margin: Style.spacing.panelPadding
  readonly property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  readonly property int rowHeight: Math.max(Style.space(58), Style.font.body + Style.font.caption + Style.space(26))

  onOpenedChanged: {
    if (!opened) {
      root.clearConfirmOpen = false
      return
    }
    root.filterText = ""
    root.selectedIndex = 0
    pointerGate.reset()
    root.rebuild()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  onHistoryChanged: if (root.opened) root.rebuild()

  function rebuild() {
    var rows = Model.displayRows(root.history, root.filterText)
    rowsModel.clear()
    for (var i = 0; i < rows.length; i++) rowsModel.append(rows[i])
    root.selectedIndex = Math.max(0, Math.min(root.selectedIndex, rowsModel.count - 1))
    Qt.callLater(function() {
      if (rowsModel.count > 0) list.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  function setFilter(text) {
    root.filterText = text
    root.selectedIndex = 0
    root.rebuild()
  }

  function move(delta) {
    if (rowsModel.count === 0) return
    pointerGate.reset()
    root.selectedIndex = (root.selectedIndex + delta + rowsModel.count) % rowsModel.count
    list.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function current() {
    return rowsModel.count > 0 ? rowsModel.get(root.selectedIndex) : null
  }

  function stamp(at) {
    if (!at) return ""
    return new Date(at).toLocaleString(Qt.locale(Commons.I18n.formatLocale), "d MMM yyyy, HH:mm")
  }

  ListModel { id: rowsModel }

  PointerMoveGate { id: pointerGate; referenceItem: card }

  OverlayWindow {
    id: window
    shown: root.opened
    WlrLayershell.namespace: "drorko-translate-history"

    Rectangle { anchors.fill: parent; color: Commons.Color.menu.scrim }
    MouseArea { anchors.fill: parent; onClicked: root.closeRequested() }

    BorderSurface {
      id: card
      width: Math.min(Style.space(900), window.width - Style.gapsOut * 2)
      height: Math.min(Style.space(600), window.height - Style.gapsOut * 2)
      anchors.centerIn: parent
      radius: Style.cornerRadius
      color: root.background
      borderSpec: Border.surfaceSpec("menu", "border", root.border, Math.max(1, Style.space(2)))
      padding: root.margin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        z: root.clearConfirmOpen ? 20 : 0
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (root.clearConfirmOpen) {
            if (clearConfirm.handleKey(event)) event.accepted = true
            return
          }
          var row = root.current()
          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else root.closeRequested()
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
          } else if (event.key === Qt.Key_Delete) {
            if (event.modifiers & Qt.ShiftModifier) {
              if (root.history.length > 0) {
                clearConfirm.selectedIndex = 1
                root.clearConfirmOpen = true
              }
            } else if (row) {
              root.removeRequested(row.historyIndex)
            }
          } else if (event.key === Qt.Key_Up) {
            root.move(-1)
          } else if (event.key === Qt.Key_Down) {
            root.move(1)
          } else if (event.key === Qt.Key_PageUp) {
            root.move(-6)
          } else if (event.key === Qt.Key_PageDown) {
            root.move(6)
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (row) root.copyRequested((event.modifiers & Qt.ShiftModifier) ? row.source : row.translation)
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text)
          } else {
            return
          }
          event.accepted = true
        }

        ConfirmDialog {
          id: clearConfirm
          anchors.fill: parent
          opened: root.clearConfirmOpen
          z: 10
          message: root.strings.t("history.clearConfirm")
          confirmText: Commons.I18n.t("common.delete")
          background: root.background
          foreground: root.foreground
          scrim: Commons.Color.menu.scrim
          selectedBackground: root.selectedBackground
          selectedText: root.selectedText
          fontFamily: root.fontFamily
          onCanceled: {
            root.clearConfirmOpen = false
            keyCatcher.forceActiveFocus()
          }
          onConfirmed: {
            root.clearConfirmOpen = false
            root.clearRequested()
            keyCatcher.forceActiveFocus()
          }
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.spacing.md

        Item {
          width: parent.width
          height: root.headerHeight

          Text {
            anchors.left: parent.left
            anchors.right: hint.left
            anchors.rightMargin: root.margin
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.filterText || root.strings.t("history.search")
            color: root.foreground
            opacity: root.filterText ? 1 : 0.58
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            elide: Text.ElideRight
          }

          Text {
            id: hint
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.strings.t("history.hint")
            color: root.foreground
            opacity: 0.45
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Item {
          width: parent.width
          height: parent.height - root.headerHeight - Style.spacing.md

          Row {
            anchors.fill: parent
            visible: rowsModel.count > 0

            ListView {
              id: list
              width: parent.width / 2 - root.margin
              height: parent.height
              model: rowsModel
              clip: true
              spacing: Style.space(4)
              boundsBehavior: Flickable.StopAtBounds

              delegate: Rectangle {
                id: row
                required property int index
                required property string translationLine
                required property string sourceLine
                readonly property bool selected: index === root.selectedIndex

                width: ListView.view.width
                height: root.rowHeight
                radius: Style.cornerRadius
                color: selected ? root.selectedBackground : "transparent"

                Column {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(12)
                  anchors.rightMargin: Style.space(12)
                  anchors.topMargin: Style.space(8)
                  spacing: Style.space(4)

                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: row.translationLine
                    color: row.selected ? root.selectedText : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title
                    elide: Text.ElideRight
                    maximumLineCount: 1
                  }
                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: row.sourceLine
                    color: root.foreground
                    opacity: 0.55
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                    maximumLineCount: 1
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onPositionChanged: function(mouse) {
                    if (pointerGate.moved(row, mouse)) root.selectedIndex = row.index
                  }
                  onClicked: {
                    root.selectedIndex = row.index
                    var r = root.current()
                    if (r) root.copyRequested(r.translation)
                  }
                }
              }
            }

            Rectangle {
              width: Style.normalBorderWidth
              height: parent.height
              color: Util.alpha(root.border, 0.28)
            }

            Flickable {
              id: detail
              readonly property var entry: rowsModel.count > 0 && root.selectedIndex < rowsModel.count ? rowsModel.get(root.selectedIndex) : null
              width: parent.width / 2 + root.margin - Style.normalBorderWidth
              height: parent.height
              leftMargin: root.margin
              clip: true
              contentWidth: width - root.margin
              contentHeight: detailColumn.implicitHeight
              boundsBehavior: Flickable.StopAtBounds

              Column {
                id: detailColumn
                width: detail.width - root.margin
                spacing: Style.space(10)

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: detail.entry
                    ? root.strings.t("popup.direction").arg(detail.entry.fromName).arg(detail.entry.toName)
                      + (detail.entry.at ? "  ·  " + root.stamp(detail.entry.at) : "")
                    : ""
                  color: Commons.Color.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: detail.entry ? detail.entry.translation : ""
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  wrapMode: Text.Wrap
                }
                Rectangle {
                  width: parent.width
                  height: Style.normalBorderWidth
                  color: Util.alpha(root.border, 0.18)
                }
                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: detail.entry ? detail.entry.source : ""
                  color: root.foreground
                  opacity: 0.6
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  wrapMode: Text.Wrap
                }
              }
            }
          }

          Column {
            anchors.centerIn: parent
            width: parent.width - 2 * root.margin
            spacing: Style.space(8)
            visible: rowsModel.count === 0

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "󰗊"
              color: root.selectedText
              opacity: 0.8
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
            }
            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.history.length === 0
                ? root.strings.t("history.empty")
                : root.strings.t("history.noMatches").arg(root.filterText)
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              horizontalAlignment: Text.AlignHCenter
              elide: Text.ElideRight
            }
          }
        }
      }
    }
  }
}

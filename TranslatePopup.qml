import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The card shown next to the pointer: the translation, with the language pair
// above it. Left click copies it again and closes, right click just closes.
BorderSurface {
  id: card

  property var strings
  property string phase: "loading"   // loading | done | error
  property string source: ""
  property var result: null
  property string error: ""
  property bool copied: true
  readonly property bool hovered: mouse.containsMouse

  signal copyRequested()
  signal dismissRequested()

  readonly property int pad: Style.space(14)
  readonly property int minContent: Style.space(200)
  readonly property int maxContent: Style.space(440)

  readonly property string bodyText: {
    if (card.phase === "done" && card.result) return card.result.translation
    if (card.phase === "loading") return card.source
    if (card.error === "nothing") return card.strings.t("popup.nothingSelected")
    if (card.error === "timeout") return card.strings.t("popup.timeout")
    return card.strings.t("popup.failed")
  }

  readonly property string captionText: {
    if (card.phase === "loading") return card.strings.t("popup.translating")
    if (card.phase === "done" && card.result) {
      var direction = card.strings.t("popup.direction").arg(card.result.fromName).arg(card.result.toName)
      return card.copied ? card.strings.t("popup.directionCopied").arg(direction) : direction
    }
    return card.strings.t("popup.title")
  }

  readonly property int contentWidth: Math.max(card.minContent, Math.min(card.maxContent,
    Math.ceil(Math.max(bodyMetrics.advanceWidth, captionMetrics.advanceWidth)) + 2))

  width: card.borderLeft + card.pad + card.contentWidth + card.pad + card.borderRight
  height: card.borderTop + card.pad + content.implicitHeight + card.pad + card.borderBottom
  color: Util.alpha(Commons.Color.background, 0.97)
  borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Math.max(1, Style.space(2)))
  radius: Style.cornerRadius

  TextMetrics {
    id: bodyMetrics
    font.family: Style.font.family
    font.pixelSize: Style.font.title
    text: card.bodyText.split("\n")[0]
  }

  TextMetrics {
    id: captionMetrics
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    text: card.captionText
  }

  Column {
    id: content
    x: card.borderLeft + card.pad
    y: card.borderTop + card.pad
    width: card.contentWidth
    spacing: Style.space(6)

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: card.captionText
      color: card.phase === "error" ? Commons.Color.urgent : Commons.Color.accent
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
      maximumLineCount: 1
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: card.bodyText
      color: Commons.Color.popups.text
      opacity: card.phase === "done" ? 1 : 0.6
      font.family: Style.font.family
      font.pixelSize: Style.font.title
      wrapMode: Text.Wrap
      maximumLineCount: card.phase === "loading" ? 2 : 14
      elide: Text.ElideRight
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: card.phase === "done" ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: function(event) {
      if (event.button === Qt.LeftButton && card.phase === "done") card.copyRequested()
      else card.dismissRequested()
    }
  }
}

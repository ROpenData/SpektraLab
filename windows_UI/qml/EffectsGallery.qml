import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import SpektraLab.Native 1.0

// Modal film comparison for the current photo. A large live-tier view shows
// the selected film at real detail (pan/zoom, double-click fit/100%), while
// a bottom strip of every catalog film switches the view instantly. Click a
// strip cell to compare, double-click / Enter / the apply button to apply
// that film to the current photo, Escape to leave without changes.
Popup {
    id: galleryPopup
    objectName: "effectsGallery"
    anchors.centerIn: parent
    width: Math.min(parent.width * 0.96, 1500)
    height: Math.min(parent.height * 0.96, 980)
    padding: 14
    modal: true; focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    onVisibleChanged: window.updateDialogState()

    property int selectedFilm: preview.filmIndex
    // The cell being compared; its image is a (possibly null) QImage until
    // the live-tier render arrives, so readiness uses the flag, not null.
    readonly property var selectedCell: preview.galleryFilms.length > selectedFilm ? preview.galleryFilms[selectedFilm] : null
    onSelectedFilmChanged: Qt.callLater(function() { bigView.resetView(true) })

    // Close the popup before switching the film: the film setter refuses
    // changes while a modal dialog is registered as open.
    function applyFilm(catalogIndex) {
        if (preview.galleryBusy) return
        galleryPopup.close()
        preview.filmIndex = catalogIndex
    }
    function moveSelection(delta) {
        const count = preview.galleryFilms.length
        if (count <= 0) return
        selectedFilm = ((selectedFilm + delta) % count + count) % count
    }

    // Only active while the popup is visible; shortcuts are window-scoped.
    Shortcut { sequence: "Left"; enabled: galleryPopup.visible; onActivated: galleryPopup.moveSelection(-1) }
    Shortcut { sequence: "Right"; enabled: galleryPopup.visible; onActivated: galleryPopup.moveSelection(1) }
    Shortcut { sequence: "Return"; enabled: galleryPopup.visible && !preview.galleryBusy; onActivated: galleryPopup.applyFilm(galleryPopup.selectedFilm) }

    contentItem: ColumnLayout {
        spacing: 10
        RowLayout {
            Layout.fillWidth: true; spacing: 10
            Text { text: "胶片效果总览"; color: Theme.text; font.pixelSize: 19; font.bold: true }
            Text {
                color: Theme.accent; font.pixelSize: 12
                text: galleryPopup.selectedCell ? galleryPopup.selectedCell.name : ""
            }
            Item { Layout.fillWidth: true }
            Text {
                color: Theme.muted; font.pixelSize: 11
                text: preview.galleryBusy
                    ? "正在生成 " + preview.galleryProgress + " / " + preview.galleryTotal + " …"
                    : "←/→ 切换对比 · 双击或 Enter 应用 · 滚轮缩放 · 双击全图/100%"
            }
            ActionButton {
                text: "应用此胶片"; accented: true; implicitHeight: 28
                enabled: !preview.galleryBusy && preview.galleryFilms.length > 0
                onClicked: galleryPopup.applyFilm(galleryPopup.selectedFilm)
            }
            ActionButton { text: "关闭"; implicitHeight: 28; onClicked: galleryPopup.close() }
        }
        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.line; opacity: 0.5 }

        // Large comparison view: the full live-tier render at real detail.
        Item {
            Layout.fillWidth: true; Layout.fillHeight: true; clip: true
            FrameCanvas {
                id: bigView
                objectName: "effectsBigView"
                anchors.fill: parent
                image: galleryPopup.selectedCell ? galleryPopup.selectedCell.image : preview.emptyImage
                enabled: galleryPopup.visible && !preview.galleryBusy
            }
            Text {
                anchors.centerIn: parent
                visible: !(galleryPopup.selectedCell && galleryPopup.selectedCell.ready)
                text: preview.galleryBusy ? "生成中…" : "未生成"
                color: Theme.muted; font.pixelSize: 13
            }
            Rectangle {
                anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 10
                width: 96; height: 20; radius: 2; color: "#b32d2d2c"
                visible: galleryPopup.selectedCell && galleryPopup.selectedCell.ready
                Text { anchors.centerIn: parent; text: bigView.scalePercent.toFixed(0) + "%"; color: Theme.text; font.pixelSize: 9 }
            }
        }

        // Bottom strip: every catalog film for instant switching.
        ListView {
            id: strip
            objectName: "effectsStrip"
            Layout.fillWidth: true; Layout.preferredHeight: 128
            orientation: ListView.Horizontal; spacing: 6; clip: true
            model: preview.galleryFilms
            currentIndex: galleryPopup.selectedFilm
            onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
            ScrollBar.horizontal: ScrollBar {}
            delegate: Rectangle {
                required property var modelData
                required property int index
                width: 148; height: strip.height - 4
                radius: 5; color: Theme.wellDark
                border.width: index === galleryPopup.selectedFilm ? 2 : modelData.catalogIndex === preview.filmIndex ? 1 : 1
                border.color: index === galleryPopup.selectedFilm ? Theme.accent
                    : modelData.catalogIndex === preview.filmIndex ? Theme.text : Theme.line
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 5; spacing: 2
                    Item {
                        Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                        FrameCanvas { anchors.fill: parent; image: modelData.image; enabled: false }
                        Text {
                            anchors.centerIn: parent; visible: !modelData.ready
                            text: preview.galleryBusy ? "…" : "—"; color: Theme.muted; font.pixelSize: 10
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 3
                        Text { Layout.fillWidth: true; text: modelData.name; color: index === galleryPopup.selectedFilm ? Theme.accent : Theme.text; font.pixelSize: 10; elide: Text.ElideRight }
                        Rectangle {
                            visible: modelData.positive; width: 28; height: 13; radius: 2
                            border.color: Theme.line; border.width: 1; color: "transparent"
                            Text { anchors.centerIn: parent; text: "正片"; color: Theme.muted; font.pixelSize: 8 }
                        }
                        Text { visible: modelData.catalogIndex === preview.filmIndex; text: "当前"; color: Theme.accent; font.pixelSize: 9 }
                    }
                }
                MouseArea {
                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: galleryPopup.selectedFilm = modelData.catalogIndex
                    onDoubleClicked: galleryPopup.applyFilm(modelData.catalogIndex)
                }
            }
        }

        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.line; opacity: 0.5; visible: preview.galleryBusy }
        RowLayout {
            Layout.fillWidth: true; visible: preview.galleryBusy; spacing: 10
            ProgressBar { Layout.fillWidth: true; from: 0; to: Math.max(1, preview.galleryTotal); value: preview.galleryProgress }
            ActionButton { text: "取消生成"; onClicked: preview.cancelEffectsGallery() }
        }
    }
}

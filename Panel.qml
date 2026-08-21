import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root

  moduleName: "dev.alexandre.moonlight-sunshine"
  ipcTarget: "dev.alexandre.moonlight-sunshine"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  readonly property string scriptPath: {
    var path = String(Qt.resolvedUrl("bin/omarchy-moonlight-sunshine"))
    if (path.indexOf("file://") === 0) path = path.substring(7)
    return decodeURIComponent(path)
  }

  property var hosts: []
  property var profileNames: ["LAN"]
  property string activeProfile: "LAN"
  property var presetNames: ["Desktop", "Gaming", "Low bandwidth", "Remote Desktop"]
  property string selectedPreset: "Desktop"
  property string statusText: "Scanning for Sunshine hosts…"
  property string label: "󰍹"
  property string tooltipText: "Moonlight Sunshine"
  property bool refreshing: false

  property bool profileFormVisible: false
  property bool settingsVisible: false
  property string profileFormName: ""
  property bool hostFormVisible: false
  property bool hostFormEditing: false
  property string hostFormKey: ""
  property string hostFormName: ""
  property string hostFormAddress: ""
  property string hostFormPort: "47989"
  property string hostFormApp: "Desktop"
  property string hostFormApps: "Desktop"
  property bool hostFormFavorite: false

  function open() {
    root.controller.show()
    root.refresh()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function refresh() {
    if (snapshotProc.running || mutationProc.running) return
    refreshing = true
    statusText = "Scanning profile " + root.activeProfile + "…"
    snapshotProc.command = [root.scriptPath, "snapshot", "--wait", "1.2"]
    snapshotProc.running = true
  }

  function runMutation(args) {
    if (mutationProc.running) return
    mutationProc.command = [root.scriptPath].concat(args)
    mutationProc.running = true
  }

  function selectProfile(name) {
    if (!name || name === root.activeProfile) return
    root.closeHostForm()
    root.runMutation(["profile-select", String(name)])
  }

  function addProfile() {
    var name = root.profileFormName.trim()
    if (!name) return
    root.profileFormVisible = false
    root.profileFormName = ""
    root.runMutation(["profile-add", name, "--from-profile", root.activeProfile])
  }

  function beginAddHost(host) {
    root.hostFormVisible = true
    root.hostFormEditing = !!(host && host.saved)
    root.hostFormKey = root.hostFormEditing ? String(host.id) : ""
    root.hostFormName = host ? String(host.name || host.address || "") : ""
    root.hostFormAddress = host ? String(host.address || "") : ""
    root.hostFormPort = host ? String(host.port || 47989) : "47989"
    root.hostFormApp = host ? String(host.app || "Desktop") : "Desktop"
    root.hostFormApps = host && host.apps ? host.apps.join(", ") : root.hostFormApp
    root.hostFormFavorite = host ? host.favorite === true : false
  }

  function closeHostForm() {
    root.hostFormVisible = false
    root.hostFormEditing = false
    root.hostFormKey = ""
  }

  function saveHost() {
    var key = root.hostFormEditing ? root.hostFormKey.trim() : root.hostFormName.trim()
    var label = root.hostFormName.trim() || key
    var address = root.hostFormAddress.trim()
    if (!key || !address) return

    var args = [
      "remember", key, address,
      "--port", root.hostFormPort.trim() || "47989",
      "--app", root.hostFormApp.trim() || "Desktop",
      "--apps", root.hostFormApps.trim() || root.hostFormApp.trim() || "Desktop",
      "--label", label,
      "--profile", root.activeProfile,
      root.hostFormFavorite ? "--favorite" : "--unfavorite"
    ]
    root.closeHostForm()
    root.runMutation(args)
  }

  function forgetHost(host) {
    root.runMutation(["forget", String(host.id), "--profile", root.activeProfile])
  }

  function toggleFavorite(host) {
    root.runMutation([
      "favorite", String(host.id), host.favorite ? "off" : "on",
      "--profile", root.activeProfile
    ])
  }

  function connect(host, appName) {
    var preset = host.preset || root.selectedPreset
    root.close()
    Quickshell.execDetached([
      root.scriptPath, "connect", String(host.id), String(appName || host.app || "Desktop"),
      "--preset", preset, "--profile", root.activeProfile
    ])
  }

  function runInTerminal(action, host) {
    var args = [root.scriptPath, action, String(host.id), "--profile", root.activeProfile]
    var command = args.map(function(value) {
      return Util.shellQuote(String(value))
    }).join(" ")
    root.close()
    Quickshell.execDetached(["bash", "-lc", "omarchy-launch-floating-terminal-with-presentation " + command])
  }

  function parseSnapshot(raw) {
    try {
      var data = JSON.parse(String(raw || "{}"))
      root.hosts = data.hosts || []
      root.profileNames = data.profileNames || [data.activeProfile || "LAN"]
      root.activeProfile = data.activeProfile || root.profileNames[0] || "LAN"
      root.presetNames = data.presetNames || ["Desktop", "Gaming", "Low bandwidth"]
      if (root.presetNames.indexOf(root.selectedPreset) < 0)
        root.selectedPreset = root.presetNames[0] || "Desktop"
      root.refreshing = false

      var discovered = root.hosts.filter(function(host) { return host.online }).length
      var count = root.hosts.length
      root.label = count > 0 ? "󰍹 " + count : "󰍹"
      root.tooltipText = count > 0
        ? root.activeProfile + " · " + count + " Sunshine host" + (count === 1 ? "" : "s")
        : "No Sunshine hosts discovered"
      if (data.moonlightInstalled !== true)
        root.statusText = "Moonlight is not installed on this client"
      else if (data.discoveryError)
        root.statusText = data.discoveryError
      else if (count === 0)
        root.statusText = "No Sunshine hosts found on the local network"
      else if (discovered > 0)
        root.statusText = discovered + " online · click Stream to connect"
      else
        root.statusText = count + " saved · refresh to check local discovery"
    } catch (error) {
      root.refreshing = false
      root.statusText = "Could not read the Sunshine scan"
    }
  }

  Process {
    id: snapshotProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseSnapshot(text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.refreshing = false
        root.statusText = "Could not scan for Sunshine hosts"
      }
    }
  }

  Process {
    id: mutationProc
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.statusText = "Could not save the Moonlight change"
      }
      root.refresh()
    }
  }

  IpcHandler {
    target: root.ipcTarget
    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.toggle() }
    function refresh() { root.refresh() }
  }

  Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  PopupCard {
    id: popup
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    triggerMode: "click"
    contentWidth: Style.space(500)
    contentHeight: Math.min(Style.space(760), Math.max(Style.space(260), hostColumn.implicitHeight + Style.space(8)))

    Flickable {
      anchors.fill: parent
      contentWidth: width
      contentHeight: hostColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      Column {
        id: hostColumn
        width: parent.width
        spacing: Style.space(10)

        Row {
          width: parent.width
          spacing: Style.space(8)

          Column {
            width: parent.width - refreshButton.width - addHostHeaderButton.width - settingsButton.width - Style.space(24)
            spacing: Style.space(2)
            Text {
              text: "Sunshine hosts"
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Text {
              width: parent.width
              text: root.statusText
              color: Color.foreground
              opacity: 0.62
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }

          Rectangle {
            id: refreshButton
            width: Style.space(34)
            height: Style.space(34)
            radius: Style.cornerRadius
            color: refreshMouse.containsMouse
              ? Style.hoverFillFor(Color.foreground, Color.accent)
              : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
            Text {
              anchors.centerIn: parent
              text: root.refreshing ? "…" : "󰑐"
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.heading
            }
            MouseArea {
              id: refreshMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.refresh()
            }
          }

          Rectangle {
            id: addHostHeaderButton
            width: Style.space(34)
            height: Style.space(34)
            radius: Style.cornerRadius
            color: addHostHeaderMouse.containsMouse
              ? Style.hoverFillFor(Color.foreground, Color.accent)
              : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
            Text {
              anchors.centerIn: parent
              text: "+"
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.title
            }
            MouseArea {
              id: addHostHeaderMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.beginAddHost(null)
            }
          }

          Rectangle {
            id: settingsButton
            width: Style.space(34)
            height: Style.space(34)
            radius: Style.cornerRadius
            color: settingsMouse.containsMouse || root.settingsVisible
              ? Style.hoverFillFor(Color.foreground, Color.accent)
              : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
            Text {
              anchors.centerIn: parent
              text: "󰒓"
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.heading
            }
            MouseArea {
              id: settingsMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.settingsVisible = !root.settingsVisible
            }
          }
        }

        BorderSurface {
          visible: root.settingsVisible
          width: parent.width
          height: settingsColumn.implicitHeight + Style.space(16)
          radius: Style.spacing.labelGap
          color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.04)
          borderSpec: Border.localOrSurfaceSpec("popups", "border", Color.popups.border, Color.popups.border, Math.max(1, Style.space(1)))

          Column {
            id: settingsColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(8)
            spacing: Style.space(7)

            Text {
              text: "Connection settings"
              color: Color.foreground
              opacity: 0.68
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            Row {
              width: parent.width
              spacing: Style.space(7)

              Text {
                text: "Profile"
                width: Style.space(52)
                color: Color.foreground
                opacity: 0.62
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
              }

              ComboBox {
                id: profileCombo
                width: parent.width - Style.space(94)
                model: root.profileNames
                currentIndex: Math.max(0, root.profileNames.indexOf(root.activeProfile))
                onActivated: root.selectProfile(currentText)
              }

              Rectangle {
                width: Style.space(28)
                height: Style.spacing.controlHeight
                radius: Style.cornerRadius
                color: profileAddMouse.containsMouse
                  ? Style.hoverFillFor(Color.foreground, Color.accent)
                  : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
                Text { anchors.centerIn: parent; text: "+"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body }
                MouseArea {
                  id: profileAddMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.profileFormVisible = !root.profileFormVisible
                }
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(7)

              Text {
                text: "Preset"
                width: Style.space(52)
                color: Color.foreground
                opacity: 0.62
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
              }

              ComboBox {
                id: presetCombo
                width: parent.width - Style.space(59)
                model: root.presetNames
                currentIndex: Math.max(0, root.presetNames.indexOf(root.selectedPreset))
                onActivated: {
                  root.selectedPreset = currentText
                  root.statusText = root.activeProfile + " · " + root.selectedPreset + " preset"
                }
              }
            }
          }
        }

        Row {
          visible: root.profileFormVisible
          width: parent.width
          spacing: Style.space(8)
          TextField {
            id: profileNameField
            width: parent.width - addProfileButton.width - Style.space(8)
            placeholderText: "Profile name, e.g. VPN"
            text: root.profileFormName
            onTextChanged: if (root.profileFormName !== text) root.profileFormName = text
            onAccepted: root.addProfile()
          }
          Rectangle {
            id: addProfileButton
            width: Style.space(92)
            height: profileNameField.height
            radius: Style.cornerRadius
            color: Color.accent
            Text { anchors.centerIn: parent; text: "Create"; color: Color.background; font.family: Style.font.family; font.pixelSize: Style.font.caption; font.bold: true }
            MouseArea { anchors.fill: parent; onClicked: root.addProfile() }
          }
        }

        BorderSurface {
          visible: root.hostFormVisible
          width: parent.width
          height: hostFormColumn.implicitHeight + Style.space(20)
          radius: Style.cornerRadius
          color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.06)
          borderSpec: Border.localOrSurfaceSpec("popups", "border", Color.popups.border, Color.popups.border, Math.max(1, Style.space(1)))

          Column {
            id: hostFormColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(10)
            spacing: Style.space(7)

            Text {
              text: root.hostFormEditing ? "Edit saved host" : "Add Sunshine host"
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
            }
            Row {
              width: parent.width
              spacing: Style.space(7)
              TextField {
                id: hostNameField
                width: parent.width * 0.42
                placeholderText: "Friendly name"
                text: root.hostFormName
                onTextChanged: if (root.hostFormName !== text) root.hostFormName = text
              }
              TextField {
                id: hostAddressField
                width: parent.width * 0.58 - Style.space(7)
                placeholderText: "Hostname or IP"
                text: root.hostFormAddress
                onTextChanged: if (root.hostFormAddress !== text) root.hostFormAddress = text
              }
            }
            Row {
              width: parent.width
              spacing: Style.space(7)
              TextField {
                id: hostPortField
                width: Style.space(90)
                placeholderText: "Port"
                text: root.hostFormPort
                onTextChanged: if (root.hostFormPort !== text) root.hostFormPort = text
              }
              TextField {
                id: hostAppField
                width: parent.width - hostPortField.width - Style.space(7)
                placeholderText: "Default app, e.g. Desktop"
                text: root.hostFormApp
                onTextChanged: if (root.hostFormApp !== text) root.hostFormApp = text
              }
            }
            TextField {
              id: hostAppsField
              width: parent.width
              placeholderText: "Quick apps, comma-separated: Desktop, Steam"
              text: root.hostFormApps
              onTextChanged: if (root.hostFormApps !== text) root.hostFormApps = text
            }
            Row {
              width: parent.width
              spacing: Style.space(8)
              Rectangle {
                width: Style.space(104)
                height: Style.spacing.controlHeight
                radius: Style.cornerRadius
                color: root.hostFormFavorite ? Color.accent : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
                Text { anchors.centerIn: parent; text: root.hostFormFavorite ? "★ Favorite" : "☆ Favorite"; color: root.hostFormFavorite ? Color.background : Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
                MouseArea { anchors.fill: parent; onClicked: root.hostFormFavorite = !root.hostFormFavorite }
              }
              Rectangle {
                width: Style.space(72)
                height: Style.spacing.controlHeight
                radius: Style.cornerRadius
                color: Color.accent
                Text { anchors.centerIn: parent; text: "Save"; color: Color.background; font.family: Style.font.family; font.pixelSize: Style.font.caption; font.bold: true }
                MouseArea { anchors.fill: parent; onClicked: root.saveHost() }
              }
              Rectangle {
                width: Style.space(76)
                height: Style.spacing.controlHeight
                radius: Style.cornerRadius
                color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
                Text { anchors.centerIn: parent; text: "Cancel"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
                MouseArea { anchors.fill: parent; onClicked: root.closeHostForm() }
              }
            }
          }
        }

        Rectangle {
          visible: root.hosts.length === 0
          width: parent.width
          height: Style.space(68)
          color: "transparent"
          Text {
            anchors.fill: parent
            text: "No hosts in this profile yet. Use Add host to save a LAN or VPN address, or keep Sunshine running and refresh discovery."
            color: Color.foreground
            opacity: 0.65
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }
        }

        Repeater {
          model: root.hosts

          BorderSurface {
            id: hostCard
            required property var modelData
            width: hostColumn.width
            height: hostBody.implicitHeight + Style.space(18)
            radius: Style.spacing.labelGap
            color: modelData.favorite
              ? Style.selectedFillFor(Color.foreground, Color.accent)
              : "transparent"
            borderSpec: Border.localOrSurfaceSpec("popups", "border", Color.popups.border, Color.popups.border, Math.max(1, Style.space(1)))

            Column {
              id: hostBody
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.space(11)
              spacing: Style.space(8)

              Row {
                width: parent.width
                spacing: Style.space(8)
                Text {
                  width: parent.width - stateBadge.width - Style.space(8)
                  text: hostCard.modelData.name || hostCard.modelData.address
                  color: Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.subtitle
                  font.bold: true
                  elide: Text.ElideRight
                  anchors.verticalCenter: parent.verticalCenter
                }
                Rectangle {
                  id: stateBadge
                  width: stateBadgeText.implicitWidth + Style.space(12)
                  height: Style.space(20)
                  radius: height / 2
                  color: hostCard.modelData.online
                    ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.16)
                    : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
                  anchors.verticalCenter: parent.verticalCenter
                  Text {
                    id: stateBadgeText
                    anchors.centerIn: parent
                    text: hostCard.modelData.online ? "ONLINE" : (hostCard.modelData.saved ? "SAVED" : "OFFLINE")
                    color: hostCard.modelData.online ? Color.accent : Color.foreground
                    opacity: hostCard.modelData.online ? 1.0 : 0.58
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                }
              }

              Row {
                width: parent.width
                spacing: Style.space(5)
                Text {
                  text: hostCard.modelData.address
                  color: Color.foreground
                  opacity: 0.62
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                  width: parent.width - defaultAppText.implicitWidth - presetChip.width - Style.space(15)
                }
                Text {
                  text: "·"
                  color: Color.foreground
                  opacity: 0.4
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
                Text {
                  id: defaultAppText
                  text: hostCard.modelData.app
                  color: Color.foreground
                  opacity: 0.62
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
                Rectangle {
                  id: presetChip
                  visible: !!hostCard.modelData.preset
                  width: visible ? presetChipText.implicitWidth + Style.space(10) : 0
                  height: Style.space(18)
                  radius: height / 2
                  color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.07)
                  Text {
                    id: presetChipText
                    anchors.centerIn: parent
                    text: hostCard.modelData.preset || ""
                    color: Color.foreground
                    opacity: 0.56
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }
              }

              Flow {
                width: parent.width
                spacing: Style.space(6)

                Rectangle {
                  width: Style.space(86)
                  height: Style.space(30)
                  radius: Style.cornerRadius
                  opacity: hostCard.modelData.online || hostCard.modelData.saved ? 1.0 : 0.42
                  color: streamMouse.containsMouse
                    ? Style.hoverFillFor(Color.foreground, Color.accent)
                    : Color.accent
                  Text { anchors.centerIn: parent; text: "Stream"; color: Color.background; font.family: Style.font.family; font.pixelSize: Style.font.caption; font.bold: true }
                  MouseArea {
                    id: streamMouse
                    anchors.fill: parent
                    enabled: hostCard.modelData.online || hostCard.modelData.saved
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.connect(hostCard.modelData, hostCard.modelData.app)
                  }
                }

                Rectangle {
                  width: Style.space(58)
                  height: Style.space(30)
                  radius: Style.cornerRadius
                  color: appsMouse.containsMouse
                    ? Style.hoverFillFor(Color.foreground, Color.accent)
                    : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
                  Text { anchors.centerIn: parent; text: "Apps"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
                  MouseArea {
                    id: appsMouse
                    anchors.fill: parent
                    enabled: hostCard.modelData.online || hostCard.modelData.saved
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.runInTerminal("list", hostCard.modelData)
                  }
                }

                Rectangle {
                  width: Style.space(58)
                  height: Style.space(30)
                  radius: Style.cornerRadius
                  color: pairMouse.containsMouse
                    ? Style.hoverFillFor(Color.foreground, Color.accent)
                    : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
                  Text { anchors.centerIn: parent; text: "Pair"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
                  MouseArea {
                    id: pairMouse
                    anchors.fill: parent
                    enabled: hostCard.modelData.online || hostCard.modelData.saved
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.runInTerminal("pair", hostCard.modelData)
                  }
                }

                Repeater {
                  model: hostCard.modelData.apps || []
                  Rectangle {
                    required property string modelData
                    visible: modelData !== hostCard.modelData.app
                    width: Math.max(Style.space(58), appLabel.implicitWidth + Style.space(18))
                    height: Style.space(30)
                    radius: Style.cornerRadius
                    color: appMouse.containsMouse
                      ? Style.hoverFillFor(Color.foreground, Color.accent)
                      : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
                    Text {
                      id: appLabel
                      anchors.centerIn: parent
                      text: modelData
                      color: Color.foreground
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                    MouseArea {
                      id: appMouse
                      anchors.fill: parent
                      enabled: hostCard.modelData.online || hostCard.modelData.saved
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.connect(hostCard.modelData, modelData)
                    }
                  }
                }
              }

              Flow {
                width: parent.width
                spacing: Style.space(5)

                Rectangle {
                  width: Style.space(92)
                  height: Style.space(24)
                  radius: Style.cornerRadius
                  color: favoriteMouse.containsMouse
                    ? Style.hoverFillFor(Color.foreground, Color.accent)
                    : "transparent"
                  Text { anchors.centerIn: parent; text: hostCard.modelData.favorite ? "★ Favorite" : "☆ Favorite"; color: Color.foreground; opacity: hostCard.modelData.saved ? 0.72 : 0.35; font.family: Style.font.family; font.pixelSize: Style.font.caption }
                  MouseArea {
                    id: favoriteMouse
                    anchors.fill: parent
                    enabled: hostCard.modelData.saved
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleFavorite(hostCard.modelData)
                  }
                }

                Rectangle {
                  width: Style.space(58)
                  height: Style.space(24)
                  radius: Style.cornerRadius
                  color: editMouse.containsMouse
                    ? Style.hoverFillFor(Color.foreground, Color.accent)
                    : "transparent"
                  Text { anchors.centerIn: parent; text: hostCard.modelData.saved ? "Edit" : "Save"; color: Color.foreground; opacity: 0.68; font.family: Style.font.family; font.pixelSize: Style.font.caption }
                  MouseArea {
                    id: editMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.beginAddHost(hostCard.modelData)
                  }
                }

                Rectangle {
                  visible: hostCard.modelData.saved
                  width: Style.space(64)
                  height: Style.space(24)
                  radius: Style.cornerRadius
                  color: forgetMouse.containsMouse
                    ? Style.hoverFillFor(Color.foreground, Color.accent)
                    : "transparent"
                  Text { anchors.centerIn: parent; text: "Forget"; color: Color.foreground; opacity: 0.5; font.family: Style.font.family; font.pixelSize: Style.font.caption }
                  MouseArea {
                    id: forgetMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.forgetHost(hostCard.modelData)
                  }
                }
              }
            }
          }
        }

        Rectangle {
          width: Style.space(120)
          height: Style.spacing.controlHeight
          radius: Style.cornerRadius
          color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
          Text { anchors.centerIn: parent; text: "＋ Add host"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
          MouseArea { anchors.fill: parent; onClicked: root.beginAddHost(null) }
        }

        Text {
          width: parent.width
          text: "Middle-click the bar icon to rescan · profiles keep LAN and VPN addresses separate"
          color: Color.foreground
          opacity: 0.48
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}

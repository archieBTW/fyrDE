import QtQuick 2.15
import QtQuick.Controls 2.15
import QtGraphicalEffects 1.15
import QtQuick.Layouts 1.15

Rectangle {
    id: root
    width: Screen.width
    height: Screen.height
    color: "black"

    function updateUserAssets() {
        var selectedUser = "";
        
        if (userModel.count === 1) {
            selectedUser = userModel.data(userModel.index(0, 0), Qt.UserRole + 1);
        } else {
            selectedUser = usernameBox.currentText;
        }

        for (var i = 0; i < userModel.count; ++i) {
            if (userModel.data(userModel.index(i, 0), Qt.UserRole + 1) === selectedUser) {
                var userHome = userModel.data(userModel.index(i, 0), Qt.UserRole + 3) || "";
                var iconFromModel = userModel.data(userModel.index(i, 0), Qt.UserRole + 4) || "";
                var cleanHome = userHome.replace(/^file:\/\//, "");
                
                var timestamp = new Date().getTime();
                
                if (iconFromModel !== "") {
                    avatar.source = (iconFromModel.startsWith("/") ? "file://" + iconFromModel : iconFromModel) + "?nocache=" + timestamp;
                } else if (userHome !== "") {
                    avatar.source = "file://" + cleanHome + "/.face.icon?nocache=" + timestamp;
                } else {
                    avatar.source = "face.png";
                }

                bg.source = "file://" + cleanHome + "/.config/fyr/lockscreen.jpg?nocache=" + timestamp;
                break;
            }
        }
    }

    Component.onCompleted: updateUserAssets()

    // Background Image
    Image {
        id: bg
        anchors.fill: parent
        source: config.background || "space.jpg"
        fillMode: Image.PreserveAspectCrop
        visible: false
        cache: false
        onStatusChanged: {
            if (status == Image.Error) {
                source = config.background || "space.jpg";
            }
        }
    }

    // Blurred Background
    FastBlur {
        anchors.fill: parent
        source: bg
        radius: 100
        cached: true
    }

    // Dark Overlay
    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: 0.4
    }

    // Login Center Container
    Column {
        anchors.centerIn: parent
        spacing: 40
        width: 350

        // Profile Picture (Circle)
        Item {
            width: 160
            height: 160
            anchors.horizontalCenter: parent.horizontalCenter

            Image {
                id: avatar
                anchors.fill: parent
                source: "face.png"
                fillMode: Image.PreserveAspectCrop
                visible: false
                cache: false
                onStatusChanged: {
                    if (status == Image.Error) {
                        source = "face.png"
                    }
                }
            }

            Rectangle {
                id: mask
                anchors.fill: parent
                radius: width / 2
                visible: false
            }

            OpacityMask {
                anchors.fill: avatar
                source: avatar
                maskSource: mask
            }

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: "transparent"
                border.color: "white"
                border.width: 3
                opacity: 0.6
            }
        }

        // Username Display/Input
        Column {
            width: parent.width
            spacing: 10

            ComboBox {
                id: usernameBox
                width: parent.width
                model: userModel
                textRole: "name"
                currentIndex: userModel.lastIndex
                font.pointSize: 14
                visible: userModel.count > 1
                onCurrentTextChanged: updateUserAssets()
                
                popup: Popup {
                    y: usernameBox.height - 1
                    width: usernameBox.width
                    height: contentItem.implicitHeight
                    padding: 1
                    
                    contentItem: ListView {
                        clip: true
                        implicitHeight: contentHeight
                        model: usernameBox.delegateModel
                        currentIndex: usernameBox.highlightedIndex
                        highlightMoveDuration: 0
                    }
                    
                    background: Rectangle {
                        color: "#1A1A1A"
                        border.color: "white"
                        border.width: 1
                        radius: 12
                    }
                }
                
                background: Rectangle {
                    color: "white"
                    opacity: 0.1
                    radius: 12
                    border.color: usernameBox.activeFocus ? "#6200EE" : "transparent"
                    border.width: 2
                }
                
                contentItem: Text {
                    leftPadding: 15
                    text: usernameBox.displayText
                    font: usernameBox.font
                    color: "white"
                    verticalAlignment: Text.AlignVCenter
                }
            }

            TextField {
                id: singleUsername
                width: parent.width
                text: userModel.count === 1 ? userModel.data(userModel.index(0, 0), Qt.UserRole + 1) : ""
                font.pointSize: 14
                color: "white"
                readOnly: true
                visible: userModel.count === 1
                background: Rectangle {
                    color: "white"
                    opacity: 0.1
                    radius: 12
                    border.color: "transparent"
                    border.width: 2
                }
            }

            TextField {
                id: password
                width: parent.width
                placeholderText: "Password"
                echoMode: TextInput.Password
                focus: true
                font.pointSize: 14
                color: "white"
                selectionColor: "#6200EE"
                selectedTextColor: "white"
                renderType: Text.NativeRendering
                background: Rectangle {
                    color: "white"
                    opacity: 0.1
                    radius: 12
                    border.color: parent.activeFocus ? "#6200EE" : "transparent"
                    border.width: 2
                }
                onAccepted: sddm.login(userModel.count > 1 ? usernameBox.currentText : singleUsername.text, password.text, sessionBox.currentIndex)
            }
        }

        Button {
            id: loginButton
            width: 150
            height: 40
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Login"
            onClicked: sddm.login(userModel.count > 1 ? usernameBox.currentText : singleUsername.text, password.text, sessionBox.currentIndex)
            
            contentItem: Text {
                text: loginButton.text
                font.pointSize: 12
                font.bold: true
                color: "white"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            background: Rectangle {
                color: loginButton.pressed ? "white" : "transparent"
                opacity: loginButton.pressed ? 0.2 : 1.0
                radius: 10
                border.color: "white"
                border.width: 1
            }
        }

        Text {
            id: errorMessage
            anchors.horizontalCenter: parent.horizontalCenter
            color: "#FF5252"
            font.pointSize: 12
            text: ""
        }
    }

    // Bottom Right Controls
    Row {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 60
        spacing: 15

        ComboBox {
            id: sessionBox
            width: 180
            height: 45
            model: sessionModel
            textRole: "name"
            currentIndex: sessionModel.lastIndex
            font.pointSize: 11
            
            popup: Popup {
                y: -height
                width: sessionBox.width
                height: contentItem.implicitHeight
                padding: 1
                
                contentItem: ListView {
                    clip: true
                    implicitHeight: contentHeight
                    model: sessionBox.delegateModel
                    currentIndex: sessionBox.highlightedIndex
                    highlightMoveDuration: 0
                }
                
                background: Rectangle {
                    color: "#1A1A1A"
                    border.color: "white"
                    border.width: 1
                    radius: 10
                }
            }
            
            background: Rectangle {
                color: "white"
                opacity: 0.1
                radius: 10
            }
            
            contentItem: Text {
                leftPadding: 15
                text: sessionBox.displayText
                font: sessionBox.font
                color: "white"
                verticalAlignment: Text.AlignVCenter
            }
        }

        Button {
            id: restartBtn
            width: 45
            height: 45
            onClicked: sddm.reboot()
            background: Rectangle {
                color: "white"
                opacity: 0.1
                radius: 10
            }
            contentItem: Text {
                text: "⟳"
                font.pointSize: 18
                color: "white"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                opacity: 0.8
            }
        }

        Button {
            id: shutdownBtn
            width: 45
            height: 45
            onClicked: sddm.powerOff()
            background: Rectangle {
                color: "white"
                opacity: 0.1
                radius: 10
            }
            contentItem: Text {
                text: "⏻"
                font.pointSize: 18
                color: "white"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                opacity: 0.8
            }
        }
    }

    Connections {
        target: sddm
        onLoginFailed: {
            errorMessage.text = "Login failed"
            password.text = ""
            password.focus = true
        }
    }
}

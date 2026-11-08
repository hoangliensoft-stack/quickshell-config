// One Quickshell process for the whole desktop UI.
// Run: qs -c desktop
//   Switcher.qml  - window switcher   (ipc target "coverflow": next|prev|release|confirm|cancel|swipeUp|swipeDown|state)
//   Launcher.qml  - app launcher      (ipc target "launcher":  toggle|open|hide|search|state|slowmo)
import QtQuick
import Quickshell

ShellRoot {
    Switcher {}
    Launcher {}
}

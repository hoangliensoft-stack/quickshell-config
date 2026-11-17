// One Quickshell process for the whole desktop UI.
// Run: qs -c desktop          (after editing QML: ./restart.sh)
//   Switcher.qml  - window switcher   (ipc target "coverflow": next|prev|release|confirm|cancel|swipeUp|swipeDown|state)
//   Launcher.qml  - app launcher      (ipc target "launcher":  toggle|open|hide|search|state|slowmo)
import QtQuick
import Quickshell

ShellRoot {
    // No hot reload: Quickshell 0.3.2 never frees the old config generation after a reload, and
    // until it does every `qs ipc call` answers "Not ready to accept queries yet" -> Alt+Tab,
    // the launcher and the swipe gestures stop working. Apply QML edits with a restart instead:
    //   ~/.config/quickshell/desktop/restart.sh
    settings.watchFiles: false

    Switcher {}
    Launcher {}
}

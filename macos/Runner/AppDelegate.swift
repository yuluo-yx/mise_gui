import Cocoa
import FlutterMacOS
import Darwin

@main
class AppDelegate: FlutterAppDelegate {
  override init() {
    super.init()
    // Finder / LaunchServices launches can leave stdio in a state where a
    // framework write triggers SIGPIPE and kills the app before any crash
    // report is produced. Ignore SIGPIPE so those writes surface as regular
    // I/O errors instead of terminating the process.
    signal(SIGPIPE, SIG_IGN)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // Keep the app alive if the initial window fails to stay visible on a
    // target machine. This prevents an immediate "flash and quit" experience
    // and lets users reopen the main window from the Dock.
    return false
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    guard !flag, let window = mainFlutterWindow else {
      return false
    }

    sender.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(self)
    window.orderFrontRegardless()
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}

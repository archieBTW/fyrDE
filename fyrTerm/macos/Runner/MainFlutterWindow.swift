// import Cocoa
// import FlutterMacOS

// class MainFlutterWindow: NSWindow {
//   override func awakeFromNib() {
//     let flutterViewController = FlutterViewController()
//     let windowFrame = self.frame
//     self.contentViewController = flutterViewController
//     self.setFrame(windowFrame, display: true)

//     self.titleVisibility = .hidden
//     self.titlebarAppearsTransparent = true
    
//     // Expand the Flutter content to fill the entire window (including where the title bar used to be)
//     self.styleMask.insert(.fullSizeContentView)
    
//     // Hide the default macOS traffic light buttons so they don't overlap with your custom ones
//     self.standardWindowButton(.closeButton)?.isHidden = true
//     self.standardWindowButton(.miniaturizeButton)?.isHidden = true
//     self.standardWindowButton(.zoomButton)?.isHidden = true
    
//     // Optional: Make the window background transparent if you want rounded corners
//     // to render properly via your Flutter UI
//     self.isOpaque = false
//     self.backgroundColor = .clear

//     RegisterGeneratedPlugins(registry: flutterViewController)

//     super.awakeFromNib()
//   }
// }

import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.styleMask.insert(.fullSizeContentView)
    self.isOpaque = false
    self.backgroundColor = .clear

    // THE FIX:
    // Instead of hiding the buttons themselves, we hide their entire parent container. 
    // This prevents macOS or the window_manager plugin from forcing them back 
    // onto the screen when the app initializes or the window resizes.
    if let closeButton = self.standardWindowButton(.closeButton) {
        closeButton.superview?.isHidden = true
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
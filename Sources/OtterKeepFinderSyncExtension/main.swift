import Foundation
import Cocoa
import FinderSync
import OtterKeepCore

/// Native Apple AppExtension entrypoint invoked by macOS PluginKit daemon (pkd).
@_silgen_name("NSExtensionMain")
func NSExtensionMain() -> Int32

_ = NSExtensionMain()

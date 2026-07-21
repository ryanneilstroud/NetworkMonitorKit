Pod::Spec.new do |s|
  s.name         = "PeriscopeKit"
  s.version      = "1.2.0"
  s.summary      = "Capture URLSession traffic for Periscope viewers."
  s.description  = "PeriscopeKit captures URLSession HTTP and native WebSocket activity for Periscope viewers."
  s.homepage     = "https://github.com/ryanneilstroud/PeriscopeKit"
  s.license      = { :type => "MIT", :file => "LICENSE" }
  s.author       = { "ryanneilstroud" => "ryanneilstroud@users.noreply.github.com" }
  # CocoaPods distribution is currently iOS-only. SwiftPM supports iOS and macOS.
  s.platforms    = { :ios => "15.0" }
  s.source       = { :git => "https://github.com/ryanneilstroud/PeriscopeKit.git", :tag => "v#{s.version}" }

  s.source_files = "*.{swift}"
  s.exclude_files = "Package.swift"
  s.requires_arc = true
  s.swift_version = "5.10"
end

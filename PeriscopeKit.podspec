Pod::Spec.new do |s|
  s.name         = "PeriscopeKit"
  s.version      = "0.5.1"
  s.summary      = "Capture URLSession traffic for NetworkMonitor viewers."
  s.description  = "PeriscopeKit captures URLSession events and forwards them to a viewer over TCP."
  s.homepage     = "https://github.com/ryanneilstroud/PeriscopeKit"
  s.license      = { :type => "MIT" }
  s.author       = { "ryanneilstroud" => "ryanneilstroud@users.noreply.github.com" }
  # CocoaPods distribution is currently iOS-only. SwiftPM supports iOS and macOS.
  s.platforms    = { :ios => "15.0" }
  s.source       = { :git => "https://github.com/ryanneilstroud/PeriscopeKit.git", :tag => s.version.to_s }

  s.source_files = "*.{swift}"
  s.exclude_files = "Package.swift"
  s.requires_arc = true
  s.swift_version = "5.10"
end

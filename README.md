# NetworkMonitorKit

`NetworkMonitorKit` captures `URLSession` traffic and forwards events to a network monitor viewer.

## Install

### Swift Package Manager

Add this package as a dependency in Xcode, then include `NetworkMonitorKit` in your app target.

### CocoaPods

```ruby
pod 'NetworkMonitorKit', :git => 'https://github.com/ryanneilstroud/NetworkMonitorKit.git', :tag => '0.3.0'
```

## Usage

```swift
import NetworkMonitorKit

NetworkMonitor.observe(port: 61337) // host defaults to localhost
```

If you create custom `URLSessionConfiguration` instances:

```swift
NetworkMonitor.inject(into: configuration)
```

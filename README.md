# PeriscopeKit

`PeriscopeKit` captures `URLSession` traffic and forwards events to a network monitor viewer.

## Install

### Swift Package Manager

Add this package as a dependency in Xcode, then include `PeriscopeKit` in your app target.

### CocoaPods

```ruby
pod 'PeriscopeKit', :git => 'https://github.com/ryanneilstroud/PeriscopeKit.git', :tag => '0.5.0'
```

## Usage

```swift
import PeriscopeKit

Periscope.capture(
    for: .simulator() // defaults to localhost:61337
)
```

### Receiver constructors

`Periscope.Receiver` has two static constructors:

1. `Receiver.simulator(port:)` for local simulator development (routes to localhost).
2. `Receiver.device(host:port:)` for explicit host routing, especially physical devices.

```swift
// Local simulator development
Periscope.capture(
    for: .simulator()
)

// Physical device targeting your Mac's LAN IP
Periscope.capture(
    for: .device(host: "192.168.1.25")
)
```

Both methods default to port `61337`.

### Stop capture

When you need to stop forwarding events:

```swift
Periscope.stop()
```

### API change in 0.5.0

`capture(host:port:)` was removed in `0.5.0` in favor of the receiver-based API:

```swift
Periscope.capture(for: .simulator())
```

If you create custom `URLSessionConfiguration` instances:

```swift
Periscope.inject(into: configuration)
```

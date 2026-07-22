# PeriscopeKit

`PeriscopeKit` captures `URLSession` HTTP traffic and can automatically observe native
`URLSessionWebSocketTask` activity for debugging.

## Install

### Swift Package Manager

Add this package as a dependency in Xcode, then include `PeriscopeKit` in your app target.

### CocoaPods

```ruby
pod 'PeriscopeKit', :git => 'https://github.com/ryanneilstroud/PeriscopeKit.git', :tag => 'v1.2.0'
```

## Quick Start

```swift
import PeriscopeKit

Periscope.capture(for: .simulator) // uses Periscope.default
```

Calling `capture(for:)` also installs automatic native WebSocket observation when
the current Foundation runtime is supported. Existing `URLSessionWebSocketTask`
construction and send/receive calls do not need to change. Query
`Periscope.webSocketCaptureAvailability` to diagnose runtime compatibility.

The initial WebSocket proof of concept observes application-level text and binary
messages from Apple's native WebSocket task. It does not observe Starscream,
Socket.IO, `NWConnection`, WebKit, raw frames, or TCP packets.
Captured native WebSocket lifecycle and message events are delivered to compatible
Periscope 1.2 viewers. Message payloads are limited to 64 KiB per event; the
original byte count and truncation state are retained.

## Usage

You can also create your own instance:

```swift
let periscope = Periscope()
periscope.capture(for: .simulator)
```

Capture transport is process-wide. If multiple `Periscope` instances call `capture(for:)`, only the first active capture session is applied until `stop()` is called.

### Receiver constructors

`Periscope.Receiver` has static constructors:

1. `Receiver.simulator` for local simulator development (routes to localhost, default port).
2. `Receiver.simulator(port:)` for local simulator development with a custom port.
3. `Receiver.device(host:port:)` for explicit host routing, especially physical devices.

```swift
// Local simulator development
Periscope.capture(for: .simulator)

// Physical device targeting your Mac's LAN IP
Periscope.capture(for: .device(host: "192.168.1.25"))
```

`Receiver.simulator` and `Receiver.device(host:port:)` both default to port `61337`.

### Stop capture

When you need to stop forwarding events:

```swift
Periscope.stop() // stops Periscope.default
```

### API change in 0.5.0

`capture(host:port:)` was removed in `0.5.0` in favor of the receiver-based API:

```swift
Periscope.capture(for: .simulator)
```

If you create custom `URLSessionConfiguration` instances:

```swift
Periscope.inject(into: configuration)
```

# NetworkMonitorKit

`NetworkMonitorKit` captures `URLSession` traffic and forwards events to a network monitor viewer.

## Install

Add this package as a dependency in Xcode, then include `NetworkMonitorKit` in your app target.

## Usage

```swift
import NetworkMonitorKit

NetworkMonitor.start(port: 61337) // host defaults to localhost
```

If you create custom `URLSessionConfiguration` instances:

```swift
NetworkMonitor.inject(into: configuration)
```

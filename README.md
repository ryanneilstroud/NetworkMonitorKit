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
    for: .device(host: "localhost") // port defaults to 61337
)
```

If you create custom `URLSessionConfiguration` instances:

```swift
Periscope.inject(into: configuration)
```

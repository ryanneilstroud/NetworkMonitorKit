# PeriscopeKit

`PeriscopeKit` captures `URLSession` traffic and forwards events to a network monitor viewer.

## Install

### Swift Package Manager

Add this package as a dependency in Xcode, then include `PeriscopeKit` in your app target.

### CocoaPods

```ruby
pod 'PeriscopeKit', :git => 'https://github.com/ryanneilstroud/PeriscopeKit.git', :tag => '0.3.0'
```

## Usage

```swift
import PeriscopeKit

Periscope.observe(port: 61337) // host defaults to localhost
```

If you create custom `URLSessionConfiguration` instances:

```swift
Periscope.inject(into: configuration)
```

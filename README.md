# swift-observations

![Development Status](https://img.shields.io/badge/status-active--development-blue.svg)

Observation tracking for Swift value types — an `@Observable` macro and `withObservationTracking(_:onChange:)` that work on structs, `~Copyable` structs, classes, and actors.

## Quick Start

Apple's Observation framework restricts `@Observable` to classes. This package attaches it to value types:

```swift
import Observations

@Observable
struct Download {
    var progress: Double = 0
    var isComplete: Bool = false
}

var download = Download()

_ = withObservationTracking {
    download.progress
} onChange: {
    print("progress changed")
}

download.progress = 0.5   // prints "progress changed"
download.isComplete = true // untracked — no output
```

`onChange` fires exactly once, on the first mutation of any property read inside the tracking body. To keep tracking, call `withObservationTracking` again from `onChange`. The callback may run on whichever thread performs the mutation.

In a multi-statement tracking body, force each read with an explicit consume (`let _ = download.progress`) — a bare property reference at statement position may be elided by the compiler. Single-expression bodies are unambiguous.

## Installation

Add swift-observations to your `Package.swift` (no version tags are published yet; pin to `main`):

```swift
dependencies: [
    .package(url: "https://github.com/swift-foundations/swift-observations.git", branch: "main")
]
```

Add the product to your target:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "Observations", package: "swift-observations")
    ]
)
```

### Requirements

- Swift 6.3+ toolchain
- macOS 26+, iOS 26+, tvOS 26+, watchOS 26+, visionOS 26+

## Key Features

- **Value-type subjects** — `@Observable` attaches to structs, `~Copyable` structs, classes, and actors; per-property identifiers are assigned in declaration order, so they are stable across recompiles.
- **One-shot change tracking** — `withObservationTracking(_:onChange:)` records every tracked read in a per-thread frame and installs one-shot didSet handlers; the first mutation wins and all sibling handlers are unsubscribed without firing.
- **RAII subscriptions** — `Observation.Subscription.Token` is a `~Copyable` handle that unsubscribes on `deinit`; the type system guarantees the unsubscribe runs exactly once, and `detach()` transfers ownership to a longer-lived registry.
- **Manual observation without the macro** — the underlying `Observation.Registrar` surface is re-exported, so hand-authored `_read` accessors can call `Observation.Tracking.access(_:_:)` directly.

## Usage Examples

### Scoped subscriptions with `Token`

A bare `Observation.Registrar.subscribe(to:didSet:)` returns an ID the caller must remember to unsubscribe. The token removes that contract:

```swift
import Observations

let registrar = Observation.Registrar()
do {
    let token = Observation.Subscription.Token(
        registrar,
        registrar.subscribe(to: [.init(0)], didSet: { _ in print("property 0 mutated") })
    )
    // ... observe ...
}
// token deinits at scope exit; the observer is unsubscribed.
```

### Hand-authored tracked accessors

Types that cannot take the macro can participate in tracking by recording reads themselves:

```swift
import Observations

struct Gauge {
    let registrar = Observation.Registrar()
    var _level: Int = 0

    var level: Int {
        _read {
            Observation.Tracking.access(registrar, .init(0))
            yield _level
        }
        set {
            _level = newValue
            registrar.didSet(.init(0))
        }
    }
}
```

## Architecture

| Type | Purpose |
|------|---------|
| `@Observable` | Macro — synthesizes the registrar field, `Observable` conformance, and tracked accessors for every stored `var` |
| `withObservationTracking(_:onChange:)` | Records reads in the body; fires `onChange` once on the first tracked mutation |
| `Observation.Tracking.access(_:_:)` | Records a single read against the active tracking frame (no-op when none is active) |
| `Observation.Subscription.Token` | `~Copyable` RAII handle — unsubscribes on `deinit`, `detach()` to transfer ownership |
| `Observation.Registrar` (re-exported) | Subscribe/notify core from Observation Primitives |

Tracking frames are thread-local: synchronous code on the same thread sees the active frame; an async hop to another thread does not carry it. Nested `withObservationTracking` calls stack — only the innermost frame records.

## Community

<!-- BEGIN: discussion -->
*Discussion thread will be created at first public release.*
<!-- END: discussion -->

## License

Apache 2.0 — see [LICENSE](LICENSE.md).

// ===----------------------------------------------------------------------===//
//
// This source file is part of the swift-observations open source project
//
// Copyright (c) 2024-2026 Coen ten Thije Boonkkamp and the swift-observations
// project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// ===----------------------------------------------------------------------===//

import Foundation
import Testing

@testable import Observations

/// Thread-safe holder for mutable test state captured in `@Sendable` closures.
final class Box<T: Sendable>: @unchecked Sendable {
    private var _value: T
    private let lock = NSObject()

    init(_ initial: T) { self._value = initial }

    var value: T {
        get { objc_sync_enter(lock); defer { objc_sync_exit(lock) }; return _value }
    }

    func mutate(_ body: (inout T) -> Void) {
        objc_sync_enter(lock); defer { objc_sync_exit(lock) }
        body(&_value)
    }
}

/// A small Subject under observation. Hand-authored — the macro will
/// generate this shape automatically once it ships.
struct Counter: Observable {
    let _$registrar: Observation.Registrar
    var _x: Int
    var _y: Int

    init() {
        self._$registrar = Observation.Registrar()
        self._x = 0
        self._y = 0
    }

    var x: Int {
        _read {
            Observation.Tracking.access(_$registrar, .init(0))
            yield _x
        }
        _modify {
            _$registrar.willSet(.init(0))
            yield &_x
            _$registrar.didSet(.init(0))
        }
    }

    var y: Int {
        _read {
            Observation.Tracking.access(_$registrar, .init(1))
            yield _y
        }
        _modify {
            _$registrar.willSet(.init(1))
            yield &_y
            _$registrar.didSet(.init(1))
        }
    }
}

@Suite("Observation.Tracking")
struct TrackingTests {
    @Suite struct ContextCapture {}
    @Suite struct WithObservationTracking {}
    @Suite struct Token {}
}

extension TrackingTests.ContextCapture {

    @Test
    func `access outside withObservationTracking is a no-op`() {
        // Without an active frame, access(_:_:) does nothing — no
        // crash, no recorded state.
        let counter = Counter()
        Observation.Tracking.access(counter._$registrar, .init(0))
        // No assertion needed; the absence of a trap is the property.
    }

    @Test
    func `currentFrame is nil outside withObservationTracking`() {
        #expect(Observation.Tracking.currentFrame() == nil)
    }
}

extension TrackingTests.WithObservationTracking {

    @Test
    func `onChange fires when a tracked property mutates`() {
        var counter = Counter()
        let fired = Box(false)

        let value = withObservationTracking {
            counter.x
        } onChange: {
            fired.mutate { $0 = true }
        }
        #expect(value == 0)
        #expect(fired.value == false)  // Not fired yet — no mutation.

        counter.x = 1
        #expect(fired.value == true)
    }

    @Test
    func `onChange does NOT fire for untracked property mutation`() {
        var counter = Counter()
        let fired = Box(false)

        _ = withObservationTracking {
            counter.x  // Track only x.
        } onChange: {
            fired.mutate { $0 = true }
        }

        counter.y = 1  // Mutate y — not tracked.
        #expect(fired.value == false)
    }

    @Test
    func `onChange fires once even with multiple tracked mutations`() {
        var counter = Counter()
        let fireCount = Box(0)

        _ = withObservationTracking {
            _ = counter.x
            _ = counter.y
        } onChange: {
            fireCount.mutate { $0 += 1 }
        }

        counter.x = 1
        counter.y = 2
        counter.x = 3
        #expect(fireCount.value == 1)
    }

    @Test
    func `repeated reads of same property dedupe to one subscription`() {
        var counter = Counter()
        let fireCount = Box(0)

        _ = withObservationTracking {
            _ = counter.x
            _ = counter.x
            _ = counter.x
        } onChange: {
            fireCount.mutate { $0 += 1 }
        }

        counter.x = 99
        #expect(fireCount.value == 1)
    }

    @Test
    func `body return value is propagated`() {
        var counter = Counter()
        counter.x = 42

        let result = withObservationTracking {
            counter.x * 2
        } onChange: {
            // unused
        }
        #expect(result == 84)
    }

    @Test
    func `nested withObservationTracking — only inner records`() {
        var counter = Counter()
        let outerFired = Box(false)
        let innerFired = Box(false)

        _ = withObservationTracking {
            // Outer body — but the inner withObservationTracking will
            // shadow this frame for any access inside its body.
            return withObservationTracking {
                counter.x  // Recorded against the inner frame.
            } onChange: {
                innerFired.mutate { $0 = true }
            }
        } onChange: {
            outerFired.mutate { $0 = true }
        }

        counter.x = 1
        #expect(innerFired.value == true)
        #expect(outerFired.value == false)  // Outer recorded nothing.
    }

    @Test
    func `multiple registrars in one body`() {
        let a = Counter()
        var b = Counter()
        let fired = Box(false)

        _ = withObservationTracking {
            _ = a.x
            _ = b.y
        } onChange: {
            fired.mutate { $0 = true }
        }

        b.y = 1  // Mutating either should fire.
        #expect(fired.value == true)
    }
}

extension TrackingTests.Token {

    @Test
    func `Token unsubscribes on deinit`() {
        let registrar = Observation.Registrar()
        let fireCount = Box(0)

        do {
            let id = registrar.subscribe(
                to: [.init(0)],
                didSet: { _ in fireCount.mutate { $0 += 1 } }
            )
            _ = Observation.Subscription.Token(registrar, id)
        }
        // Token deinit'd; subscription removed.
        registrar.didSet(.init(0))
        #expect(fireCount.value == 0)
    }

    @Test
    func `Token detach disarms the deinit`() {
        let registrar = Observation.Registrar()
        let fireCount = Box(0)

        let detached: (Observation.Registrar, Observation.Subscription.ID)?
        do {
            let id = registrar.subscribe(
                to: [.init(0)],
                didSet: { _ in fireCount.mutate { $0 += 1 } }
            )
            var token = Observation.Subscription.Token(registrar, id)
            detached = token.detach()
        }
        // Token deinit'd as a no-op (detached); subscription is still live.
        registrar.didSet(.init(0))
        #expect(fireCount.value == 1)

        // Cleanup: caller is now responsible for the detached subscription.
        if let (r, id) = detached { r.unsubscribe(id) }
    }

    @Test
    func `Token detach twice returns nil the second time`() {
        let registrar = Observation.Registrar()
        let id = registrar.subscribe(to: [.init(0)])
        var token = Observation.Subscription.Token(registrar, id)

        let first = token.detach()
        let second = token.detach()
        #expect(first != nil)
        #expect(second == nil)

        // Cleanup the first detach.
        if let (r, id) = first { r.unsubscribe(id) }
    }
}

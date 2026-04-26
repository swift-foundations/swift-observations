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

internal import Synchronization

/// Tracks the property reads performed by `apply` and invokes
/// `onChange` exactly once when any tracked property next mutates.
///
/// Mirrors Apple's `withObservationTracking(_:onChange:)` — the
/// observation framework's read/write witness. Differences:
/// - Records reads via static ``Observation/Tracking/access(_:_:)``
///   calls in hand-authored `_read` accessors (or, in the future,
///   `@Observable` macro-generated ones).
/// - Backed by `Kernel.Thread.Local` storage rather than
///   `_ThreadLocal`, so it composes with the rest of the ecosystem
///   per [PLAT-ARCH-006].
///
/// ## Semantics
///
/// 1. Push a fresh tracking frame onto the calling thread.
/// 2. Run `apply()`; every property read that calls
///    `Observation.Tracking.access(_:_:)` is recorded against the
///    frame.
/// 3. Pop the frame.
/// 4. For each unique `(registrar, propertyID)` pair recorded,
///    register a **one-shot** didSet handler. The first to fire
///    invokes `onChange()`; all the others are unsubscribed without
///    firing.
///
/// `onChange` may run on any thread — whichever thread mutates the
/// first tracked property. It is `@Sendable` for that reason.
///
/// `onChange` runs at most once per `withObservationTracking` call.
/// If you need to re-track, call again from `onChange`.
///
/// ## Reading observable properties in `apply`
///
/// To register tracking, the body MUST actually read the value of
/// each observable property. A bare property reference at statement
/// position may be elided by the compiler in multi-statement
/// closures; use an explicit consume:
///
/// ```swift
/// withObservationTracking {
///     let _ = subject.x
///     let _ = subject.y
/// } onChange: { ... }
/// ```
///
/// Single-expression closures (`{ subject.x }`) are unambiguous —
/// the implicit return forces the read.
///
/// The forthcoming `@Observable` macro sidesteps this for
/// macro-generated accessors, but the user-authored body of
/// `withObservationTracking` is still subject to this rule.
///
/// - Parameters:
///   - apply: The body whose tracked property reads to record.
///   - onChange: One-shot callback fired the first time any tracked
///     property mutates after `apply` returns.
/// - Returns: The result of `apply()`.
public func withObservationTracking<R>(
    _ apply: () -> R,
    onChange: @escaping @Sendable () -> Void
) -> R {
    let frame = Observation.Tracking.Frame(parent: Observation.Tracking.currentFrame())
    Observation.Tracking.pushFrame(frame)
    let result = apply()
    Observation.Tracking.popFrame(frame)

    let accesses = frame.accesses
    guard !accesses.isEmpty else { return result }

    // One-shot, atomic-fired box: the first didSet fires onChange,
    // and all sibling subscriptions are unsubscribed without firing.
    let _ = Observation.Tracking._installOneShot(
        accesses: accesses,
        onChange: onChange
    )

    return result
}

extension Observation.Tracking {
    /// Per-tracking-call shared state for the one-shot dispatch:
    /// `fired` is set true by the winner thread; the array of
    /// `(registrar, subscriptionID)` is consulted on fire to
    /// unsubscribe siblings.
    final class _OneShot: @unchecked Sendable {
        let fired: Mutex<Bool>
        let registrations: Mutex<[(Observation.Registrar, Observation.Subscription.ID)]>
        let onChange: @Sendable () -> Void

        init(onChange: @escaping @Sendable () -> Void) {
            self.fired = Mutex(false)
            self.registrations = Mutex([])
            self.onChange = onChange
        }
    }

    /// Subscribes a one-shot didSet handler for every recorded access
    /// and returns a holder that the registrations close over. The
    /// holder is captured by the per-subscription closures, not
    /// returned to the caller — its lifetime is the lifetime of the
    /// outstanding subscriptions.
    @discardableResult
    static func _installOneShot(
        accesses: [ObjectIdentifier: (registrar: Observation.Registrar, properties: Set<Observation.Property.ID>)],
        onChange: @escaping @Sendable () -> Void
    ) -> _OneShot {
        let oneShot = _OneShot(onChange: onChange)

        var subscriptions: [(Observation.Registrar, Observation.Subscription.ID)] = []
        for (_, value) in accesses {
            let registrar = value.registrar
            let properties = value.properties

            let id = registrar.subscribe(
                to: properties,
                didSet: { @Sendable [oneShot] _ in
                    oneShot.fire()
                }
            )
            subscriptions.append((registrar, id))
        }

        oneShot.registrations.withLock { $0 = subscriptions }
        return oneShot
    }
}

extension Observation.Tracking._OneShot {
    /// Idempotent fire: the first caller wins, runs `onChange`, and
    /// unsubscribes all sibling registrations. Subsequent callers
    /// see `fired == true` and short-circuit.
    func fire() {
        let didFireFirst = fired.withLock { fired -> Bool in
            if fired {
                return false
            }
            fired = true
            return true
        }
        guard didFireFirst else { return }

        let registrationsCopy = registrations.withLock { $0 }
        for (registrar, id) in registrationsCopy {
            registrar.unsubscribe(id)
        }
        onChange()
    }
}

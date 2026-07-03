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

internal import Ownership_Latch_Primitives
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

  Observation.Tracking._installOneShot(accesses: accesses, onChange: onChange)

  return result
}

extension Observation.Tracking {
  /// Subscribes a one-shot didSet handler for every recorded access.
  ///
  /// The first didSet to fire wins via
  /// ``Ownership/Latch/take()`` — its CAS atomically
  /// transitions the latch from `.full` to `.taken`, runs the
  /// cleanup closure (which unsubscribes every recorded
  /// registration and invokes `onChange`), and disarms all sibling
  /// fires. Subsequent fires see `.taken` and short-circuit to
  /// `nil`.
  ///
  /// The latch and its captured cleanup closure are held alive by
  /// the per-subscription `[latch]` captures; once all
  /// subscriptions are unsubscribed (by the winning fire), the
  /// captures release and the latch deinits.
  @discardableResult
  static func _installOneShot(
    accesses: [ObjectIdentifier: (
      registrar: Observation.Registrar, properties: Set<Observation.Property.ID>
    )],
    onChange: @escaping @Sendable () -> Void
  ) -> Ownership.Latch<@Sendable () -> Void> {
    // Subscriptions are accumulated as the loop registers them;
    // the cleanup closure reads the list at fire-time. A fire
    // that races the registration loop sees a partial list and
    // unsubscribes only the registrations recorded so far —
    // matching the existing `Mutex<[Registration]>` behavior.
    let pending: Mutex<[(Observation.Registrar, Observation.Subscription.ID)]> = Mutex([])

    let cleanup: @Sendable () -> Void = {
      let ids = pending.withLock { $0 }
      for (registrar, id) in ids {
        registrar.unsubscribe(id)
      }
      onChange()
    }

    let latch = Ownership.Latch<@Sendable () -> Void>(cleanup)

    for (_, value) in accesses {
      let registrar = value.registrar
      let properties = value.properties
      let id = registrar.subscribe(
        to: properties,
        didSet: { @Sendable [latch] _ in
          latch.take()?()
        }
      )
      pending.withLock { $0.append((registrar, id)) }
    }

    return latch
  }
}

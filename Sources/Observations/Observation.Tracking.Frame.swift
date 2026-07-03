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

extension Observation.Tracking {
  /// One activation record of an in-flight
  /// ``withObservationTracking(_:onChange:)`` body.
  ///
  /// The frame accumulates the
  /// `(Observation.Registrar, Observation.Property.ID)` accesses
  /// recorded during the body. After the body returns, the
  /// withObservationTracking primitive walks the frame's accesses
  /// and registers a one-shot didSet handler for each unique
  /// `(registrar, propertyID)` pair, then discards the frame.
  ///
  /// Frames stack via `parent` to support nested tracking. Only
  /// the innermost (current) frame records accesses; outer frames
  /// remain dormant until their nested body returns.
  ///
  /// ## Why a class?
  ///
  /// Frames live in `Kernel.Thread.Local` storage as opaque pointers,
  /// bridged via `Unmanaged`. A reference type gives a stable
  /// pointer identity for the slot's lifetime; the retain/release
  /// pair on push/pop balances the slot's strong reference. A
  /// struct would need explicit heap allocation anyway, so the
  /// class form is direct.
  final class Frame {
    /// The frame underneath this one on the same thread, or `nil`
    /// if this is the outermost active frame.
    let parent: Frame?

    /// Accumulated `(registrar, propertyID)` accesses recorded by
    /// `Tracking.access(_:_:)` while this frame was current.
    ///
    /// `[ObjectIdentifier: (Observation.Registrar, Set<Property.ID>)]`
    /// — the dictionary keys deduplicate by registrar identity
    /// (same Subject across struct copies); the per-registrar Set
    /// deduplicates property reads within the body.
    var accesses:
      [ObjectIdentifier: (
        registrar: Observation.Registrar, properties: Set<Observation.Property.ID>
      )] = [:]

    init(parent: Frame?) {
      self.parent = parent
    }

    /// Records a property read on this frame.
    ///
    /// `O(1)` amortized: dictionary lookup + Set insert.
    func record(_ registrar: Observation.Registrar, _ propertyID: Observation.Property.ID) {
      let key = registrar.id
      if accesses[key] != nil {
        accesses[key]!.properties.insert(propertyID)
      } else {
        accesses[key] = (registrar, [propertyID])
      }
    }
  }
}

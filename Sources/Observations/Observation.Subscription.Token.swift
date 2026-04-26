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

extension Observation.Subscription {
    /// `~Copyable` RAII handle wrapping a
    /// (``Observation/Registrar``, ``Observation/Subscription/ID``)
    /// pair.
    ///
    /// On `deinit`, the token unsubscribes its observer from the
    /// registrar — eliminating the
    /// "caller-must-retain-and-explicitly-unsubscribe" contract of
    /// the bare ``Observation/Subscription/ID``.
    ///
    /// Because the token is `~Copyable`, the type system enforces
    /// single-ownership: the token cannot be duplicated, only moved
    /// or consumed. The deinit fires exactly once.
    ///
    /// Use ``detach()`` to release the token without unsubscribing —
    /// e.g., to transfer ownership of the subscription to a long-
    /// lived registry that will unsubscribe later.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let registrar = Observation.Registrar()
    /// do {
    ///     let token = Observation.Subscription.Token(
    ///         registrar,
    ///         registrar.subscribe(to: [.init(0)], didSet: { _ in })
    ///     )
    ///     // ... use the subscription ...
    /// }
    /// // token deinits at scope exit; observer is unsubscribed.
    /// ```
    public struct Token: ~Copyable, Sendable {
        @usableFromInline
        var _registrar: Observation.Registrar?

        @usableFromInline
        var _id: Observation.Subscription.ID?

        /// Creates a token armed to unsubscribe `id` from `registrar`
        /// on deinit.
        @inlinable
        public init(_ registrar: Observation.Registrar, _ id: Observation.Subscription.ID) {
            self._registrar = registrar
            self._id = id
        }

        deinit {
            if let registrar = _registrar, let id = _id {
                registrar.unsubscribe(id)
            }
        }
    }
}

// MARK: - Detachment

extension Observation.Subscription.Token {
    /// Releases the token's hold without unsubscribing.
    ///
    /// Returns the `(registrar, id)` pair so the caller can transfer
    /// ownership elsewhere — e.g., to a long-lived registry that
    /// will unsubscribe later.
    ///
    /// After `detach`, this token's `deinit` runs as a no-op.
    /// Calling `detach` a second time on the same token returns
    /// `nil` (the token is already disarmed).
    ///
    /// - Returns: The `(registrar, id)` if the token was armed;
    ///   `nil` if it has already been detached.
    @inlinable
    public mutating func detach() -> (Observation.Registrar, Observation.Subscription.ID)? {
        guard let registrar = _registrar, let id = _id else { return nil }
        _registrar = nil
        _id = nil
        return (registrar, id)
    }
}

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

internal import Kernel_Thread

extension Observation.Tracking {
    /// Per-thread slot holding the current ``Observation/Tracking/Frame``.
    ///
    /// Backed by `Kernel.Thread.Local<Frame>`, the L3 typed thread-local
    /// primitive that wraps the platform's TLS slot
    /// (POSIX `pthread_key_*` via ``ISO_9945/Kernel/Thread/Key`` /
    /// Windows `TlsAlloc` via ``Windows/Kernel/Thread/Index``). The
    /// kernel-layer wrapper encapsulates the `Unmanaged` retain/release
    /// dance, so this file's push/pop/currentFrame surface is
    /// `unsafe`-free.
    ///
    /// One slot is allocated process-wide (lazy init at first
    /// access), shared by all threads. Each thread has its own slot
    /// value — a Frame on Thread A never shows up on Thread B.
    static let _slot: Kernel.Thread.Local<Frame> = Kernel.Thread.Local()

    /// Returns the current frame on the calling thread, or `nil` if
    /// no `withObservationTracking` body is active.
    static func currentFrame() -> Frame? {
        _slot.value
    }

    /// Pushes `frame` as the current frame, setting `frame.parent` to
    /// the previous current frame (which may be `nil`). Call
    /// `popFrame(_:)` with the same frame to restore.
    static func pushFrame(_ frame: Frame) {
        _slot.value = frame
    }

    /// Pops `frame` from the current slot, restoring `frame.parent`.
    ///
    /// Precondition: `frame` is the current frame on this thread —
    /// nested `withObservationTracking` calls must pop in LIFO order.
    static func popFrame(_ frame: Frame) {
        guard let current = _slot.value else { return }
        precondition(
            current === frame,
            "Observation.Tracking frame popped out of order"
        )
        _slot.value = frame.parent
    }
}

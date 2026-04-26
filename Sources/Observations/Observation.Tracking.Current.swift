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
    /// Backed by `Kernel.Thread.Local` (POSIX `pthread_key_*` /
    /// Windows `TlsAlloc`). The slot stores a retained
    /// `Unmanaged<Frame>.toOpaque()` raw pointer; `nil` means no
    /// frame is active on this thread.
    ///
    /// One slot is allocated process-wide (lazy init at first
    /// access), shared by all threads. Each thread has its own slot
    /// value — a Frame on Thread A never shows up on Thread B.
    ///
    /// `Kernel.Thread.Local` is `@unchecked Sendable` because its
    /// semantics are per-thread by construction; the kernel TLS
    /// machinery provides the per-thread isolation. Sharing one slot
    /// across threads is the intended design.
    static let _slot: Kernel.Thread.Local = Kernel.Thread.Local()

    /// Returns the current frame on the calling thread, or `nil` if
    /// no `withObservationTracking` body is active.
    static func currentFrame() -> Frame? {
        guard let raw = unsafe _slot.value else { return nil }
        return unsafe Unmanaged<Frame>.fromOpaque(raw).takeUnretainedValue()
    }

    /// Pushes `frame` as the current frame, setting `frame.parent` to
    /// the previous current frame (which may be `nil`). Call
    /// `popFrame(_:)` with the same frame to restore.
    ///
    /// Allocates one retain on `frame` so the slot owns a strong
    /// reference for its lifetime; `popFrame` releases.
    static func pushFrame(_ frame: Frame) {
        let retained = unsafe Unmanaged.passRetained(frame).toOpaque()
        unsafe (_slot.value = retained)
    }

    /// Pops `frame` from the current slot, restoring `frame.parent`.
    /// Releases the retain installed by `pushFrame`.
    ///
    /// Precondition: `frame` is the current frame on this thread —
    /// nested `withObservationTracking` calls must pop in LIFO order.
    static func popFrame(_ frame: Frame) {
        guard let raw = unsafe _slot.value else { return }
        let current = unsafe Unmanaged<Frame>.fromOpaque(raw)
        unsafe precondition(
            current.takeUnretainedValue() === frame,
            "Observation.Tracking frame popped out of order"
        )

        if let parent = frame.parent {
            let parentRaw = unsafe Unmanaged.passRetained(parent).toOpaque()
            unsafe (_slot.value = parentRaw)
        } else {
            unsafe (_slot.value = nil)
        }
        unsafe current.release()
    }
}

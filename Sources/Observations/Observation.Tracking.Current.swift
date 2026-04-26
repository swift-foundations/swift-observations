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
// See LICENSE for license information
//
// ===----------------------------------------------------------------------===//

internal import Kernel_Thread

extension Observation.Tracking {
    /// Per-thread slot holding the current ``Observation/Tracking/Frame``.
    ///
    /// Backed by ``_FrameLocal``, a typed wrapper around
    /// `Kernel.Thread.Local` (POSIX `pthread_key_*` / Windows
    /// `TlsAlloc`). The wrapper localizes the `Unmanaged`
    /// retain/release dance inside its setter so the public push/pop
    /// surface stays free of `unsafe` markers.
    ///
    /// One slot is allocated process-wide (lazy init at first
    /// access), shared by all threads. Each thread has its own slot
    /// value — a Frame on Thread A never shows up on Thread B.
    static let _slot: _FrameLocal = _FrameLocal()

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

extension Observation.Tracking {
    /// Typed thread-local storage for a class-typed payload.
    ///
    /// Wraps `Kernel.Thread.Local` (an untyped raw-pointer slot) with
    /// generic typing and ARC-managed retain/release. The setter
    /// releases the previous value (if any) and retains the new one;
    /// the getter returns an unretained reference to the current
    /// value.
    ///
    /// ## Why this lives here, not in swift-kernel
    ///
    /// `Kernel.Thread.Local`'s public `value: UnsafeMutableRawPointer?`
    /// surface is necessarily unsafe — the platform layer doesn't
    /// know payload typing. A typed wrapper localizes the `Unmanaged`
    /// dance to one place, but the cleanest naming
    /// (`Kernel.Thread.Local<T>`) collides with the existing untyped
    /// `Kernel.Thread.Local` typealias at `swift-kernel`. Promoting
    /// this to an ecosystem primitive requires renaming the existing
    /// untyped slot (e.g., to `Kernel.Thread.Local.Raw`) — a
    /// cross-package change deferred until other consumers exist.
    /// For now, this private helper encapsulates the unsafe surface
    /// for `swift-observations`.
    @safe
    final class _FrameLocal: @unchecked Sendable {
        let _raw: Kernel.Thread.Local

        init() {
            _raw = Kernel.Thread.Local()
        }

        var value: Frame? {
            get {
                guard let opaque = unsafe _raw.value else { return nil }
                return unsafe Unmanaged<Frame>.fromOpaque(opaque).takeUnretainedValue()
            }
            set {
                if let oldOpaque = unsafe _raw.value {
                    unsafe Unmanaged<Frame>.fromOpaque(oldOpaque).release()
                }
                if let newValue {
                    let retained = unsafe Unmanaged.passRetained(newValue).toOpaque()
                    unsafe (_raw.value = retained)
                } else {
                    unsafe (_raw.value = nil)
                }
            }
        }
    }
}

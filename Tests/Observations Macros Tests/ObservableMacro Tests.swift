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

import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

@testable import Observations_Macros

// MARK: - Macro registry

private let testMacros: [String: MacroSpec] = [
    "Observable": MacroSpec(type: ObservableMacro.self),
    "_ObservationTracked": MacroSpec(type: ObservationTrackedMacro.self),
]

// MARK: - Swift Testing adapter

/// Bridges `SwiftSyntaxMacrosGenericTestSupport.assertMacroExpansion`'s
/// framework-agnostic `failureHandler` callback to Swift Testing's
/// `Issue.record(...)`. Avoids `SwiftSyntaxMacrosTestSupport`, which
/// pulls XCTest (and transitively Foundation).
private func expectMacroExpansion(
    _ originalSource: String,
    expandedSource: String,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
) {
    assertMacroExpansion(
        originalSource,
        expandedSource: expandedSource,
        macroSpecs: testMacros,
        failureHandler: { failure in
            Issue.record(
                Comment(rawValue: failure.message),
                sourceLocation: SourceLocation(
                    fileID: failure.location.fileID.description,
                    filePath: failure.location.filePath.description,
                    line: Int(failure.location.line),
                    column: Int(failure.location.column)
                )
            )
        },
        fileID: fileID,
        filePath: filePath,
        line: line,
        column: column
    )
}

// MARK: - Suite hierarchy

extension ObservableMacro {
    @Suite
    struct Test {
        @Suite struct Unit {}
        @Suite struct `Edge Case` {}
    }
}

// MARK: - Unit

extension ObservableMacro.Test.Unit {

    @Test
    func `simple struct with two stored vars expands to target shape`() {
        expectMacroExpansion(
            """
            @Observable
            struct Counter {
                var x: Int = 0
                var y: Int = 0
            }
            """,
            expandedSource: """
            struct Counter {
                var x: Int = 0 {
                    @storageRestrictions(initializes: _x)
                    init(initialValue) {
                        _x = initialValue
                    }
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

                var _x: Int
                var y: Int = 0 {
                    @storageRestrictions(initializes: _y)
                    init(initialValue) {
                        _y = initialValue
                    }
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

                var _y: Int

                let _$registrar: Observation.Registrar = Observation.Registrar()
            }

            extension Counter: Observable {
            }
            """
        )
    }

    @Test
    func `noncopyable struct expansion composes with ~Copyable Self`() {
        // Ground rule #2 research gate: confirms that `_$registrar` and
        // `_modify` synthesis admit `~Copyable Self`. Registrar's CoW
        // shape carries no Copyable constraint, so the conformance is
        // valid.
        expectMacroExpansion(
            """
            @Observable
            struct Foo: ~Copyable {
                var x: Int = 0
            }
            """,
            expandedSource: """
            struct Foo: ~Copyable {
                var x: Int = 0 {
                    @storageRestrictions(initializes: _x)
                    init(initialValue) {
                        _x = initialValue
                    }
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

                var _x: Int

                let _$registrar: Observation.Registrar = Observation.Registrar()
            }

            extension Foo: Observable {
            }
            """
        )
    }

    @Test
    func `class subject synthesizes accessors and conformance`() {
        expectMacroExpansion(
            """
            @Observable
            class Box {
                var value: Int = 0
            }
            """,
            expandedSource: """
            class Box {
                var value: Int = 0 {
                    @storageRestrictions(initializes: _value)
                    init(initialValue) {
                        _value = initialValue
                    }
                    _read {
                        Observation.Tracking.access(_$registrar, .init(0))
                        yield _value
                    }
                    _modify {
                        _$registrar.willSet(.init(0))
                        yield &_value
                        _$registrar.didSet(.init(0))
                    }
                }

                var _value: Int

                let _$registrar: Observation.Registrar = Observation.Registrar()
            }

            extension Box: Observable {
            }
            """
        )
    }

    @Test
    func `generic struct preserves the type parameter in the storage peer`() {
        expectMacroExpansion(
            """
            @Observable
            struct Box<T> {
                var value: T
            }
            """,
            expandedSource: """
            struct Box<T> {
                var value: T {
                    @storageRestrictions(initializes: _value)
                    init(initialValue) {
                        _value = initialValue
                    }
                    _read {
                        Observation.Tracking.access(_$registrar, .init(0))
                        yield _value
                    }
                    _modify {
                        _$registrar.willSet(.init(0))
                        yield &_value
                        _$registrar.didSet(.init(0))
                    }
                }

                var _value: T

                let _$registrar: Observation.Registrar = Observation.Registrar()
            }

            extension Box: Observable {
            }
            """
        )
    }
}

// MARK: - Edge Case

extension ObservableMacro.Test.`Edge Case` {

    @Test
    func `mixed let and var only tracks var`() {
        expectMacroExpansion(
            """
            @Observable
            struct Counter {
                let id: Int
                var x: Int = 0
            }
            """,
            expandedSource: """
            struct Counter {
                let id: Int
                var x: Int = 0 {
                    @storageRestrictions(initializes: _x)
                    init(initialValue) {
                        _x = initialValue
                    }
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

                var _x: Int

                let _$registrar: Observation.Registrar = Observation.Registrar()
            }

            extension Counter: Observable {
            }
            """
        )
    }

    @Test
    func `underscore-prefixed var is not tracked`() {
        expectMacroExpansion(
            """
            @Observable
            struct Counter {
                var _internal: Int = 0
                var x: Int = 0
            }
            """,
            expandedSource: """
            struct Counter {
                var _internal: Int = 0
                var x: Int = 0 {
                    @storageRestrictions(initializes: _x)
                    init(initialValue) {
                        _x = initialValue
                    }
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

                var _x: Int

                let _$registrar: Observation.Registrar = Observation.Registrar()
            }

            extension Counter: Observable {
            }
            """
        )
    }
}

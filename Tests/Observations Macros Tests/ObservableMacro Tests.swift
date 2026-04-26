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
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

@testable import Observations_Macros

private let testMacros: [String: any Macro.Type] = [
    "Observable": ObservableMacro.self,
    "_ObservationTracked": ObservationTrackedMacro.self,
]

final class ObservableMacroTests: XCTestCase {

    // MARK: - Simple struct (matches the hand-authored Counter shape)

    func test_simple_struct_expands_to_target_shape() {
        assertMacroExpansion(
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
            """,
            macros: testMacros
        )
    }

    // MARK: - ~Copyable struct (ground rule #2 research gate)

    func test_noncopyable_struct_expansion() {
        // Verifies that `_$registrar` + `_modify` accessor synthesis
        // composes with `~Copyable Self`. Registrar's CoW shape carries
        // no Copyable constraint, so the conformance is admissible.
        assertMacroExpansion(
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
            """,
            macros: testMacros
        )
    }

    // MARK: - Class

    func test_class_expansion() {
        assertMacroExpansion(
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
            """,
            macros: testMacros
        )
    }

    // MARK: - Generic struct

    func test_generic_struct_expansion() {
        assertMacroExpansion(
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
            """,
            macros: testMacros
        )
    }

    // MARK: - Mixed let / var (only var gets accessors)

    func test_mixed_let_var_only_var_tracked() {
        assertMacroExpansion(
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
            """,
            macros: testMacros
        )
    }

    // MARK: - Underscored properties skipped

    func test_underscored_var_not_tracked() {
        assertMacroExpansion(
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
            """,
            macros: testMacros
        )
    }
}

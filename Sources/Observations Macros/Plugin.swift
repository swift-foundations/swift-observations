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

import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct ObservationsPlugin: CompilerPlugin {
    let providingMacros: [any Macro.Type] = [
        ObservableMacro.self,
        ObservationTrackedMacro.self,
    ]
}

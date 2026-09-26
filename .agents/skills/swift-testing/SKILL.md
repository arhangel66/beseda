---
name: swift-testing
description: Write Swift Testing unit tests and migrate XCTest assertions while keeping XCUITest at its UI-automation boundary.
---

# Swift Testing

This retained candidate is from `dpearson2699/swift-ios-skills` at source
revision `8d90fd121a263355a4fb44fd082af1416a5c1c2a`. Its migration trial
compiled the unit-test bundle in 5.42 seconds. That trial's simulator execution
remains pending because destination resolution was unavailable at trial time;
FAB-13 separately proved the generated app's unit/UI test path on a private
matching runtime. See `docs/evidence/skills-search-trial-FAB-11-20260920.md`.

This retained skill targets the host's Xcode 26.6 toolchain. Its bundled
references exclude guidance for newer-toolchain-only interoperability defaults.

## Unit tests

```swift
import Testing

@Test("expense keeps its title")
func expenseKeepsItsTitle() {
    let expense = Expense(title: "Lunch", amount: 12.50, category: "Food")
    #expect(expense.title == "Lunch")
}
```

Use `#expect` for independent assertions and `try #require` when later code
needs an unwrapped value. Keep each test's state independent; Swift Testing
may run tests in parallel. Use `@Suite(.serialized)` only for genuinely shared
external state, not to encode test order.

## Migration boundary

Migrate unit-test files one at a time. Map `XCTAssert*` to `#expect`,
`XCTUnwrap` to `try #require`, and unconditional `XCTFail` to `Issue.record`.
Keep XCUITest for UI automation, performance tests, and tooling that requires
XCTest. Swift Testing and XCTest can coexist during migration.

Check the active Swift/Xcode version before using newer APIs such as
`Test.cancel()`, warning severity, attachments, or exit testing. Do not use
iOS-hostile exit testing for an iOS app target. A generic simulator-SDK
compile is not proof that a simulator test ran.

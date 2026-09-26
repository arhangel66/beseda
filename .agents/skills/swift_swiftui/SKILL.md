---
name: swift_swiftui
description: Choose the smallest correct SwiftUI state wrapper and keep data flow explicit in small views.
license: Proprietary
compatibility: SwiftUI 1.0+
metadata:
  version: "1.0"
  author: SwiftZilla
  sourceRevision: "682d49b5380830f4d95aeb6026b84dc5a974ff64"
---

# SwiftUI state

The `swiftzilla/skills` candidate was trialed against the immutable expense
app. Its `@Binding` variant compiled in 8.67 seconds but did not improve the
baseline's save-closure design. Evidence and the rewrite decision are in
`docs/evidence/skills-search-trial-FAB-11-20260920.md`.

## State decision

- Use `@State` for value-type state owned by one view, such as text fields,
  toggles, or a small local collection.
- Use `@Binding` when a child must mutate value-type state owned by its parent.
- Use `@ObservedObject` for a reference-type model supplied by another owner.
- Use `@StateObject` only when the view owns a reference-type model across view
  recreation.
- Use `@Environment` for system values or deliberately shared dependencies.

Lift state only when two views share it. For a small local form, a save closure
can be simpler than binding the entire collection. Do not add a view model,
Combine, or an environment object only to move a few lines.

Keep mutations on the appropriate actor for the data being changed. Do not
make the blanket claim that every property wrapper requires `@MainActor`; the
wrapper choice and the model's concurrency requirements are separate.

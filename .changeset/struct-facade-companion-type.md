---
"@effect/tsgo": patch
---

declarations: keep a companion type for faceted struct schemas instead of dropping it

The effect-schema struct facade transform dropped the `export type X = typeof X.Type`
companion of a `const X = S.Struct(...)` model, but only emitted the replacement
`interface X` when the decoded `Type` materialized as an object literal. Under newer
effect Schema types `.Type` can resolve to a mapped type (e.g.
`Struct.ReadonlySide<…, "Type">`), so the facade builder bailed, the const stayed
un-faceted, and the companion alias was dropped with no replacement — leaving `X`
value-only and breaking cross-module `import { type X }` usage (TS2749) under faceted
resolution.

Now the builder emits the decoded `Type` as a `type X = …` alias when it is not an
object literal (keeping the `interface X` form when it is), and the companion alias is
only dropped when the struct was actually faceted; otherwise the original alias is kept.

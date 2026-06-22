---
"@effect/tsgo": patch
---

declarations: facet bare-imported class schemas and emit static class namespace interfaces

Two facade-emit gaps under newer effect Schema types:

- Heritage detection only matched namespaced constructors (`S.Class(...)` /
  `Schema.Opaque(...)`); a bare named import (`import { Class } from "effect-app/Schema"`
  → `class X extends Class<X>(...)`) was not recognized, so the class base kept its
  fully-inlined `EnhancedClass<X, Struct<{…all fields…}>>` instead of the compact
  `OpaqueClassFacade<X, X.Encoded, …>`. Now both heritage shapes are recognized.

- The class static-property resolver (`CreateTypeOfClassStaticProperty`) serialized
  `Type`/`Encoded`/`Make`/`Fields` via the node builder, which under effect #2442 keeps
  the deferred mapped helper (`Struct.ReadonlySide<…>`) as a reference — regressing the
  generated namespace from static interfaces to mapped-type aliases. Now object-typed
  properties are expanded to static `interface`s (matching the struct-facade path);
  callable members (`never` services, the base `mapFields`/`copy`) keep their signatures.

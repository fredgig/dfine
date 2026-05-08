# Dfine

A testing ground for the **Dfine** framework — a small entity/component-style layer over Roblox `Instance`s with inheritance, default values, and shared/server/client method scoping.

This repo isn't the published framework; it's where the design and runtime are being shaken out, with `lune` standing in for the Roblox runtime.

## Layout

| File                  | Purpose                                                                                                                                            |
| --------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Dfine.luau`          | The framework runtime + generated type aliases.                                                                                                    |
| `generate_types.luau` | Codegen that scans `scripts/*.luau` for `D.fine{...}` calls and writes type aliases into `Dfine.luau` between `-- Begin Types` and `-- End Types`. |
| `scripts/Tests.luau`  | Demo + smoke tests. Defines a few entities and asserts behavior.                                                                                   |
| `.luaurc`             | Sets the `@dfine` and `@lune` aliases.                                                                                                             |

## Concepts

### `D.fine(spec)` — declare an entity

`D.fine` takes a spec table and returns a frozen-ish "entity definition" that can be passed to `D.new` (or used as a parent via `D.Extends`).

```lua
local Vehicle = D.fine {
    [D.Name] = "Vehicle",

    Honk = function(self): string
        return "Beep!"
    end,
}

local Car = D.fine {
    [D.Name] = "Car",
    [D.Container] = Instance.new("Model"),
    [D.Extends] = { Vehicle },

    Color = "red",
    TopSpeed = 120,
    Owner = D.Nil :: Player?,

    Drive = function(self, distance: number): string
        return `drove {distance}m at {self.TopSpeed}km/h`
    end,

    Server_Refuel = function(self): string
        return "tank full"
    end,

    Client_PlayHorn = function(self): string
        return self:Honk()  -- inherited from Vehicle
    end,
}
```

Spec keys fall into three buckets:

- **Sentinel keys** (`[D.Name]`, `[D.Container]`, `[D.Extends]`) — metadata, not properties.
- **Properties** — anything else with a non-function value (`Property1 = "Hello"`, etc.). Used as defaults.
- **Methods** — function values. Three flavors based on prefix:
  - `SomeMethod = function(self, ...) ... end` — shared (works on both client and server).
  - `Server_SomeMethod = ...` — server-only.
  - `Client_SomeMethod = ...` — client-only.

`D.fine` also walks `[D.Extends]` and pulls inherited fields (properties + methods) onto the spec at definition time, so a child entity can call any method defined on a parent.

### `D.new(spec)` — instantiate

```lua
local entity2 = D.new(TestEntity2)
```

Creates a fresh `Instance` (cloned from `[D.Container]`) and wraps it with a metatable that:

- Reads properties from the spec (defaults) unless overridden on the instance.
- Routes method calls to the spec's functions, passing the wrapper as `self`.
- Falls through to the underlying `Instance` for anything else (`entity2.Name`, `entity2:GetChildren()`, etc.).

When you assign a property:

- If the new value **equals the spec default**, the override is cleared (instance reverts to the default).
- Otherwise the override is stored on the wrapper.
- Names that aren't in the spec are forwarded to the underlying `Instance`.
- Trying to overwrite a method raises an error.

### Sentinels

Dfine uses string sentinels (so they can sit as keys in plain table literals without colliding with property names). They live on `D`:

| Sentinel      | Where it goes                           | Purpose                                                                                                                                                                                                       |
| ------------- | --------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `D.Name`      | `[D.Name] = "Entity2"`                  | Entity type name. Used by the codegen to name the generated type aliases (`Entity2`, `Entity2Properties`, etc.).                                                                                              |
| `D.Container` | `[D.Container] = Instance.new("Model")` | Prototype `Instance` cloned for each `D.new`. Defaults to a `Folder` if omitted. The class of this instance also becomes the type's container type (`Entity2 = ... & Model`).                                 |
| `D.Extends`   | `[D.Extends] = { TestEntity1 }`         | Parent entities. Properties and methods are inherited; multiple parents are allowed. Grandparents are flattened in.                                                                                           |
| `D.Nil`       | `Property5 = D.Nil :: Player?`          | Placeholder for "this property exists but defaults to `nil`". Plain `nil` in a table literal would just remove the key, so `D.Nil` is the workaround. The `:: Type` cast is what the type generator picks up. |

### Type generation

`Dfine.luau` ends with a block between `-- Begin Types` and `-- End Types` that's overwritten by the generator. For every `D.fine{...}` call the generator finds in `scripts/*.luau`, it emits:

- `<Name>Properties` — explicit type for the spec's properties (with literal values widened: `"Hello"` → `string`, `123` → `number`, etc.). Type assertions like `D.Nil :: Player?` are honored.
- `<Name>Methods`, `<Name>ClientMethods`, `<Name>ServerMethods` — split by prefix.
- `<Name>` / `<Name>Client` / `<Name>Server` — composed from the above plus the `Container` instance type.
- `<Name>Config` — the input shape `D.fine` accepts.
- A single `D` overload type that fans out across all defined entities so `D.fine` and `D.new` return the right per-entity types.

## Running

Both scripts run under [Lune](https://github.com/lune-org/lune).

```sh
# Regenerate types into Dfine.luau
lune run generate_types.luau

# Run the test/demo
lune run scripts/Tests.luau
```

The test file shadows `assert` at the top:

```lua
local assert: (boolean, string?) -> () = assert :: any
```

This is intentional. Luau treats the built-in `assert` as a type-narrowing intrinsic, so `assert(x == "Hello", msg)` would refine `x`'s type to the singleton `"Hello"` for the rest of the file — which then makes later mutations like `x ..= " World"` fail to type-check. Shadowing with a plain function signature strips the narrowing magic; the runtime is unchanged.

## Adding a new entity

1. Drop a file in `scripts/` containing one or more `D.fine{...}` calls. Give each entity a unique `[D.Name]`.
2. Run `lune run generate_types.luau` — types are emitted into `Dfine.luau`.
3. Use `D.new(...)` with full type info.

Type-only changes (renaming properties, adding a parent via `[D.Extends]`, etc.) require re-running the generator.

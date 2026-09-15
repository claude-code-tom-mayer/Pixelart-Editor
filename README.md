# Entity servers — C++ / GDScript mix

This branch is the same system as the GDScript branch (`claude/affectionate-shannon-mvac7l`),
with the **servers** rewritten as a C++ GDExtension. The data resources and the module
manager stay GDScript, so this is a **mix**, not a full C++ port.

Everything below was verified on Godot **4.7.1-stable**.

---

## 1. What is where, and why

| Class | Language | Reason |
|---|---|---|
| `ApiServer`, `ChunkingServer`, `HitServer`, `TargetingServer`, `A_EntityServer` | **C++** | All the per frame work lives here. |
| `C_ChunkingServer`, `C_HitServer`, `C_TargetingServer` | **C++** | Server constants. The servers need them at compile time; reading them out of a script every frame would undo the point. |
| `R_EntityData`, `R_HitProfile`, `R_HitData`, `R_TargetingData` | **GDScript** | Authored in the inspector, read once at registration. |
| `M_ModuleManager` | **GDScript** | Game logic that reacts to a hit. |

The seam is deliberate: **logic that runs every frame is C++, data you author is GDScript.**

---

## 2. Building it

### Prerequisites

- Python 3 and SCons (`pip install scons`)
- A C++17 compiler: GCC or Clang on Linux, MSVC (Build Tools) on Windows, Xcode on macOS

### Getting godot-cpp

`godot-cpp` is the C++ binding library. It has **no 4.6 or 4.7 branch** yet, so use `master`
and point it at the API your engine actually reports:

```bash
cd cpp
git clone https://github.com/godotengine/godot-cpp.git
"C:\Users\morit\Documents\Godot_v4.7.1-stable_win64.exe" --headless --dump-extension-api
# writes extension_api.json next to the executable; move it into cpp/
```

### Compiling

```bash
cd cpp
scons platform=windows target=template_debug   custom_api_file=extension_api.json generate_bindings=yes -j8
scons platform=windows target=template_release custom_api_file=extension_api.json generate_bindings=yes -j8
```

Use `platform=linux` or `platform=macos` as appropriate. **Build both targets**: the editor
loads the `template_debug` library, an exported game loads `template_release`. If only one
exists, the other simply fails to load and every server class disappears.

The result lands in `cpp/bin/`, which is what `cpp/bin/EntityServers.gdextension` points at.

### Loading it

Godot picks the extension up from the `.gdextension` file on project load. After a rebuild
you must **restart the editor** — `reloadable = false` is set because these servers hold
entity state that cannot survive a hot reload.

---

## 3. How the two halves talk to each other

### GDScript calling C++ (the cheap direction)

The C++ classes are ordinary global classes once the extension is loaded. Nothing special:

```gdscript
var l_api: ApiServer = ApiServer.new()

var l_entityData: R_EntityData = preload("uid://your_entity_data_uid")
var l_module: M_ModuleManager = M_ModuleManager.new()

var l_id: int = l_api.create_entity(Vector2(100.0, 200.0), C_ChunkingServer.TEAM_ATTACKER,
	l_module, l_entityData)

l_api.set_position(l_id, Vector2(110.0, 200.0))
var l_state: int = l_api.update_entity(l_id)

if (l_state == C_TargetingServer.STATE_SEARCH):
	l_api.search_target(l_id)
```

A call into a C++ GDExtension costs about **36 ns**, against about **138 ns** for a
GDScript to GDScript call, because bound native methods skip the GDScript VM's call
machinery. There is no binding tax to design around: calling C++ per entity is cheaper
than staying in GDScript.

### C++ calling GDScript (the expensive direction)

Two places do this, and both are deliberate.

**Reading a resource, once per registration.** C++ cannot name a GDScript class, so the
resources arrive as `Ref<Resource>` and are read by property name:

```cpp
_entityYBand[p_id] = p_hitProfile->get("yBand");
_entityHurtGroups[p_id] = p_hitProfile->get("hurtGroups");
```

That is a string keyed Variant lookup. It only happens at `create_entity()`, so the cost
does not matter. It does mean **the property names in the `R_*` scripts are load bearing**:
rename `yBand` in `R_HitProfile.gd` and the C++ side silently reads `null`.

**Dispatching a hit, once per landed hit.** The module manager is a GDScript object, so:

```cpp
l_module->call("hit", p_hitData);
```

This is the one per frame boundary crossing, and it costs a full script call (~375 ns class
of cost, since it enters the GDScript VM). At 500 hits per frame that is about 0.2 ms, which
is why the hit phase is still the most expensive one in the table below. If hits ever become
the bottleneck, that dispatch is the thing to batch or move into C++.

### Passing data back

C++ returns Godot types directly, so GDScript sees normal values:

```gdscript
var l_impacts: PackedVector3Array = l_api.hit_circle_ordered(l_id, l_position, 64.0,
	Vector2(0.0, 64.0), 1, C_HitServer.NO_PREFERRED_TARGET, l_hitData)
```

---

## 4. Differences from the GDScript API

The logic is identical; four things had to change shape.

| GDScript | C++ | Why |
|---|---|---|
| `C_ChunkingServer.MAP_SIZE` | `C_ChunkingServer.get_map_size()` | Only integer constants can be bound as constants; floats and Vector2 need a static method. |
| `C_ChunkingServer.CHUNK_SIZE` | `C_ChunkingServer.get_chunk_size()` | Same. |
| `C_TargetingServer.STATE.COMBAT` | `C_TargetingServer.STATE_COMBAT` | Bound enums are flat; the enum name becomes a prefix. |
| `HitServer.register()` / `TargetingServer.register()` | `register_entity()` | `register` is a reserved word in older C++ and reads ambiguously next to `ChunkingServer.register_entity()`. |

Everything else — method names, parameter order, return types, semantics — is the same.

The derived grid constants are now `constexpr`, computed at compile time instead of in
`_static_init()`. Change `CONFIGURED_MAP_SIZE_X` in `C_ChunkingServer.h` and rebuild.

---

## 5. RULES.md in C++

Followed: `snake_case` methods, `p_` parameters, `l_` locals, `UPPER_CASE` constants,
`_` prefixed privates, PascalCase class names with the `A_` / `C_` / `R_` / `M_` prefixes,
one file per class named after the class, folders mirroring the GDScript layout, a doc
comment on every class, method and member, at most two lines each.

Deviations, all forced by the language:

- **`///` instead of `##`.** C++ has no `##` doc comment.
- **No `[br]`.** That tag exists for Godot's documentation renderer, which never sees these
  comments. Adding it would be noise.
- **`// ===== REGION =====` instead of `#region`.** `#pragma region` is not portable to GCC.
- **`extends` before `class_name`** becomes `class X : public Base` plus the `GDCLASS` macro,
  which is the same ordering.
- **`@abstract`** becomes pure virtual methods plus `GDREGISTER_ABSTRACT_CLASS`.

---

## 6. Measured: full GDScript against this mix

Both branches, same benchmark, same seed, same world, back to back in one session on an
Intel Xeon @2.8GHz, Godot 4.7.1 headless. N entities and N single target hits per frame,
150 searches per frame, simulation only with no rendering.

| entities | full GDScript | C++ servers + GDScript data | speedup | sim-only FPS |
|---:|---:|---:|---:|---:|
| 300 | 8.12 ms | **0.36 ms** | **22.6x** | 123 -> 2778 |
| 500 | 11.00 ms | **0.58 ms** | **19.0x** | 91 -> 1724 |
| 750 | 14.98 ms | **0.83 ms** | **18.0x** | 67 -> 1205 |
| 1000 | 21.63 ms | **1.16 ms** | **18.6x** | 46 -> 862 |
| 3000 | 94.84 ms | **4.10 ms** | **23.1x** | 11 -> 244 |
| 5000 | 201.32 ms | **7.94 ms** | **25.4x** | 5 -> 126 |
| 10000 | 728.87 ms | **24.36 ms** | **29.9x** | 1 -> 41 |

Both branches land **exactly the same hits on exactly the same entities** at every count
(14, 25, 47, 93, 584, 1200, 3085), which is the equivalence check: this is a pure cost
change, not a behaviour change.

### Where the mix wins, and where the boundary holds it back

Per phase at 1000 entities. This is the useful table, because it shows that the speedup is
not uniform — it depends on how much of each phase is really C++.

| phase | full GDScript | this branch | speedup | what crosses the boundary |
|---|---:|---:|---:|---|
| `set_position` | 2.66 ms | 0.53 ms | **5x** | 1000 calls in, and the caller's own movement maths stays GDScript |
| `update_entity` | 1.80 ms | 0.06 ms | **30x** | 1000 calls in |
| `get_target_position` | 1.31 ms | 0.04 ms | **33x** | 1000 calls in |
| `search_target` | 9.52 ms | 0.15 ms | **63x** | 150 calls in, everything else is C++ |
| `hit_circle_ordered` | 6.33 ms | 0.39 ms | **16x** | 1000 calls in, and 93 calls back out to `M_ModuleManager.hit()` |

Read it this way:

- **Search gets 63x** because a search is one call in and then thousands of operations that
  never leave C++. This is the phase the port was for.
- **Hits only get 16x** because every landed hit calls back into GDScript. That return trip
  is the expensive direction, and it caps what the port can do here.
- **Movement only gets 5x** because the benchmark computes the new position in GDScript and
  the server only stores it. In a real game that maths is yours, so the shape holds: the more
  work you leave on the GDScript side of a call, the less the C++ side matters.

The lesson is the general one for a mix: **move whole loops across, not single operations.**
A server method that does a lot per call pays for itself many times over; one that does
almost nothing per call is dominated by the call itself.

## 7. Things that will bite you

- **Two builds.** Editor uses `template_debug`, export uses `template_release`. Forgetting
  one makes the classes vanish with only a "dynamic library not found" line in the log.
- **Restart after rebuilding.** The extension is not reloadable.
- **Property names are an interface.** Renaming an `@export` in an `R_*` script breaks the
  C++ reader silently, because `get()` on a missing property returns `null`, not an error.
- **`godot-cpp` must match your engine.** Use the dumped `extension_api.json` from the exact
  binary you run; a mismatch usually shows up as a crash on load rather than a clean error.
- **Exporting to Android or iOS** needs the extension compiled for those platforms too, with
  the matching entries in the `.gdextension`. The desktop build alone will not ship.

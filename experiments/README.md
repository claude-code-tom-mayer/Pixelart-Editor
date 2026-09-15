# Experiments

Measurement code only. **Nothing here is wired into `scripts/`** — the shipped
servers are untouched. Each folder holds a self-contained experiment, kept so it
can be picked up later without redoing the work.

Every number below was measured on the container that ran the experiment:
Intel Xeon @2.8GHz, 4 cores, Godot 4.7.1-stable headless, single threaded.
Run-to-run variance was under 2%.

---

## team-buckets

**Question:** is one centre bucket per chunk *and team* faster than one shared
bucket per chunk, so a searcher never walks its own team at all?

`ExpChunkingServer` / `ExpTargetingServer` are copies of the shipped servers with
`_centerHead` sized `TEAM_COUNT * CHUNK_COUNT`, the centre chains split by team,
and the per-candidate team test removed because it becomes structurally
impossible. `TeamBucketCompare.gd` runs both against the same world.

| entities | shared bucket | per team bucket | speedup | same targets |
|---------:|--------------:|----------------:|--------:|--------------|
| 500      | 35.62 us      | 35.21 us        | 1.01x   | yes |
| 1000     | 59.80 us      | 55.74 us        | 1.07x   | yes |
| 3000     | 161.03 us     | 121.27 us       | 1.33x   | yes |
| 5000     | 270.15 us     | 194.45 us       | 1.39x   | yes |

Per-search cost, reach 4, two fronts facing each other.

**Conclusion: not worth it below about 1000 entities.** The win comes from not
walking own-team entities, and that only matters once chunks are dense enough to
hold many of them. At 500 it is inside the noise; at 5000 it is a third off.
Targets picked are identical at every count, so it is a pure cost change.

---

## language-comparison

**Question:** how much would moving the search into another language buy?

`SPEC.md` defines one kernel — the ring search with its early exit, the
map/column/chunk group filter, the centre chains and the full scoring — precisely
enough to port. Every implementation builds the *same* world from the same
xorshift seed and returns a checksum, so agreement is verifiable rather than
assumed.

**All ports return checksum 57188 / 235364 / 2047625 / 5779530 at 500 / 1000 /
3000 / 5000 entities.** They compute the same thing.

### Standalone, outside Godot (raw language speed, us per search)

| entities | GDScript | C++ | Rust | C# |
|---------:|---------:|----:|-----:|---:|
| 500      | 17.474   | 0.167 | 0.174 | 0.369 |
| 1000     | 21.973   | 0.357 | 0.371 | 0.514 |
| 3000     | 43.223   | 0.751 | 0.852 | 1.035 |
| 5000     | 55.180   | 1.149 | 1.272 | 1.520 |

### Inside Godot (what you would actually ship)

| entities | GDScript | C++ GDExtension | speedup | C# | speedup |
|---------:|---------:|----------------:|--------:|---:|--------:|
| 500      | 18.7 us  | 0.173 us | 108x | 0.524 us | 36x |
| 1000     | 23.2 us  | 0.371 us |  63x | 0.601 us | 37x |
| 3000     | 38.5 us  | 0.755 us |  51x | 1.070 us | 36x |
| 5000     | 53.5 us  | 1.145 us |  47x | 1.603 us | 35x |

### Boundary cost — one trivial call from GDScript

| direction | ns per call |
|-----------|------------:|
| GDScript -> GDScript    | 132 |
| GDScript -> C++ GDExtension | **36** |
| GDScript -> C#          | **375** |

Measured over 2,000,000 calls, loop overhead included in all three, so they are
comparable to each other.

**This is the result that decides the design.** Calling into a C++ GDExtension is
*cheaper than calling GDScript from GDScript* — native bound methods skip the
GDScript VM's call machinery. Calling into C# is roughly three times more
expensive than staying in GDScript, so a C# port only pays off if whole loops
move across at once; per-entity calls into C# would lose.

### Rust

The standalone Rust port matches C++ to within about 5%. Building it as a
*GDExtension* was not possible here: godot-rust (gdext) 0.4.5 fails to generate
bindings for the Godot 4.7.1 API. `src/gdext_lib.rs` is the wrapper that would be
used once gdext supports 4.7.

## Reproducing

- GDScript: put `src/KernelGD.gd` in a project, run `src/BenchCpp2.gd` headless.
- C++: build `godot-cpp` against the engine's own `--dump-extension-api` output,
  then compile `src/kernel_core.h` + `src/search_kernel.*` + `src/register_types.cpp`
  into a shared library.
- C#: a Godot .NET project with `src/KernelCore.cs` + `src/KernelCS.cs`. Note the
  editor loads the **Debug** assembly, so set `<Optimize>true</Optimize>` or the
  measurement is of unoptimised IL.
- Rust standalone: `rustc -O src/kernel.rs`.

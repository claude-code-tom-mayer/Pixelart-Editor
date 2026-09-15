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

### Inside Godot (what you would actually ship, us per search)

All three native ports and GDScript return the same checksum in the same process.

| entities | GDScript | C++ GDExt | vs GD | Rust GDExt | vs GD | C# | vs GD |
|---------:|---------:|----------:|------:|-----------:|------:|---:|------:|
| 500      | 18.86 | 0.174 | **108x** | 0.204 | 93x | 0.524 | 36x |
| 1000     | 23.02 | 0.358 | **64x**  | 0.385 | 60x | 0.601 | 37x |
| 3000     | 38.40 | 0.769 | **50x**  | 0.866 | 44x | 1.070 | 36x |
| 5000     | 53.87 | 1.133 | **48x**  | 1.325 | 41x | 1.603 | 35x |

C# was measured in the same kernel in a separate process (the .NET build of the
engine), so its column is comparable in magnitude but not same-run.

### Boundary cost - one trivial call from GDScript

| direction | ns per call |
|-----------|------------:|
| GDScript -> GDScript         | 138 |
| GDScript -> C++ GDExtension  | **36** |
| GDScript -> Rust GDExtension | **45** |
| GDScript -> C#               | **375** |

Measured over 2,000,000 calls, loop overhead included in all of them, so they are
comparable to each other.

**This is the result that decides the design.** Calling into a C++ or Rust
GDExtension is *cheaper than calling GDScript from GDScript* - native bound
methods skip the GDScript VM's call machinery. There is no binding tax to design
around; per-entity calls into native code are fine. Calling into C# is about
three times more expensive than staying in GDScript, so a C# port only pays off
when whole loops cross the boundary at once.

### Toolchain notes

- **godot-rust**: the released gdext 0.4.5 cannot generate bindings for Godot
  4.7.1 (`Parameter 'mode_flags' ... can only replace int with enum`). Git master
  (0.5.5) works. `src/gdext_Cargo.toml` pins what was used, with the
  `api-custom-json` feature and `GODOT4_GDEXTENSION_JSON` pointing at the
  engine's own `--dump-extension-api` output.
- **godot-cpp** has no 4.6 or 4.7 branch; master built fine against the same
  dumped API.
- **C#**: the editor loads the **Debug** assembly, so set `<Optimize>true</Optimize>`
  or the measurement is of unoptimised IL. Godot also refuses to instantiate C#
  scripts if only a Release build exists - it hangs rather than reporting it.

## Reproducing

- GDScript: put `src/KernelGD.gd` in a project, run `src/BenchCpp2.gd` headless.
- C++: build `godot-cpp` against the engine's own `--dump-extension-api` output,
  then compile `src/kernel_core.h` + `src/search_kernel.*` + `src/register_types.cpp`
  into a shared library.
- C#: a Godot .NET project with `src/KernelCore.cs` + `src/KernelCS.cs`. Note the
  editor loads the **Debug** assembly, so set `<Optimize>true</Optimize>` or the
  measurement is of unoptimised IL.
- Rust standalone: `rustc -O src/kernel.rs`.
- Rust GDExtension: `src/gdext_lib.rs` + `src/gdext_Cargo.toml`, gdext git master.
- All three natives in one run: `src/BenchAll.gd`.

---

## How big is the gap really? (follow up)

The first numbers here compared C++ against a **naive** GDScript kernel, one that
called a helper per column and per chunk. That flattered C++. Two corrections
were measured afterwards.

### 1. Hand optimised GDScript closes part of it

`src/KernelGDOpt.gd` is the same kernel with the three has() helpers inlined, the
two-team case specialised, and every read only column hoisted into a local.
Identical checksums.

| entities | GD naive | GD optimised | C++ | naive/opt | opt vs C++ |
|---------:|---------:|-------------:|----:|----------:|-----------:|
| 500  | 19.31 us | 8.67 us  | 0.166 | 2.23x | **52x** |
| 1000 | 23.09 us | 12.66 us | 0.358 | 1.82x | **35x** |
| 3000 | 39.82 us | 29.40 us | 0.799 | 1.35x | **37x** |
| 5000 | 54.66 us | 42.97 us | 1.166 | 1.27x | **37x** |

### 2. The hit path is memory bound, and the gap is much smaller there

`src/hit_core.h` and `src/HitGD.gd` resolve one hit per entity per frame from a
fixed mix that holds at every entity count: 60% single target (maxHits 1,
ordered), 30% capped area (maxHits 5, ordered), 10% uncapped blast (unordered,
triple radius). Entities occupy every chunk their radius touches. Checksums match
at every count.

| entities | GDScript | C++ | speedup |
|---------:|---------:|----:|--------:|
| 500   | 1.43 ms   | 0.032 ms | 44.2x |
| 1000  | 4.20 ms   | 0.255 ms | 16.5x |
| 3000  | 30.06 ms  | 2.278 ms | 13.2x |
| 10000 | 326.64 ms | 27.17 ms | **12.0x** |

### 3. A whole frame, N searches plus N hits

| entities | GDScript (opt) | C++ | speedup |
|---------:|---------------:|----:|--------:|
| 500   | 6.47 ms    | 0.115 ms | **56x** |
| 1000  | 17.58 ms   | 0.627 ms | **28x** |
| 3000  | 112.06 ms  | 4.590 ms | **24x** |
| 10000 | 1127.02 ms | 47.57 ms | **24x** |

**So the honest number is 24x to 56x, not 100x.** Three things explain the
spread:

- GDScript is a **bytecode interpreter**, not a JIT. There is no native code
  generation, so the per operation overhead never goes away. C# in Godot *is*
  JIT compiled, which is why published GDScript-vs-C# figures are much smaller
  than GDScript-vs-C++ ones.
- The gap is largest where the work is small and the interpreter overhead
  dominates (500 entities), and shrinks as the working set grows and both
  languages become memory bound (10000 entities, hit path).
- This kernel spends **100% of its time in the language** and never calls the
  engine. Most game code does not: node access, physics and rendering run in the
  engine's own C++ whatever language called them, which is why typical
  comparisons show far less. These servers happen to be the unusual case where
  the language really is the bottleneck.

# GDScript Coding Rules

Reference for writing GDScript in this project. Follow all of this by default; do not ask before applying it.

## Naming & Typing

- Functions: `snake_case`, starting lowercase.
- Function parameters: prefixed `p_`, then camelCase (e.g. `p_dataStorage`).
- Local variables (declared inside a function): prefixed `l_`, then camelCase (e.g. `l_requiredBits`).
- Private variables and private functions: prefixed `_`, then camelCase for variables (e.g. `_activeSortKey`); functions stay `snake_case` after the `_` (e.g. `_apply_filter`).
- Constants and enum values: fully `UPPER_CASE`.
- Class names: PascalCase (e.g. `R_ProgressPathDataStorage`).
  - Custom Resources: prefix `R_`.
  - Abstract classes: prefix `A_`.
  - Abstract Resources: prefix `A_R_`.
  - Global / static (singleton-style) classes: prefix `G_`.
  - Modules (plug-and-work into entities): prefix `M_`.
  - Constants/enums scoped to one system: `C_[SystemName]`.
- Always use static typing. The only exception: `var rs = RenderingServer`.
- In every class, `extends` comes before `class_name`.
- When using `RenderingServer`, alias it once as `var rs = RenderingServer` and use `rs` from then on.
- When referencing paths, always use a `uid`.
- When referencing nodes within the same tree, always use unique names.
- Use `@export` for values meant to be tweaked easily (e.g. in the inspector); everything else stays a plain typed variable.

## Documentation

- Every class, function, and class-variable gets a short doc comment. Local (`l_`) variables do not need one.
- Description is at most 2 lines — state what it is/does, not how.
- Prefix every doc line with `##`. Append `[br]` to a line only if another doc line follows it (never on the last line of a block).
- Use `@param <name> ...` and `@return ...` tags after the description for functions that need them.
- Keep documentation minimal but immediately understandable — skip filler, skip restating the type name.

Example:

```gdscript
## Will detect a click and return the milestone to collect to the ProgressBar. [br]
## If the click is invalid or the milestone can´t be collected, invalidates the click. [br]
## @param p_position The position of the click to get the correct milestone [br]
## @param p_dataStorage The data to check, if a milestone can be collected [br]
## @return The milestone, which has to be collected or null
func handle_release(p_position: Vector2, p_dataStorage: R_ProgressPathDataStorage) -> R_MilestoneData:
	var l_milestone: R_MilestoneData = null

	if (pressedMilestone):
		if (milestoneRects.find_key(pressedMilestone).has_point(p_position)):
			if (on_milestone_clicked(pressedMilestone, p_dataStorage)):
				l_milestone = pressedMilestone

		invalidate_press()

	return l_milestone
```

## File & Code Organization

- Organize scripts in clear folder structures: a script lives where it is used.
- Use `#region REGION_NAME` / `#endregion` blocks to group related declarations (e.g. `PRIVATE_VARIABLES`, `LIFECYCLE`, `ABSTRACT_METHODS`, `PUBLIC_METHODS`, `PRIVATE_METHODS`).
- Use custom Resources (`R_...`) for data that should be reusable and exchangeable — not raw fields duplicated across scripts.
- Make code modular wherever reasonable.

## Clean Code / Minimalism

- Do not add a layer (a Resource wrapper, an extra base class, an extra enum file, a helper singleton, …) unless it adds real capability. More files is not more correct — a smaller design that does the same job is the better one.
- If two or more classes need the identical data or logic, move it up into one shared parent class instead of duplicating it — this applies to whole fields/arrays, not just methods.
- Do not build a multi-entry structure (array, dictionary) for state that can only ever hold one active value at a time — use a plain scalar field instead.
- A concept that only one class owns or cares about (e.g. a small enum) is declared inside that class, not split out into its own top-level file.
- Exit a loop as soon as the result is decided (`return`/`break`) instead of scanning the rest of the data once the answer is already known.
- No speculative flexibility: don't add parameters, branches, or config for a case nothing in the project currently needs.

## Abstract Classes

- Abstract classes/Resources are prefixed `A_` / `A_R_` and marked with `@abstract` directly above the `extends` line.
- An abstract method is declared with `@abstract` directly above it and has no body:
  ```gdscript
  @abstract
  func _get_enum() -> Dictionary
  ```
- When an abstract class extends another abstract class and does not itself implement an inherited abstract method, it must re-declare that method as `@abstract` in its own body too. Abstractness is not automatically inherited down the chain in GDScript — every class that leaves a method unimplemented must repeat the `@abstract` declaration for it, all the way down to the last class before a concrete implementation is provided.

## Explanatory Naming

- A name must say what the thing is or does. If a reader can't tell from the identifier alone, rename it — don't rely on a comment to compensate for a vague name.
- Avoid filler/ambiguous qualifiers (e.g. "typed", "data", "info", "helper") when a more specific word exists (e.g. `_get_valid_children()` over `_get_children_typed()`).
- Documentation should explain the *why*/role, not restate the signature — e.g. explicitly call out when a field or class is dual-purpose (used differently depending on which subclass/role holds it), since that's the part a name alone can't convey.

## PackedArrays & Bit/Value Comparisons

- For fixed, per-enum-key data, use a `Packed*Array` (`PackedByteArray`, `PackedStringArray`, `PackedFloat32Array`, …) with one slot per enum entry — not `Array`/`Dictionary`. Size and fill it once, from `<Enum>.keys()`/`<Enum>.values()`, typically in `_init()`.
- Build a `PackedStringArray` of enum key names (`PackedStringArray(<Enum>.keys())`) to identify which enum a container was built from, and use it to validate that two instances are compatible before comparing their values.
- `Packed*Array` equality (`==`/`!=`) is an element-wise value comparison in GDScript, not a reference/identity comparison — safe to use directly as a cheap compatibility check. Still check size (or rely on `!=` for size+content together) before indexing either array, to avoid an out-of-bounds read.
- To check that a set of properties satisfies a set of requirements, compare with a bitwise AND against the required bitmask (`current & required == required`) per entry, rather than a Dictionary/lookup-based rule engine.
- Prefer merging a "same identity" check (e.g. per-index key-name comparison) into the same loop that already walks the array for the value comparison, instead of a separate up-front pass, when both checks iterate the same indices anyway.

# GDScript / Godot Project Style Guide

## General

- Always use static typing. Only exceptions: `var rs = RenderingServer` and cached autoload references (see Caching).
- Write clean, modular code. Prefer composition (Modules, `M_` prefix) over deep inheritance where possible.
- Use custom Resources (`class_name` with `R_` prefix) for any reusable/exchangeable data.
- When referencing file paths, always use a uid (`uid://...`), never a raw `res://` path.
- When referencing nodes in the same scene tree, always use unique names (`%NodeName`), never relative NodePaths.
- When using `RenderingServer`, alias once: `var rs = RenderingServer`, then use `rs` for all following calls in that scope.
- Godot editor location: `C:\Users\morit\Documents\Godot_v4.7.1-stable_win64.exe`

## Folder Structure

- PascalCase folder names, e.g. `res://Entities/Player/`, `res://UI/ProgressBar/`.
- Scripts live in the folder of the system/scene they belong to, not in one global "scripts" dump.

## File Naming

| File type | Convention | Example |
|---|---|---|
| Script (`.gd`) | Matches `class_name` exactly, including its prefix | `R_MilestoneData` → `R_MilestoneData.gd` |
| Scene (`.tscn`) | PascalCase matching the root node's script class | `MainMenu.gd` → `MainMenu.tscn` |
| Custom Resource (`.tres`) | Matches the `R_` class name exactly | `R_MilestoneData` → `R_MilestoneData.tres` |
| Native/engine resource (Theme, StyleBox, AnimationLibrary, etc.) | PascalCase describing purpose, with `R_` prefix added when feasible | `R_MainMenuTheme.tres`, `R_ButtonHoverStyle.tres` |
| Shader (`.gdshader`) | PascalCase like a class name, with `S_` prefix | `S_WaterEffect.gdshader` |

If multiple instances of the same custom Resource class exist, append a descriptive suffix:
`R_MilestoneData_Fire.tres`, `R_MilestoneData_Ice.tres`.

## Class Prefixes (`class_name`)

| Kind | Prefix | Example |
|---|---|---|
| Regular class | none | `PascalCase` |
| Custom Resource | `R_` | `R_MilestoneData` |
| Abstract class | `A_` | `A_Weapon` |
| Abstract Resource | `A_R_` | `A_R_ItemData` |
| Utility class (never a Node, NOT an autoload; a helper used statically or per instance, static-only whenever possible) | `U_` | `U_MathUtils`, `U_TouchInput` |
| Module (plug-and-play component) | `M_` | `M_Health` |
| Constants container for one system | `C_[SystemName]` | `C_Inventory` |
| Shader "class" | `S_` | (see File Naming above) |
| Autoload / Singleton | `G_` — **only** for autoloads | Project Settings autoload name: `G_AudioManager`, file: `G_AudioManager.gd` |
| Inner/nested class (defined inside another class file) | none | `class Entry:` |

> **Note:** Do not also declare `class_name` on an autoload script — this conflicts with the autoload's global name. The `G_` prefix is used for the Autoload's name in Project Settings and the script's file name only.

Every class file order: `extends` line first, then `class_name` line, then the class's doc comment, then the body.

## Variables

Baseline casing for **all** variables (member, export, onready, local, parameter) is `camelCase` starting lowercase. Only a scope prefix goes in front of that camelCase name.

| Kind | Rule | Example |
|---|---|---|
| Member variable (public, not exported/private) | camelCase, no prefix | `currentHealth` |
| `@export` variable | camelCase, no prefix | `@export var maxSpeed: float` |
| `@onready` variable | follows normal public/private rules, no special prefix | `@onready var healthBar: ProgressBar` / `@onready var _internalTimer: Timer` (if private) |
| Private variable | `_` + camelCase | `_currentTarget` |
| Function parameter | `p_` + camelCase | `p_newValue`, `p_dataStorage` |
| Local variable (inside a function) | `l_` + camelCase | `l_currentIndex`, `l_milestone` |
| Local constant (inside a function) | `l_` + UPPER_CASE | `l_MAX_RETRIES` |
| Class-level constant | UPPER_CASE, no prefix | `MAX_HEALTH` |
| Static variable | no extra prefix, normal rules apply | `static var instance` (private: `static var _cache`) |

**Booleans (any scope):** `is`/`has`/`can` directly followed by the rest, no underscore after it, placed after any scope prefix:
`isActive`, `p_isValid`, `l_hasCollided`, `_isReady`, `canJump`

## Functions

- `snake_case`, starting with a lowercase letter: `func handle_release()`
- Private function: `_` + snake_case → `func _handle_input()`
- Static function: no extra prefix → `static func create_default()`
- Parameters always follow the `p_` + camelCase variable rule above.

## Enums & Constants

| Kind | Rule | Example |
|---|---|---|
| Enum type name | UPPER_CASE_WITH_UNDERSCORES | `enum MOVEMENT_STATE { IDLE, RUNNING }` |
| Enum values | UPPER_CASE | `IDLE`, `RUNNING` |
| Class-level const | UPPER_CASE | `const MAX_HEALTH = 100` |
| Local const | `l_` + UPPER_CASE | `const l_MAX_RETRIES = 3` |

All constants belonging to one system are grouped into a single `C_[SystemName]` class (file name matches exactly, e.g. `C_Inventory.gd`).

## Caching

Cache constants from `C_` classes and autoload references into member variables on init (`_init()`) to prevent repeated global name lookups.

- Cached constant: statically typed, keeps the constant's UPPER_CASE name, assigned once in `_init()` and never changed afterwards.
- Cached autoload reference: untyped (an autoload can't be used as a type, only its value), follows the normal variable rules, named after the autoload without `G_`.
- Enum constants are not cached.

```gdscript
## Cached C_TouchInput.CLICK_DEADZONE.
var CLICK_DEADZONE: float
## Cached G_AudioManager autoload.
var _audioManager

func _init() -> void:
	CLICK_DEADZONE = C_TouchInput.CLICK_DEADZONE
	_audioManager = G_AudioManager
```

## Signals

- `s_` prefix + camelCase: `signal s_healthChanged(p_newValue: int)`
- Signal parameters follow the same `p_` + camelCase rule as function parameters.
- Every signal gets a short doc comment (see Documentation).

## Nodes, Scenes, Groups, Input, Animation

- Node names in the scene tree: PascalCase, descriptive of role. `HealthBar`, `AttackTimer`
- Always reference same-tree nodes via unique names (`%NodeName`), never relative NodePaths.
- Node groups: never raw strings — store as an UPPER_CASE constant inside the relevant `C_[SystemName]` class and reference that constant. e.g. `add_to_group(C_Enemy.GROUP_ENEMIES)`
- Input Map action names: `snake_case` → `"move_left"`, `"ui_confirm_purchase"`
- AnimationPlayer track names: `camelCase` → `"idle"`, `"runLeft"`, `"attackCombo1"`

## Shaders

- File naming: see File Naming above (`S_` prefix, PascalCase).
- Uniform / varying variables: camelCase, no prefix. `uniform float waveSpeed;` `varying vec3 worldPos;`
- Documentation and section-comment rules apply the same as GDScript (see below), **except**: `#region`/`#endregion` is not supported by the Shader editor, so use a plain, unclosed comment line as a section marker instead:

```glsl
// UNIFORMS
uniform float waveSpeed;

// FUNCTIONS
void vertex() { ... }
```

## Documentation

- Every class, function, class-variable, `@export` variable, signal, and enum gets a doc comment directly above it, using `##` lines with `[br]` appended to every line that needs a break.
- Keep it as short as possible — 2 lines is a **hard maximum** for the plain description, not a target. Shorter is always better as long as it stays clearly descriptive.
- For functions, list parameters and return value below the description using `@param` and `@return`, one per line, each ending in `[br]` (these are additional to, not counted within, the 2-line cap):

```gdscript
## Detects a click and returns the milestone to collect. [br]
## @param p_position The click position. [br]
## @param p_dataStorage The data to validate the milestone against. [br]
## @return The milestone to collect, or null.
func handle_release(p_position: Vector2, p_dataStorage: R_ProgressPathDataStorage) -> R_MilestoneData:
```

## Regions (GDScript files)

Use this fixed, ordered set of `#region` blocks in every script; skip any that don't apply:

```gdscript
#region SIGNALS
#endregion

#region ENUMS_AND_CONSTANTS
#endregion

#region CACHED_VARS
#endregion

#region EXPORTS_AND_VARS
#endregion

#region LIFECYCLE_AND_METHODS
#endregion

#region MISC
#endregion
```

extends RefCounted
class_name C_TargetingServer
## Constants, states and scoring weights of the targeting system. [br]
## Ranges are counted in chunks here, only the combat range is a real distance.

#region ENUMS_AND_CONSTANTS

## What an entity is currently doing.
enum STATE { SEARCH, APPROACH, COMBAT, FLEE }

## Set while the entity cannot be seen by searchers without TARGETS_INVISIBLE.
const FLAG_INVISIBLE: int = 1 << 0

## Set while the entity can see invisible enemies.
const FLAG_TARGETS_INVISIBLE: int = 1 << 1

## Set while the entity is a focus target and scores the focus bonus.
const FLAG_HAS_FOCUS: int = 1 << 2

## Set while the entity scores every candidate without the focus bonus.
const FLAG_IGNORES_FOCUS: int = 1 << 3

## Stored as the target of an entity that has none.
const NO_TARGET: int = -1

## How close to its own base x an entity has to be before it stops fleeing.
const BASE_REACHED_EPSILON: float = 32.0

## What a diagonal chunk step costs against a straight one.
const DIAGONAL_CHUNK_COST: float = 1.45

# Derived once on class load, so they are static vars instead of consts.

## The x every team retreats towards; attackers hold the left side, defenders the right one.
static var TEAM_BASE_X: PackedFloat32Array

## The x every team marches towards while it has no target — the opposing base.
static var TEAM_MARCH_X: PackedFloat32Array

## The direction a team marches in along x; 1 towards a larger x, -1 towards a smaller one.
static var TEAM_FORWARD_SIGN: PackedInt32Array

# Scoring weights.

## Score per chunk the candidate is closer than the edge of the search area.
const WEIGHT_CLOSENESS: float = 1.0

## Score added when the candidate is a focus target.
const WEIGHT_FOCUS: float = 6.0

## Score added when the candidate stands behind the searcher.
const WEIGHT_BEHIND: float = 3.0

## Score lost per entity that already targets the candidate.
const WEIGHT_CROWDING: float = 1.5

## Score added when the candidate already targets the searcher.
const WEIGHT_MUTUAL: float = 4.0

#endregion

#region LIFECYCLE_AND_METHODS

## Pins the bases to the two x edges of the chunk grid, once on class load. [br]
## Reading C_ChunkingServer here also loads it first, so its own grid is already derived.
static func _static_init() -> void:
	var l_rightEdge: float = C_ChunkingServer.MAP_SIZE.x
	
	TEAM_BASE_X = PackedFloat32Array([0.0, l_rightEdge])
	TEAM_MARCH_X = PackedFloat32Array([l_rightEdge, 0.0])
	TEAM_FORWARD_SIGN = PackedInt32Array([1, -1])
	
	assert(TEAM_BASE_X.size() == C_ChunkingServer.TEAM_COUNT,
		"C_TargetingServer: every team needs a base x and a march x.")

#endregion

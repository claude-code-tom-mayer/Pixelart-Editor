extends RefCounted
class_name C_ChunkingServer
## Grid, map and team constants of the chunking system. [br]
## Recalculates the configured chunk counts once so that every chunk is square.

#region ENUMS_AND_CONSTANTS

## Teams an entity can fight for; the values index every per team container.
enum TEAM { ATTACKER, DEFENDER }

## World size the chunk grid has to cover, in world units.
const CONFIGURED_MAP_SIZE: Vector2 = Vector2(4096.0, 4096.0)

## Wanted chunks per row; only kept exactly if it already yields square chunks.
const CONFIGURED_CHUNK_COLUMNS: int = 32

## Wanted chunk rows; only kept exactly if it already yields square chunks.
const CONFIGURED_CHUNK_ROWS: int = 32

## Tolerance against float error when deriving the chunk counts from the map size.
const COVERAGE_EPSILON: float = 0.0001

## Stored as the outermost occupied column of a team that holds no entity at all.
const NO_COLUMN: int = -1

## Stored as a membership link that points nowhere, in every chunk and entity chain.
const NO_SLOT: int = -1

## Stored as a center link that points nowhere, in every center chain.
const NO_ENTITY: int = -1

# Derived once on class load, so they are static vars instead of consts.

## Edge length of one chunk; identical on both axes, so chunks are square.
static var CHUNK_SIZE: float

## Chunks per row after the square chunk recalculation.
static var MAP_CHUNK_COLUMNS: int

## Chunk rows after the square chunk recalculation.
static var MAP_CHUNK_ROWS: int

## Total number of chunks on the map.
static var CHUNK_COUNT: int

## Size the chunk grid really covers; never smaller than CONFIGURED_MAP_SIZE.
static var MAP_SIZE: Vector2

## Number of teams; size of every per team container.
static var TEAM_COUNT: int

#endregion

#region LIFECYCLE_AND_METHODS

## Derives the square chunk grid from the configuration once, on class load. [br]
## Uses the chunk edge closest to both configured counts and covers the map with it.
static func _static_init() -> void:
	var l_columnEdge: float = CONFIGURED_MAP_SIZE.x / float(CONFIGURED_CHUNK_COLUMNS)
	var l_rowEdge: float = CONFIGURED_MAP_SIZE.y / float(CONFIGURED_CHUNK_ROWS)
	
	CHUNK_SIZE = (l_columnEdge + l_rowEdge) * 0.5
	MAP_CHUNK_COLUMNS = maxi(1, ceili(CONFIGURED_MAP_SIZE.x / CHUNK_SIZE - COVERAGE_EPSILON))
	MAP_CHUNK_ROWS = maxi(1, ceili(CONFIGURED_MAP_SIZE.y / CHUNK_SIZE - COVERAGE_EPSILON))
	CHUNK_COUNT = MAP_CHUNK_COLUMNS * MAP_CHUNK_ROWS
	MAP_SIZE = Vector2(MAP_CHUNK_COLUMNS, MAP_CHUNK_ROWS) * CHUNK_SIZE
	TEAM_COUNT = TEAM.size()

#endregion

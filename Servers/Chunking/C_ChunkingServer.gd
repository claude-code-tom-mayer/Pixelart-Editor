extends RefCounted
class_name C_ChunkingServer
## Grid and map constants of the chunk index. [br]
## Recalculates the configured chunk counts once so that every chunk is square.

#region ENUMS_AND_CONSTANTS

## World size the chunk grid has to cover, in world units.
const CONFIGURED_MAP_SIZE: Vector2 = Vector2(4096.0, 4096.0)

## Wanted chunk columns; only kept exactly if it already yields square chunks.
const CONFIGURED_CHUNK_COLUMNS: int = 32

## Wanted chunk rows; only kept exactly if it already yields square chunks.
const CONFIGURED_CHUNK_ROWS: int = 32

## Tolerance against float error when deriving the chunk counts from the map size.
const COVERAGE_EPSILON: float = 0.0001

## Chunk area that covers no chunk at all, as (minColumn, minRow, maxColumn, maxRow). [br]
## Held by every entity that stands nowhere: freshly created and removed ones.
const EMPTY_CHUNK_AREA: Vector4i = Vector4i(0, 0, -1, -1)

## Edge length of one chunk; identical on both axes, so chunks are square.
static var CHUNK_SIZE: float

## Chunk columns after the square chunk recalculation.
static var CHUNK_COLUMNS: int

## Chunk rows after the square chunk recalculation.
static var CHUNK_ROWS: int

## Total number of chunks on the map.
static var CHUNK_COUNT: int

## Size the chunk grid really covers; never smaller than CONFIGURED_MAP_SIZE.
static var MAP_SIZE: Vector2

#endregion

#region LIFECYCLE_AND_METHODS

## Derives the square chunk grid from the configuration once, on class load. [br]
## Uses the chunk edge closest to both configured counts and covers the map with it.
static func _static_init() -> void:
	var l_columnEdge: float = CONFIGURED_MAP_SIZE.x / float(CONFIGURED_CHUNK_COLUMNS)
	var l_rowEdge: float = CONFIGURED_MAP_SIZE.y / float(CONFIGURED_CHUNK_ROWS)

	CHUNK_SIZE = (l_columnEdge + l_rowEdge) * 0.5
	CHUNK_COLUMNS = maxi(1, ceili(CONFIGURED_MAP_SIZE.x / CHUNK_SIZE - COVERAGE_EPSILON))
	CHUNK_ROWS = maxi(1, ceili(CONFIGURED_MAP_SIZE.y / CHUNK_SIZE - COVERAGE_EPSILON))
	CHUNK_COUNT = CHUNK_COLUMNS * CHUNK_ROWS
	MAP_SIZE = Vector2(CHUNK_COLUMNS, CHUNK_ROWS) * CHUNK_SIZE

#endregion

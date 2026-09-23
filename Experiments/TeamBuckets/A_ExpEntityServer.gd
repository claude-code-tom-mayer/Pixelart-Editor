@abstract
extends RefCounted
class_name A_ExpEntityServer
## Base of every server that keeps one slot per entity id beside the chunk index. [br]
## Owns the slot protocol and the cached grid values, so no server repeats either.

#region CACHED_VARS

## Cached C_ChunkingServer.MAP_CHUNK_COLUMNS; the search loops read it constantly.
var MAP_CHUNK_COLUMNS: int

## Cached C_ChunkingServer.MAP_CHUNK_ROWS.
var MAP_CHUNK_ROWS: int

## Cached C_ChunkingServer.CHUNK_COUNT.
var CHUNK_COUNT: int

## Cached C_ChunkingServer.CHUNK_SIZE.
var CHUNK_SIZE: float

## Cached C_ChunkingServer.TEAM_COUNT.
var TEAM_COUNT: int

#endregion

#region EXPORTS_AND_VARS

## Chunk index and shared entity columns this server reads; never points back at the api server.
var _chunking: ExpChunkingServer = null

#endregion

#region LIFECYCLE_AND_METHODS

## Binds the server to the chunk index and caches the grid values its loops read. [br]
## @param p_chunking The index and shared entity columns every server reads
func _init(p_chunking: ExpChunkingServer) -> void:
	_chunking = p_chunking
	MAP_CHUNK_COLUMNS = C_ChunkingServer.MAP_CHUNK_COLUMNS
	MAP_CHUNK_ROWS = C_ChunkingServer.MAP_CHUNK_ROWS
	CHUNK_COUNT = C_ChunkingServer.CHUNK_COUNT
	CHUNK_SIZE = C_ChunkingServer.CHUNK_SIZE
	TEAM_COUNT = C_ChunkingServer.TEAM_COUNT


## Makes sure the slot of an id exists and holds nothing of a previous entity. [br]
## Ids only ever grow by one, so one append covers every id that is not a reused one. [br]
## @param p_id The entity slot to prepare
func ensure_slot(p_id: int) -> void:
	if (p_id == _get_slot_count()):
		_append_slot()
		return

	_reset_slot(p_id)


## Lets the server drop what it holds for an id that is handed back for reuse. [br]
## @param p_id The entity whose slot is released
@warning_ignore("unused_parameter")
func release_entity(p_id: int) -> void:
	pass


## Lets the server react to an entity that was announced for removal. [br]
## @param p_id The entity that was announced
@warning_ignore("unused_parameter")
func on_pre_unregister(p_id: int) -> void:
	pass


## Lets the server react to an entity that was removed from the index. [br]
## @param p_id The entity that was removed
@warning_ignore("unused_parameter")
func on_unregister(p_id: int) -> void:
	pass


## Appends one fresh slot to every column of the server. [br]
## Every server has to override this.
@abstract
func _append_slot() -> void


## Resets one slot so a reused id inherits nothing of its predecessor. [br]
## Every server has to override this. [br]
## @param p_id The entity slot to reset
@abstract
func _reset_slot(p_id: int) -> void


## Reads how many slots the server currently holds. [br]
## Every server has to override this. [br]
## @return The number of slots
@abstract
func _get_slot_count() -> int

#endregion

@abstract
extends RefCounted
## Base of every server that keeps one slot per entity id beside the chunk index. [br]
## Owns the slot protocol and the cached grid values, so no server repeats either.
class_name A_EntityServer

#region PROTECTED_VARIABLES

## Chunk index and shared entity columns this server reads; never points back at the api server.
var _chunking: ChunkingServer = null

## Chunks per row, cached from C_ChunkingServer because the search loops read it constantly.
var _chunkColumns: int = 0

## Chunk rows, cached from C_ChunkingServer.
var _chunkRows: int = 0

## Total number of chunks on the map, cached from C_ChunkingServer.
var _chunkCount: int = 0

## Edge length of one chunk, cached from C_ChunkingServer.
var _chunkSize: float = 0.0

## Number of teams, cached from C_ChunkingServer.
var _teamCount: int = 0

#endregion

#region LIFECYCLE

## Binds the server to the chunk index and caches the grid values its loops read. [br]
## @param p_chunking The index and shared entity columns every server reads
func _init(p_chunking: ChunkingServer) -> void:
	_chunking = p_chunking
	_chunkColumns = C_ChunkingServer.MAP_CHUNK_COLUMNS
	_chunkRows = C_ChunkingServer.MAP_CHUNK_ROWS
	_chunkCount = C_ChunkingServer.CHUNK_COUNT
	_chunkSize = C_ChunkingServer.CHUNK_SIZE
	_teamCount = C_ChunkingServer.TEAM_COUNT

#endregion

#region PUBLIC_LIFECYCLE

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

#endregion

#region PROTECTED_METHODS

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

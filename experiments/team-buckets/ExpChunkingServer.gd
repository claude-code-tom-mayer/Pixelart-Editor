extends RefCounted
## Sorts entities into square chunks, columns and one map aggregate for fast group queries. [br]
## Counts are always written through, group masks only cascade upwards when they really change.
class_name ExpChunkingServer

#region SHARED_VARIABLES

# Private to the chunking system, but read directly by the servers built on top of it.
# Reading them from a sibling server is intended; writing them from anywhere else corrupts the index.

## Team per entity id, as a C_ChunkingServer.TEAM value.
var _entityTeam: PackedByteArray = PackedByteArray()

## Bitmask of the groups an entity belongs to.
var _entityGroups: PackedInt64Array = PackedInt64Array()

## Current position per entity id.
var _entityPosition: PackedVector2Array = PackedVector2Array()

## Effect radius per entity id; decides in how many chunks the entity stands.
var _entityRadius: PackedFloat32Array = PackedFloat32Array()

## 1 while an entity is announced for removal but still fully active.
var _entityPreUnregistered: PackedByteArray = PackedByteArray()

## 1 while an entity is removed but its id stays locked until it is released.
var _entityUnregistering: PackedByteArray = PackedByteArray()

## Chunk the center of an entity sits in; the whole entity is listed there exactly once.
var _entityCenterChunk: PackedInt32Array = PackedInt32Array()

## Column of the center chunk of an entity; flat mirror for the targeting hot loop.
var _entityCenterColumn: PackedInt32Array = PackedInt32Array()

## Row of the center chunk of an entity; flat mirror for the targeting hot loop.
var _entityCenterRow: PackedInt32Array = PackedInt32Array()

## First membership slot of every chunk, or C_ChunkingServer.NO_SLOT while it is empty. [br]
## Walk a chunk with: slot = _chunkHead[c]; while slot != NO_SLOT: ... slot = _slotChunkNext[slot]
var _chunkHead: PackedInt32Array = PackedInt32Array()

## Entity every membership slot belongs to; the id a chunk walk reads out.
var _slotEntity: PackedInt32Array = PackedInt32Array()

## Next membership slot inside the chain of the same chunk.
var _slotChunkNext: PackedInt32Array = PackedInt32Array()

## First entity whose center sits in a chunk, or C_ChunkingServer.NO_ENTITY while none does. [br]
## Walk it with: id = _centerHead[c]; while id != NO_ENTITY: ... id = _centerNext[id]
var _centerHead: PackedInt32Array = PackedInt32Array()

## Next entity inside the center chain of its chunk.
var _centerNext: PackedInt32Array = PackedInt32Array()

## Entity count per team and chunk, addressed by _get_team_chunk_index().
var _chunkCounts: PackedInt32Array = PackedInt32Array()

## Entity count per team and column, addressed by _get_team_column_index().
var _columnCounts: PackedInt32Array = PackedInt32Array()

## Ids removed since the last release; moved into the free list by release_removed_ids().
var _pendingFreeIds: PackedInt32Array = PackedInt32Array()

#endregion

#region PRIVATE_VARIABLES

## Chunk rectangle an entity covers as (minColumn, minRow, maxColumn, maxRow). [br]
## Lets set_position() and set_radius() drop out before touching any chunk.
var _entityChunkArea: Array[Vector4i] = []

## Entity ids that may be reused; only filled by release_removed_ids().
var _freeIds: PackedInt32Array = PackedInt32Array()

## First membership slot of every entity, or C_ChunkingServer.NO_SLOT while it stands nowhere. [br]
## Walking this chain lists every chunk one entity currently stands in.
var _entitySlotHead: PackedInt32Array = PackedInt32Array()

## Chunk every membership slot belongs to.
var _slotChunk: PackedInt32Array = PackedInt32Array()

## Previous membership slot inside the chain of the same chunk; makes unlinking O(1).
var _slotChunkPrev: PackedInt32Array = PackedInt32Array()

## Next membership slot inside the chain of the same entity.
var _slotEntityNext: PackedInt32Array = PackedInt32Array()

## Previous membership slot inside the chain of the same entity; makes unlinking O(1).
var _slotEntityPrev: PackedInt32Array = PackedInt32Array()

## Membership slots that may be handed out again.
var _freeSlots: PackedInt32Array = PackedInt32Array()

## Previous entity inside the center chain of its chunk; makes unlinking O(1).
var _centerPrev: PackedInt32Array = PackedInt32Array()

## Group bitmask per team and chunk, addressed by _get_team_chunk_index().
var _chunkGroups: PackedInt64Array = PackedInt64Array()

## Group bitmask per team and column — the OR of the chunk masks of that column. [br]
## Columns are the aggregation level because the two bases face each other along x.
var _columnGroups: PackedInt64Array = PackedInt64Array()

## Group bitmask per team over the whole map — the OR of all column masks.
var _mapGroups: PackedInt64Array = PackedInt64Array()

## Entity count per team over the whole map.
var _mapCounts: PackedInt32Array = PackedInt32Array()

## Lowest column a team occupies, or C_ChunkingServer.NO_COLUMN while it holds nothing. [br]
## Answers "is anything of that team further left" without walking the columns.
var _teamMinColumn: PackedInt32Array = PackedInt32Array()

## Highest column a team occupies, or C_ChunkingServer.NO_COLUMN while it holds nothing.
var _teamMaxColumn: PackedInt32Array = PackedInt32Array()

## Chunks per row, cached from C_ChunkingServer because every loop here reads it.
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

## Allocates the chunk, column and map containers for the configured grid.
func _init() -> void:
	_chunkColumns = C_ChunkingServer.MAP_CHUNK_COLUMNS
	_chunkRows = C_ChunkingServer.MAP_CHUNK_ROWS
	_chunkCount = C_ChunkingServer.CHUNK_COUNT
	_chunkSize = C_ChunkingServer.CHUNK_SIZE
	_teamCount = C_ChunkingServer.TEAM_COUNT
	
	var l_chunkSlots: int = _teamCount * _chunkCount
	var l_columnSlots: int = _teamCount * _chunkColumns
	
	_chunkGroups.resize(l_chunkSlots)
	_chunkCounts.resize(l_chunkSlots)
	_columnGroups.resize(l_columnSlots)
	_columnCounts.resize(l_columnSlots)
	_mapGroups.resize(_teamCount)
	_mapCounts.resize(_teamCount)
	
	_teamMinColumn.resize(_teamCount)
	_teamMaxColumn.resize(_teamCount)
	_teamMinColumn.fill(C_ChunkingServer.NO_COLUMN)
	_teamMaxColumn.fill(C_ChunkingServer.NO_COLUMN)
	
	_chunkHead.resize(_chunkCount)
	_centerHead.resize(_teamCount * _chunkCount)
	_chunkHead.fill(C_ChunkingServer.NO_SLOT)
	_centerHead.fill(C_ChunkingServer.NO_ENTITY)

#endregion

#region PUBLIC_METHODS

## Registers a new entity and adds it to every chunk its radius covers. [br]
## @param p_position Start position of the entity [br]
## @param p_radius Effect radius of the entity [br]
## @param p_team Team of the entity, a C_ChunkingServer.TEAM value [br]
## @param p_groups Bitmask of the groups the entity belongs to [br]
## @return The assigned entity id
func register_entity(p_position: Vector2, p_radius: float, p_team: int, p_groups: int) -> int:
	assert(p_team >= 0 and p_team < _teamCount, "ExpChunkingServer: register_entity() got an unknown team.")
	
	var l_id: int = _acquire_id()
	
	_entityTeam[l_id] = p_team
	_entityGroups[l_id] = p_groups
	_entityPosition[l_id] = p_position
	_entityRadius[l_id] = p_radius
	
	var l_area: Vector4i = _compute_chunk_area(p_position, p_radius)
	_entityChunkArea[l_id] = l_area
	
	for l_row: int in range(l_area.y, l_area.w + 1):
		var l_rowOffset: int = l_row * _chunkColumns
		
		for l_column: int in range(l_area.x, l_area.z + 1):
			_add_entity_to_chunk(l_id, l_rowOffset + l_column)
	
	_entityCenterChunk[l_id] = C_ChunkingServer.NO_COLUMN
	_apply_center_chunk(l_id, p_position)
	
	return l_id


## Marks an entity for removal; it stays fully active and queryable. [br]
## @param p_id The entity id to mark
func pre_unregister_entity(p_id: int) -> void:
	_entityPreUnregistered[p_id] = 1


## Removes an entity from all its chunks and locks its id until it is released. [br]
## Does nothing for an id that is already removed, so a double removal cannot free it twice. [br]
## @param p_id The entity id to remove
func unregister_entity(p_id: int) -> void:
	if (_entityUnregistering[p_id] == 1):
		return
	
	_entityUnregistering[p_id] = 1
	
	var l_slot: int = _entitySlotHead[p_id]
	while (l_slot != C_ChunkingServer.NO_SLOT):
		var l_nextSlot: int = _slotEntityNext[l_slot]
		_remove_slot_from_chunk(l_slot)
		l_slot = l_nextSlot
	
	_remove_center_from_chunk(p_id)
	_pendingFreeIds.append(p_id)


## Moves an entity and updates only the chunks it entered or left. [br]
## @param p_id The entity id to move [br]
## @param p_position The new position
func set_position(p_id: int, p_position: Vector2) -> void:
	_entityPosition[p_id] = p_position
	_apply_chunk_area(p_id, _compute_chunk_area(p_position, _entityRadius[p_id]))
	_apply_center_chunk(p_id, p_position)


## Resizes an entity and updates only the chunks it entered or left. [br]
## The center cannot move with the radius, so the center list stays untouched. [br]
## @param p_id The entity id to resize [br]
## @param p_radius The new effect radius
func set_radius(p_id: int, p_radius: float) -> void:
	_entityRadius[p_id] = p_radius
	_apply_chunk_area(p_id, _compute_chunk_area(_entityPosition[p_id], p_radius))


## Hands the ids of removed entities back for reuse and clears their state. [br]
## Call once after every system that could still hold a removed id has run.
func release_removed_ids() -> void:
	for l_id: int in _pendingFreeIds:
		_entityUnregistering[l_id] = 0
		_entityPreUnregistered[l_id] = 0
		_freeIds.append(l_id)
	
	_pendingFreeIds.clear()

#endregion

#region PUBLIC_QUERIES

## Checks whether an entity is already removed and only waiting for its id to be released. [br]
## @param p_id The entity to check [br]
## @return true if it is gone from the index
func is_unregistering(p_id: int) -> bool:
	return _entityUnregistering[p_id] == 1


## Reads the ids that were removed since the last release. [br]
## @return A snapshot of the ids waiting to be freed
func get_pending_free_ids() -> PackedInt32Array:
	return _pendingFreeIds


## Checks whether any team other than the asking one holds entities in a chunk. [br]
## @param p_chunkId The chunk to check [br]
## @param p_team The team that asks [br]
## @return true if an opponent stands there
func has_opponent_in_chunk(p_chunkId: int, p_team: int) -> bool:
	for l_team: int in _teamCount:
		if (l_team != p_team and _chunkCounts[l_team * _chunkCount + p_chunkId] > 0):
			return true
	
	return false


## Checks whether any team other than the asking one holds entities in a column. [br]
## @param p_columnIndex The column to check [br]
## @param p_team The team that asks [br]
## @return true if an opponent stands there
func has_opponent_in_column(p_columnIndex: int, p_team: int) -> bool:
	for l_team: int in _teamCount:
		if (l_team != p_team and _columnCounts[l_team * _chunkColumns + p_columnIndex] > 0):
			return true
	
	return false


## Checks whether any team other than the asking one stands left of a column. [br]
## Reads the outermost occupied column of every team, so the map width never enters the cost. [br]
## @param p_columnIndex The column to look out from [br]
## @param p_team The team that asks [br]
## @return true if an opponent stands further left
func has_opponent_before_column(p_columnIndex: int, p_team: int) -> bool:
	for l_team: int in _teamCount:
		var l_minColumn: int = _teamMinColumn[l_team]
		
		if (l_team != p_team and l_minColumn != C_ChunkingServer.NO_COLUMN and l_minColumn < p_columnIndex):
			return true
	
	return false


## Checks whether any team other than the asking one stands right of a column. [br]
## @param p_columnIndex The column to look out from [br]
## @param p_team The team that asks [br]
## @return true if an opponent stands further right
func has_opponent_after_column(p_columnIndex: int, p_team: int) -> bool:
	for l_team: int in _teamCount:
		var l_maxColumn: int = _teamMaxColumn[l_team]
		
		if (l_team != p_team and l_maxColumn != C_ChunkingServer.NO_COLUMN and l_maxColumn > p_columnIndex):
			return true
	
	return false


## Checks whether a chunk holds at least one of the searched groups. [br]
## @param p_chunkId The chunk to check [br]
## @param p_team Team to check, a C_ChunkingServer.TEAM value [br]
## @param p_groupMask Bitmask of the searched groups [br]
## @return true if at least one searched group bit is present
func chunk_has_group(p_chunkId: int, p_team: int, p_groupMask: int) -> bool:
	return (_chunkGroups[p_team * _chunkCount + p_chunkId] & p_groupMask) != 0


## Checks whether a column holds at least one of the searched groups. [br]
## @param p_columnIndex The column to check [br]
## @param p_team Team to check, a C_ChunkingServer.TEAM value [br]
## @param p_groupMask Bitmask of the searched groups [br]
## @return true if at least one searched group bit is present
func column_has_group(p_columnIndex: int, p_team: int, p_groupMask: int) -> bool:
	return (_columnGroups[p_team * _chunkColumns + p_columnIndex] & p_groupMask) != 0


## Checks whether the map holds at least one of the searched groups. [br]
## @param p_team Team to check, a C_ChunkingServer.TEAM value [br]
## @param p_groupMask Bitmask of the searched groups [br]
## @return true if at least one searched group bit is present
func map_has_group(p_team: int, p_groupMask: int) -> bool:
	return (_mapGroups[p_team] & p_groupMask) != 0


## Checks whether any opposing team holds one of the searched groups in a chunk. [br]
## Smallest step of the map to column to chunk filter a search walks down. [br]
## @param p_chunkId The chunk to check [br]
## @param p_team The team that asks [br]
## @param p_groupMask Bitmask of the searched groups [br]
## @return true if the chunk is worth opening
func chunk_has_opponent_group(p_chunkId: int, p_team: int, p_groupMask: int) -> bool:
	for l_team: int in _teamCount:
		if (l_team != p_team and (_chunkGroups[l_team * _chunkCount + p_chunkId] & p_groupMask) != 0):
			return true
	
	return false


## Checks whether any opposing team holds one of the searched groups in a column. [br]
## Skipping here skips every chunk of that column at once. [br]
## @param p_columnIndex The column to check [br]
## @param p_team The team that asks [br]
## @param p_groupMask Bitmask of the searched groups [br]
## @return true if the column is worth opening
func column_has_opponent_group(p_columnIndex: int, p_team: int, p_groupMask: int) -> bool:
	for l_team: int in _teamCount:
		if (l_team != p_team and (_columnGroups[l_team * _chunkColumns + p_columnIndex] & p_groupMask) != 0):
			return true
	
	return false


## Checks whether any opposing team holds one of the searched groups anywhere. [br]
## Widest step of the filter; a search that fails here never touches a chunk. [br]
## @param p_team The team that asks [br]
## @param p_groupMask Bitmask of the searched groups [br]
## @return true if a search could find anything at all
func map_has_opponent_group(p_team: int, p_groupMask: int) -> bool:
	for l_team: int in _teamCount:
		if (l_team != p_team and (_mapGroups[l_team] & p_groupMask) != 0):
			return true
	
	return false

#endregion

#region PUBLIC_INDEX

## Calculates the chunk rectangle an axis aligned box covers, clamped to the map. [br]
## Entities reach into every chunk their radius touches, so walking this area finds them all. [br]
## @param p_minCorner Upper left corner of the box [br]
## @param p_maxCorner Lower right corner of the box [br]
## @return The rectangle as (minColumn, minRow, maxColumn, maxRow)
func compute_chunk_area_from_bounds(p_minCorner: Vector2, p_maxCorner: Vector2) -> Vector4i:
	var l_lastColumn: int = _chunkColumns - 1
	var l_lastRow: int = _chunkRows - 1
	
	return Vector4i(
		clampi(floori(p_minCorner.x / _chunkSize), 0, l_lastColumn),
		clampi(floori(p_minCorner.y / _chunkSize), 0, l_lastRow),
		clampi(floori(p_maxCorner.x / _chunkSize), 0, l_lastColumn),
		clampi(floori(p_maxCorner.y / _chunkSize), 0, l_lastRow))


## Lists every chunk inside a chunk rectangle. [br]
## Only for callers that need the list itself; walking an area is done with two loops. [br]
## @param p_area The rectangle as (minColumn, minRow, maxColumn, maxRow) [br]
## @return The chunk ids inside the rectangle, in ascending order
func collect_chunks_in_area(p_area: Vector4i) -> PackedInt32Array:
	var l_chunkIds: PackedInt32Array = PackedInt32Array()
	l_chunkIds.resize((p_area.z - p_area.x + 1) * (p_area.w - p_area.y + 1))
	
	var l_writeIndex: int = 0
	for l_row: int in range(p_area.y, p_area.w + 1):
		var l_rowOffset: int = l_row * _chunkColumns
		
		for l_column: int in range(p_area.x, p_area.z + 1):
			l_chunkIds[l_writeIndex] = l_rowOffset + l_column
			l_writeIndex += 1
	
	return l_chunkIds

#endregion

#region PRIVATE_METHODS

## Determines the column a chunk belongs to. [br]
## @param p_chunkId The chunk to resolve [br]
## @return The column index of that chunk
func _get_column_index(p_chunkId: int) -> int:
	return p_chunkId % _chunkColumns


## Maps team and chunk onto the slot inside the per team chunk containers. [br]
## @param p_team Team block to address, a C_ChunkingServer.TEAM value [br]
## @param p_chunkId The chunk inside that block [br]
## @return The flat container index
func _get_team_chunk_index(p_team: int, p_chunkId: int) -> int:
	return p_team * _chunkCount + p_chunkId


## Maps team and column onto the slot inside the per team column containers. [br]
## @param p_team Team block to address, a C_ChunkingServer.TEAM value [br]
## @param p_columnIndex The column inside that block [br]
## @return The flat container index
func _get_team_column_index(p_team: int, p_columnIndex: int) -> int:
	return p_team * _chunkColumns + p_columnIndex


## Takes a free entity id or appends a fresh slot to every entity container. [br]
## @return The id the next entity is stored under
func _acquire_id() -> int:
	var l_lastFreeIndex: int = _freeIds.size() - 1
	
	if (l_lastFreeIndex >= 0):
		var l_reusedId: int = _freeIds[l_lastFreeIndex]
		_freeIds.remove_at(l_lastFreeIndex)
		return l_reusedId
	
	_entityTeam.append(0)
	_entityGroups.append(0)
	_entityPosition.append(Vector2.ZERO)
	_entityRadius.append(0.0)
	_entityPreUnregistered.append(0)
	_entityUnregistering.append(0)
	_entityChunkArea.append(Vector4i.ZERO)
	_entitySlotHead.append(C_ChunkingServer.NO_SLOT)
	_entityCenterChunk.append(C_ChunkingServer.NO_COLUMN)
	_entityCenterColumn.append(0)
	_entityCenterRow.append(0)
	_centerNext.append(C_ChunkingServer.NO_ENTITY)
	_centerPrev.append(C_ChunkingServer.NO_ENTITY)
	
	return _entityTeam.size() - 1


## Calculates the chunk rectangle a position and radius cover, clamped to the map. [br]
## Allocation free, so callers can compare it against the last area before doing any work. [br]
## @param p_position Center of the covered area [br]
## @param p_radius Radius of the covered area [br]
## @return The rectangle as (minColumn, minRow, maxColumn, maxRow)
func _compute_chunk_area(p_position: Vector2, p_radius: float) -> Vector4i:
	var l_extent: Vector2 = Vector2(p_radius, p_radius)
	return compute_chunk_area_from_bounds(p_position - l_extent, p_position + l_extent)


## Moves an entity onto a new chunk rectangle, touching only the chunks it entered or left. [br]
## Returns at once while the rectangle is unchanged, which is the common case when moving. [br]
## Both sides are rectangles, so telling them apart is a bounds test per chunk, never a search. [br]
## @param p_id The entity id to update [br]
## @param p_area The new rectangle as (minColumn, minRow, maxColumn, maxRow)
func _apply_chunk_area(p_id: int, p_area: Vector4i) -> void:
	var l_oldArea: Vector4i = _entityChunkArea[p_id]
	
	if (p_area == l_oldArea):
		return
	
	_entityChunkArea[p_id] = p_area
	
	var l_slot: int = _entitySlotHead[p_id]
	while (l_slot != C_ChunkingServer.NO_SLOT):
		var l_nextSlot: int = _slotEntityNext[l_slot]
		
		if (not _is_chunk_in_area(_slotChunk[l_slot], p_area)):
			_remove_slot_from_chunk(l_slot)
		
		l_slot = l_nextSlot
	
	for l_row: int in range(p_area.y, p_area.w + 1):
		var l_rowOffset: int = l_row * _chunkColumns
		var l_rowIsNew: bool = l_row < l_oldArea.y or l_row > l_oldArea.w
		
		for l_column: int in range(p_area.x, p_area.z + 1):
			if (l_rowIsNew or l_column < l_oldArea.x or l_column > l_oldArea.z):
				_add_entity_to_chunk(p_id, l_rowOffset + l_column)


## Checks whether a chunk lies inside a chunk rectangle. [br]
## @param p_chunkId The chunk to place [br]
## @param p_area The rectangle as (minColumn, minRow, maxColumn, maxRow) [br]
## @return true if the chunk is part of the rectangle
func _is_chunk_in_area(p_chunkId: int, p_area: Vector4i) -> bool:
	var l_column: int = p_chunkId % _chunkColumns
	
	if (l_column < p_area.x or l_column > p_area.z):
		return false
	
	@warning_ignore("integer_division")
	var l_row: int = p_chunkId / _chunkColumns
	
	return l_row >= p_area.y and l_row <= p_area.w


## Moves the center of an entity into the chunk its position falls into. [br]
## Drops out while the center chunk is unchanged, which is the common case when moving. [br]
## @param p_id The entity id to update [br]
## @param p_position The position the center is taken from
func _apply_center_chunk(p_id: int, p_position: Vector2) -> void:
	var l_column: int = clampi(floori(p_position.x / _chunkSize), 0, _chunkColumns - 1)
	var l_row: int = clampi(floori(p_position.y / _chunkSize), 0, _chunkRows - 1)
	var l_chunkId: int = l_row * _chunkColumns + l_column
	
	if (l_chunkId == _entityCenterChunk[p_id]):
		return
	
	_remove_center_from_chunk(p_id)
	
	var l_headIndex: int = _entityTeam[p_id] * _chunkCount + l_chunkId
	var l_head: int = _centerHead[l_headIndex]
	_centerPrev[p_id] = C_ChunkingServer.NO_ENTITY
	_centerNext[p_id] = l_head
	
	if (l_head != C_ChunkingServer.NO_ENTITY):
		_centerPrev[l_head] = p_id
	
	_centerHead[l_headIndex] = p_id
	_entityCenterChunk[p_id] = l_chunkId
	_entityCenterColumn[p_id] = l_column
	_entityCenterRow[p_id] = l_row


## Unlinks the center of an entity from the chain of its chunk. [br]
## @param p_id The entity whose center is removed
func _remove_center_from_chunk(p_id: int) -> void:
	var l_chunkId: int = _entityCenterChunk[p_id]
	
	if (l_chunkId == C_ChunkingServer.NO_COLUMN):
		return
	
	var l_next: int = _centerNext[p_id]
	var l_prev: int = _centerPrev[p_id]
	
	if (l_prev == C_ChunkingServer.NO_ENTITY):
		_centerHead[_entityTeam[p_id] * _chunkCount + l_chunkId] = l_next
	else:
		_centerNext[l_prev] = l_next
	
	if (l_next != C_ChunkingServer.NO_ENTITY):
		_centerPrev[l_next] = l_prev
	
	_entityCenterChunk[p_id] = C_ChunkingServer.NO_COLUMN


## Adds an entity to a chunk and cascades its groups upwards while they change. [br]
## Links one membership slot into the chain of the chunk and of the entity; no list is ever copied. [br]
## @param p_id The entity id to add [br]
## @param p_chunkId The target chunk
func _add_entity_to_chunk(p_id: int, p_chunkId: int) -> void:
	var l_slot: int = _acquire_slot()
	
	_slotEntity[l_slot] = p_id
	_slotChunk[l_slot] = p_chunkId
	
	var l_chunkHead: int = _chunkHead[p_chunkId]
	_slotChunkPrev[l_slot] = C_ChunkingServer.NO_SLOT
	_slotChunkNext[l_slot] = l_chunkHead
	
	if (l_chunkHead != C_ChunkingServer.NO_SLOT):
		_slotChunkPrev[l_chunkHead] = l_slot
	
	_chunkHead[p_chunkId] = l_slot
	
	var l_entityHead: int = _entitySlotHead[p_id]
	_slotEntityPrev[l_slot] = C_ChunkingServer.NO_SLOT
	_slotEntityNext[l_slot] = l_entityHead
	
	if (l_entityHead != C_ChunkingServer.NO_SLOT):
		_slotEntityPrev[l_entityHead] = l_slot
	
	_entitySlotHead[p_id] = l_slot
	
	var l_team: int = _entityTeam[p_id]
	var l_groups: int = _entityGroups[p_id]
	var l_chunkIndex: int = _get_team_chunk_index(l_team, p_chunkId)
	var l_mergedGroups: int = _chunkGroups[l_chunkIndex] | l_groups
	
	_apply_count_delta(p_chunkId, l_team, 1)
	
	if (l_mergedGroups == _chunkGroups[l_chunkIndex]):
		return
	
	_chunkGroups[l_chunkIndex] = l_mergedGroups
	
	if (_apply_group_to_column(_get_column_index(p_chunkId), l_team, l_groups)):
		_apply_group_to_map(l_team, l_groups)


## Unlinks one membership slot and rebuilds the masks upwards while they change. [br]
## Unlinking is a fixed number of integer writes, whatever the chunk holds. [br]
## @param p_slot The membership slot to drop
func _remove_slot_from_chunk(p_slot: int) -> void:
	var l_id: int = _slotEntity[p_slot]
	var l_chunkId: int = _slotChunk[p_slot]
	
	var l_next: int = _slotChunkNext[p_slot]
	var l_prev: int = _slotChunkPrev[p_slot]
	
	if (l_prev == C_ChunkingServer.NO_SLOT):
		_chunkHead[l_chunkId] = l_next
	else:
		_slotChunkNext[l_prev] = l_next
	
	if (l_next != C_ChunkingServer.NO_SLOT):
		_slotChunkPrev[l_next] = l_prev
	
	l_next = _slotEntityNext[p_slot]
	l_prev = _slotEntityPrev[p_slot]
	
	if (l_prev == C_ChunkingServer.NO_SLOT):
		_entitySlotHead[l_id] = l_next
	else:
		_slotEntityNext[l_prev] = l_next
	
	if (l_next != C_ChunkingServer.NO_SLOT):
		_slotEntityPrev[l_next] = l_prev
	
	_freeSlots.append(p_slot)
	
	var l_team: int = _entityTeam[l_id]
	_apply_count_delta(l_chunkId, l_team, -1)
	
	if (_rebuild_chunk_groups(l_chunkId, l_team)):
		if (_rebuild_column_groups(_get_column_index(l_chunkId), l_team)):
			_rebuild_map_groups(l_team)


## Takes a free membership slot or appends a fresh one to every slot column. [br]
## @return The slot the next membership is stored under
func _acquire_slot() -> int:
	var l_lastFreeIndex: int = _freeSlots.size() - 1
	
	if (l_lastFreeIndex >= 0):
		var l_reusedSlot: int = _freeSlots[l_lastFreeIndex]
		_freeSlots.resize(l_lastFreeIndex)
		return l_reusedSlot
	
	_slotEntity.append(0)
	_slotChunk.append(0)
	_slotChunkNext.append(C_ChunkingServer.NO_SLOT)
	_slotChunkPrev.append(C_ChunkingServer.NO_SLOT)
	_slotEntityNext.append(C_ChunkingServer.NO_SLOT)
	_slotEntityPrev.append(C_ChunkingServer.NO_SLOT)
	
	return _slotEntity.size() - 1


## Writes a count change through to chunk, column and map and keeps the column span current. [br]
## @param p_chunkId The chunk the entity was added to or removed from [br]
## @param p_team Team whose counts change, a C_ChunkingServer.TEAM value [br]
## @param p_delta The change to apply, 1 when adding and -1 when removing
func _apply_count_delta(p_chunkId: int, p_team: int, p_delta: int) -> void:
	var l_column: int = p_chunkId % _chunkColumns
	var l_columnIndex: int = p_team * _chunkColumns + l_column
	var l_columnCountBefore: int = _columnCounts[l_columnIndex]
	
	_chunkCounts[p_team * _chunkCount + p_chunkId] += p_delta
	_columnCounts[l_columnIndex] = l_columnCountBefore + p_delta
	_mapCounts[p_team] += p_delta
	
	if (p_delta > 0 and l_columnCountBefore == 0):
		_extend_team_columns(p_team, l_column)
	elif (p_delta < 0 and l_columnCountBefore + p_delta == 0):
		_shrink_team_columns(p_team, l_column)


## Widens the occupied column span of a team by a column that just filled up. [br]
## @param p_team The team whose span grows [br]
## @param p_columnIndex The column that now holds entities
func _extend_team_columns(p_team: int, p_columnIndex: int) -> void:
	if (_teamMinColumn[p_team] == C_ChunkingServer.NO_COLUMN or p_columnIndex < _teamMinColumn[p_team]):
		_teamMinColumn[p_team] = p_columnIndex
	
	if (_teamMaxColumn[p_team] == C_ChunkingServer.NO_COLUMN or p_columnIndex > _teamMaxColumn[p_team]):
		_teamMaxColumn[p_team] = p_columnIndex


## Pulls the occupied column span of a team in after a column ran empty. [br]
## Only scans when the emptied column was the span edge itself, so the cost amortises away. [br]
## @param p_team The team whose span shrinks [br]
## @param p_columnIndex The column that ran empty
func _shrink_team_columns(p_team: int, p_columnIndex: int) -> void:
	if (_mapCounts[p_team] == 0):
		_teamMinColumn[p_team] = C_ChunkingServer.NO_COLUMN
		_teamMaxColumn[p_team] = C_ChunkingServer.NO_COLUMN
		return
	
	var l_firstColumnIndex: int = p_team * _chunkColumns
	
	if (p_columnIndex == _teamMinColumn[p_team]):
		var l_column: int = p_columnIndex + 1
		
		while (_columnCounts[l_firstColumnIndex + l_column] == 0):
			l_column += 1
		
		_teamMinColumn[p_team] = l_column
	
	if (p_columnIndex == _teamMaxColumn[p_team]):
		var l_column: int = p_columnIndex - 1
		
		while (_columnCounts[l_firstColumnIndex + l_column] == 0):
			l_column -= 1
		
		_teamMaxColumn[p_team] = l_column


## Rebuilds the group mask of a chunk from the entities still standing in it. [br]
## Only reached while removing, so the mask can only shrink and the scan stops once it reaches the old value. [br]
## @param p_chunkId The chunk to rebuild [br]
## @param p_team Team whose mask is rebuilt, a C_ChunkingServer.TEAM value [br]
## @return true if the mask value changed
func _rebuild_chunk_groups(p_chunkId: int, p_team: int) -> bool:
	var l_chunkIndex: int = _get_team_chunk_index(p_team, p_chunkId)
	var l_oldGroups: int = _chunkGroups[l_chunkIndex]
	var l_groups: int = 0
	
	var l_slot: int = _chunkHead[p_chunkId]
	while (l_slot != C_ChunkingServer.NO_SLOT):
		var l_id: int = _slotEntity[l_slot]
		
		if (_entityTeam[l_id] == p_team):
			l_groups |= _entityGroups[l_id]
			
			if (l_groups == l_oldGroups):
				break
		
		l_slot = _slotChunkNext[l_slot]
	
	if (l_groups == l_oldGroups):
		return false
	
	_chunkGroups[l_chunkIndex] = l_groups
	return true


## Merges a group mask into a column mask — counterpart of the add path. [br]
## @param p_columnIndex The column to extend [br]
## @param p_team Team whose mask is extended, a C_ChunkingServer.TEAM value [br]
## @param p_groups The group bits to merge in [br]
## @return true if the mask value changed
func _apply_group_to_column(p_columnIndex: int, p_team: int, p_groups: int) -> bool:
	var l_columnIndex: int = _get_team_column_index(p_team, p_columnIndex)
	var l_mergedGroups: int = _columnGroups[l_columnIndex] | p_groups
	
	if (l_mergedGroups == _columnGroups[l_columnIndex]):
		return false
	
	_columnGroups[l_columnIndex] = l_mergedGroups
	return true


## Rebuilds a column mask from the chunk masks of that column — counterpart of the remove path. [br]
## Stops as soon as the old value is reached again, because the mask can only shrink here. [br]
## @param p_columnIndex The column to rebuild [br]
## @param p_team Team whose mask is rebuilt, a C_ChunkingServer.TEAM value [br]
## @return true if the mask value changed
func _rebuild_column_groups(p_columnIndex: int, p_team: int) -> bool:
	var l_columnIndex: int = _get_team_column_index(p_team, p_columnIndex)
	var l_oldGroups: int = _columnGroups[l_columnIndex]
	var l_groups: int = 0
	var l_firstChunkIndex: int = _get_team_chunk_index(p_team, p_columnIndex)
	
	for l_rowOffset: int in _chunkRows:
		l_groups |= _chunkGroups[l_firstChunkIndex + l_rowOffset * _chunkColumns]
		
		if (l_groups == l_oldGroups):
			break
	
	if (l_groups == l_oldGroups):
		return false
	
	_columnGroups[l_columnIndex] = l_groups
	return true


## Merges a group mask into the map mask — last step of the add cascade. [br]
## @param p_team Team whose mask is extended, a C_ChunkingServer.TEAM value [br]
## @param p_groups The group bits to merge in
func _apply_group_to_map(p_team: int, p_groups: int) -> void:
	_mapGroups[p_team] |= p_groups


## Rebuilds the map mask from all column masks, never from chunks directly. [br]
## Stops as soon as the old value is reached again, because the mask can only shrink here. [br]
## @param p_team Team whose mask is rebuilt, a C_ChunkingServer.TEAM value
func _rebuild_map_groups(p_team: int) -> void:
	var l_oldGroups: int = _mapGroups[p_team]
	var l_groups: int = 0
	var l_firstColumnIndex: int = _get_team_column_index(p_team, 0)
	
	for l_columnOffset: int in _chunkColumns:
		l_groups |= _columnGroups[l_firstColumnIndex + l_columnOffset]
		
		if (l_groups == l_oldGroups):
			return
	
	_mapGroups[p_team] = l_groups

#endregion

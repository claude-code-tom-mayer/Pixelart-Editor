extends RefCounted
## Sorts entities into square chunks, columns and one map aggregate for fast group queries. [br]
## Counts are always written through, group masks only cascade upwards when they really change.
class_name ChunkingServer

#region PUBLIC_VARIABLES

## Team per entity id, as a C_ChunkingServer.TEAM value.
var entityTeam: PackedByteArray = PackedByteArray()

## Bitmask of the groups an entity belongs to.
var entityGroups: PackedInt64Array = PackedInt64Array()

## Current position per entity id.
var entityPosition: PackedVector2Array = PackedVector2Array()

## Effect radius per entity id; decides in how many chunks the entity stands.
var entityRadius: PackedFloat32Array = PackedFloat32Array()

## 1 while an entity is announced for removal but still fully active.
var entityPreUnregistered: PackedByteArray = PackedByteArray()

## 1 while an entity is removed but its id stays locked until it is released.
var entityUnregistering: PackedByteArray = PackedByteArray()

## Chunk rectangle an entity covers as (minColumn, minRow, maxColumn, maxRow). [br]
## Lets set_position() and set_radius() drop out before touching any chunk.
var entityChunkArea: Array[Vector4i] = []

## All chunks an entity currently stands in, per entity id.
var entityChunkIds: Array[PackedInt32Array] = []

## Entity ids per chunk.
var entitiesInChunk: Array[PackedInt32Array] = []

## Entity count per team and chunk, addressed by _get_team_chunk_index().
var chunkCounts: PackedInt32Array = PackedInt32Array()

## Entity count per team and column, addressed by _get_team_column_index().
var columnCounts: PackedInt32Array = PackedInt32Array()

## Ids removed since the last release; moved into the free list by release_removed_ids().
var pendingFreeIds: PackedInt32Array = PackedInt32Array()

#endregion

#region PRIVATE_VARIABLES

## Entity ids that may be reused; only filled by release_removed_ids().
var _freeIds: PackedInt32Array = PackedInt32Array()

## Slot of the entity inside entitiesInChunk, parallel to entityChunkIds. [br]
## Makes removal from a chunk an O(1) swap-and-pop.
var _entityChunkIndices: Array[PackedInt32Array] = []

## Group bitmask per team and chunk, addressed by _get_team_chunk_index().
var _chunkGroups: PackedInt64Array = PackedInt64Array()

## Group bitmask per team and column — the OR of the chunk masks of that column. [br]
## Columns are the aggregation level because the two bases face each other along x.
var _columnGroups: PackedInt64Array = PackedInt64Array()

## Group bitmask per team over the whole map — the OR of all column masks.
var _mapGroups: PackedInt64Array = PackedInt64Array()

## Entity count per team over the whole map.
var _mapCounts: PackedInt32Array = PackedInt32Array()

#endregion

#region LIFECYCLE

## Allocates the chunk, column and map containers for the configured grid.
func _init() -> void:
	var l_chunkSlots: int = C_ChunkingServer.TEAM_COUNT * C_ChunkingServer.CHUNK_COUNT
	var l_columnSlots: int = C_ChunkingServer.TEAM_COUNT * C_ChunkingServer.MAP_CHUNK_COLUMNS
	
	_chunkGroups.resize(l_chunkSlots)
	chunkCounts.resize(l_chunkSlots)
	_columnGroups.resize(l_columnSlots)
	columnCounts.resize(l_columnSlots)
	_mapGroups.resize(C_ChunkingServer.TEAM_COUNT)
	_mapCounts.resize(C_ChunkingServer.TEAM_COUNT)
	
	entitiesInChunk.resize(C_ChunkingServer.CHUNK_COUNT)
	for l_chunkId: int in C_ChunkingServer.CHUNK_COUNT:
		entitiesInChunk[l_chunkId] = PackedInt32Array()

#endregion

#region PUBLIC_METHODS

## Registers a new entity and adds it to every chunk its radius covers. [br]
## @param p_position Start position of the entity [br]
## @param p_radius Effect radius of the entity [br]
## @param p_team Team of the entity, a C_ChunkingServer.TEAM value [br]
## @param p_groups Bitmask of the groups the entity belongs to [br]
## @return The assigned entity id
func register_entity(p_position: Vector2, p_radius: float, p_team: int, p_groups: int) -> int:
	var l_id: int = _acquire_id()
	
	entityTeam[l_id] = p_team
	entityGroups[l_id] = p_groups
	entityPosition[l_id] = p_position
	entityRadius[l_id] = p_radius
	
	var l_area: Vector4i = _compute_chunk_area(p_position, p_radius)
	entityChunkArea[l_id] = l_area
	
	for l_chunkId: int in collect_chunks_in_area(l_area):
		_add_entity_to_chunk(l_id, l_chunkId)
	
	return l_id


## Marks an entity for removal; it stays fully active and queryable. [br]
## @param p_id The entity id to mark
func pre_unregister_entity(p_id: int) -> void:
	entityPreUnregistered[p_id] = 1


## Removes an entity from all its chunks and locks its id until it is released. [br]
## @param p_id The entity id to remove
func unregister_entity(p_id: int) -> void:
	entityUnregistering[p_id] = 1
	
	var l_chunkIds: PackedInt32Array = entityChunkIds[p_id].duplicate()
	for l_chunkId: int in l_chunkIds:
		_remove_entity_from_chunk(p_id, l_chunkId)
	
	pendingFreeIds.append(p_id)


## Moves an entity and updates only the chunks it entered or left. [br]
## @param p_id The entity id to move [br]
## @param p_position The new position
func set_position(p_id: int, p_position: Vector2) -> void:
	entityPosition[p_id] = p_position
	_apply_chunk_area(p_id, _compute_chunk_area(p_position, entityRadius[p_id]))


## Resizes an entity and updates only the chunks it entered or left. [br]
## @param p_id The entity id to resize [br]
## @param p_radius The new effect radius
func set_radius(p_id: int, p_radius: float) -> void:
	entityRadius[p_id] = p_radius
	_apply_chunk_area(p_id, _compute_chunk_area(entityPosition[p_id], p_radius))


## Hands the ids of removed entities back for reuse and clears their state. [br]
## Call once after every system that could still hold a removed id has run.
func release_removed_ids() -> void:
	for l_id: int in pendingFreeIds:
		entityUnregistering[l_id] = 0
		entityPreUnregistered[l_id] = 0
		_freeIds.append(l_id)
	
	pendingFreeIds.clear()

#endregion

#region PUBLIC_QUERIES

## Checks whether any team other than the asking one holds entities in a chunk. [br]
## @param p_chunkId The chunk to check [br]
## @param p_team The team that asks [br]
## @return true if an opponent stands there
func has_opponent_in_chunk(p_chunkId: int, p_team: int) -> bool:
	for l_team: int in C_ChunkingServer.TEAM_COUNT:
		if (l_team != p_team and chunkCounts[_get_team_chunk_index(l_team, p_chunkId)] > 0):
			return true
	
	return false


## Checks whether any team other than the asking one holds entities in a column. [br]
## @param p_columnIndex The column to check [br]
## @param p_team The team that asks [br]
## @return true if an opponent stands there
func has_opponent_in_column(p_columnIndex: int, p_team: int) -> bool:
	for l_team: int in C_ChunkingServer.TEAM_COUNT:
		if (l_team != p_team and columnCounts[_get_team_column_index(l_team, p_columnIndex)] > 0):
			return true
	
	return false


## Checks whether a chunk holds at least one of the searched groups. [br]
## @param p_chunkId The chunk to check [br]
## @param p_team Team to check, a C_ChunkingServer.TEAM value [br]
## @param p_groupMask Bitmask of the searched groups [br]
## @return true if at least one searched group bit is present
func chunk_has_group(p_chunkId: int, p_team: int, p_groupMask: int) -> bool:
	return (_chunkGroups[_get_team_chunk_index(p_team, p_chunkId)] & p_groupMask) != 0


## Checks whether a column holds at least one of the searched groups. [br]
## @param p_columnIndex The column to check [br]
## @param p_team Team to check, a C_ChunkingServer.TEAM value [br]
## @param p_groupMask Bitmask of the searched groups [br]
## @return true if at least one searched group bit is present
func column_has_group(p_columnIndex: int, p_team: int, p_groupMask: int) -> bool:
	return (_columnGroups[_get_team_column_index(p_team, p_columnIndex)] & p_groupMask) != 0


## Checks whether the map holds at least one of the searched groups. [br]
## @param p_team Team to check, a C_ChunkingServer.TEAM value [br]
## @param p_groupMask Bitmask of the searched groups [br]
## @return true if at least one searched group bit is present
func map_has_group(p_team: int, p_groupMask: int) -> bool:
	return (_mapGroups[p_team] & p_groupMask) != 0

#endregion

#region PUBLIC_INDEX

## Calculates the chunk rectangle an axis aligned box covers, clamped to the map. [br]
## Entities reach into every chunk their radius touches, so walking this area finds them all. [br]
## @param p_minCorner Upper left corner of the box [br]
## @param p_maxCorner Lower right corner of the box [br]
## @return The rectangle as (minColumn, minRow, maxColumn, maxRow)
func compute_chunk_area_from_bounds(p_minCorner: Vector2, p_maxCorner: Vector2) -> Vector4i:
	var l_chunkSize: float = C_ChunkingServer.CHUNK_SIZE
	var l_lastColumn: int = C_ChunkingServer.MAP_CHUNK_COLUMNS - 1
	var l_lastRow: int = C_ChunkingServer.MAP_CHUNK_ROWS - 1
	
	return Vector4i(
		clampi(floori(p_minCorner.x / l_chunkSize), 0, l_lastColumn),
		clampi(floori(p_minCorner.y / l_chunkSize), 0, l_lastRow),
		clampi(floori(p_maxCorner.x / l_chunkSize), 0, l_lastColumn),
		clampi(floori(p_maxCorner.y / l_chunkSize), 0, l_lastRow))


## Lists every chunk inside a chunk rectangle. [br]
## @param p_area The rectangle as (minColumn, minRow, maxColumn, maxRow) [br]
## @return The chunk ids inside the rectangle, in ascending order
func collect_chunks_in_area(p_area: Vector4i) -> PackedInt32Array:
	var l_chunkIds: PackedInt32Array = PackedInt32Array()
	l_chunkIds.resize((p_area.z - p_area.x + 1) * (p_area.w - p_area.y + 1))
	
	var l_writeIndex: int = 0
	for l_row: int in range(p_area.y, p_area.w + 1):
		var l_rowOffset: int = l_row * C_ChunkingServer.MAP_CHUNK_COLUMNS
		
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
	return p_chunkId % C_ChunkingServer.MAP_CHUNK_COLUMNS


## Maps team and chunk onto the slot inside the per team chunk containers. [br]
## @param p_team Team block to address, a C_ChunkingServer.TEAM value [br]
## @param p_chunkId The chunk inside that block [br]
## @return The flat container index
func _get_team_chunk_index(p_team: int, p_chunkId: int) -> int:
	return p_team * C_ChunkingServer.CHUNK_COUNT + p_chunkId


## Maps team and column onto the slot inside the per team column containers. [br]
## @param p_team Team block to address, a C_ChunkingServer.TEAM value [br]
## @param p_columnIndex The column inside that block [br]
## @return The flat container index
func _get_team_column_index(p_team: int, p_columnIndex: int) -> int:
	return p_team * C_ChunkingServer.MAP_CHUNK_COLUMNS + p_columnIndex


## Takes a free entity id or appends a fresh slot to every entity container. [br]
## @return The id the next entity is stored under
func _acquire_id() -> int:
	var l_lastFreeIndex: int = _freeIds.size() - 1
	
	if (l_lastFreeIndex >= 0):
		var l_reusedId: int = _freeIds[l_lastFreeIndex]
		_freeIds.remove_at(l_lastFreeIndex)
		return l_reusedId
	
	entityTeam.append(0)
	entityGroups.append(0)
	entityPosition.append(Vector2.ZERO)
	entityRadius.append(0.0)
	entityPreUnregistered.append(0)
	entityUnregistering.append(0)
	entityChunkArea.append(Vector4i.ZERO)
	entityChunkIds.append(PackedInt32Array())
	_entityChunkIndices.append(PackedInt32Array())
	
	return entityTeam.size() - 1


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
## @param p_id The entity id to update [br]
## @param p_area The new rectangle as (minColumn, minRow, maxColumn, maxRow)
func _apply_chunk_area(p_id: int, p_area: Vector4i) -> void:
	if (p_area == entityChunkArea[p_id]):
		return
	
	entityChunkArea[p_id] = p_area
	
	var l_newChunkIds: PackedInt32Array = collect_chunks_in_area(p_area)
	var l_oldChunkIds: PackedInt32Array = entityChunkIds[p_id].duplicate()
	
	for l_chunkId: int in l_oldChunkIds:
		if (not l_newChunkIds.has(l_chunkId)):
			_remove_entity_from_chunk(p_id, l_chunkId)
	
	for l_chunkId: int in l_newChunkIds:
		if (not l_oldChunkIds.has(l_chunkId)):
			_add_entity_to_chunk(p_id, l_chunkId)


## Adds an entity to a chunk and cascades its groups upwards while they change. [br]
## @param p_id The entity id to add [br]
## @param p_chunkId The target chunk
func _add_entity_to_chunk(p_id: int, p_chunkId: int) -> void:
	var l_chunkEntities: PackedInt32Array = entitiesInChunk[p_chunkId]
	var l_chunkIds: PackedInt32Array = entityChunkIds[p_id]
	var l_chunkIndices: PackedInt32Array = _entityChunkIndices[p_id]
	
	l_chunkIds.append(p_chunkId)
	l_chunkIndices.append(l_chunkEntities.size())
	l_chunkEntities.append(p_id)
	
	entityChunkIds[p_id] = l_chunkIds
	_entityChunkIndices[p_id] = l_chunkIndices
	entitiesInChunk[p_chunkId] = l_chunkEntities
	
	var l_team: int = entityTeam[p_id]
	var l_groups: int = entityGroups[p_id]
	var l_chunkIndex: int = _get_team_chunk_index(l_team, p_chunkId)
	var l_mergedGroups: int = _chunkGroups[l_chunkIndex] | l_groups
	
	_apply_count_delta(p_chunkId, l_team, 1)
	
	if (l_mergedGroups == _chunkGroups[l_chunkIndex]):
		return
	
	_chunkGroups[l_chunkIndex] = l_mergedGroups
	
	if (_apply_group_to_column(_get_column_index(p_chunkId), l_team, l_groups)):
		_apply_group_to_map(l_team, l_groups)


## Removes an entity from a chunk and rebuilds the masks upwards while they change. [br]
## @param p_id The entity id to remove [br]
## @param p_chunkId The source chunk
func _remove_entity_from_chunk(p_id: int, p_chunkId: int) -> void:
	var l_slot: int = entityChunkIds[p_id].find(p_chunkId)
	var l_indexInChunk: int = _entityChunkIndices[p_id][l_slot]
	
	_swap_and_pop_chunk_entity(p_chunkId, l_indexInChunk)
	_swap_and_pop_entity_slot(p_id, l_slot)
	
	var l_team: int = entityTeam[p_id]
	_apply_count_delta(p_chunkId, l_team, -1)
	
	if (_rebuild_chunk_groups(p_chunkId, l_team)):
		if (_rebuild_column_groups(_get_column_index(p_chunkId), l_team)):
			_rebuild_map_groups(l_team)


## Drops one slot out of a chunk list and repairs the index of the moved entity. [br]
## @param p_chunkId The chunk to shrink [br]
## @param p_indexInChunk The slot the last entry is moved into
func _swap_and_pop_chunk_entity(p_chunkId: int, p_indexInChunk: int) -> void:
	var l_chunkEntities: PackedInt32Array = entitiesInChunk[p_chunkId]
	var l_lastIndex: int = l_chunkEntities.size() - 1
	var l_movedId: int = l_chunkEntities[l_lastIndex]
	
	l_chunkEntities[p_indexInChunk] = l_movedId
	l_chunkEntities.resize(l_lastIndex)
	entitiesInChunk[p_chunkId] = l_chunkEntities
	
	var l_movedIndices: PackedInt32Array = _entityChunkIndices[l_movedId]
	l_movedIndices[entityChunkIds[l_movedId].find(p_chunkId)] = p_indexInChunk
	_entityChunkIndices[l_movedId] = l_movedIndices


## Drops one chunk entry out of an entity by swap-and-pop. [br]
## @param p_id The entity to shrink [br]
## @param p_slot The entry the last one is moved into
func _swap_and_pop_entity_slot(p_id: int, p_slot: int) -> void:
	var l_chunkIds: PackedInt32Array = entityChunkIds[p_id]
	var l_chunkIndices: PackedInt32Array = _entityChunkIndices[p_id]
	var l_lastSlot: int = l_chunkIds.size() - 1
	
	l_chunkIds[p_slot] = l_chunkIds[l_lastSlot]
	l_chunkIndices[p_slot] = l_chunkIndices[l_lastSlot]
	l_chunkIds.resize(l_lastSlot)
	l_chunkIndices.resize(l_lastSlot)
	
	entityChunkIds[p_id] = l_chunkIds
	_entityChunkIndices[p_id] = l_chunkIndices


## Writes a count change through to chunk, column and map at once. [br]
## @param p_chunkId The chunk the entity was added to or removed from [br]
## @param p_team Team whose counts change, a C_ChunkingServer.TEAM value [br]
## @param p_delta The change to apply, 1 when adding and -1 when removing
func _apply_count_delta(p_chunkId: int, p_team: int, p_delta: int) -> void:
	chunkCounts[_get_team_chunk_index(p_team, p_chunkId)] += p_delta
	columnCounts[_get_team_column_index(p_team, _get_column_index(p_chunkId))] += p_delta
	_mapCounts[p_team] += p_delta


## Rebuilds the group mask of a chunk from the entities still standing in it. [br]
## Only reached while removing, so the mask can only shrink and the scan stops once it reaches the old value. [br]
## @param p_chunkId The chunk to rebuild [br]
## @param p_team Team whose mask is rebuilt, a C_ChunkingServer.TEAM value [br]
## @return true if the mask value changed
func _rebuild_chunk_groups(p_chunkId: int, p_team: int) -> bool:
	var l_chunkIndex: int = _get_team_chunk_index(p_team, p_chunkId)
	var l_oldGroups: int = _chunkGroups[l_chunkIndex]
	var l_groups: int = 0
	
	for l_id: int in entitiesInChunk[p_chunkId]:
		if (entityTeam[l_id] == p_team):
			l_groups |= entityGroups[l_id]
			
			if (l_groups == l_oldGroups):
				break
	
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
	
	for l_rowOffset: int in C_ChunkingServer.MAP_CHUNK_ROWS:
		l_groups |= _chunkGroups[l_firstChunkIndex + l_rowOffset * C_ChunkingServer.MAP_CHUNK_COLUMNS]
		
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
	
	for l_columnOffset: int in C_ChunkingServer.MAP_CHUNK_COLUMNS:
		l_groups |= _columnGroups[l_firstColumnIndex + l_columnOffset]
		
		if (l_groups == l_oldGroups):
			return
	
	_mapGroups[p_team] = l_groups

#endregion

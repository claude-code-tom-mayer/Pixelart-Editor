extends A_CoreServers
## Autoload that queries the spatial index and lets entities move or resize inside it. [br]
## Registration and removal now live on A_CoreServers; this file is chunking's own query surface.

#region LIFECYCLE_AND_METHODS

## Moves an entity and updates only the chunks it entered or left. [br]
## @param p_id The entity id to move [br]
## @param p_position The new position
func set_position(p_id: int, p_position: Vector2) -> void:
	_chunkEntityPosition[p_id] = p_position
	_apply_chunk_area(p_id, _compute_chunk_area(p_position, _chunkEntityRadius[p_id]))
	_apply_center_chunk(p_id, p_position)


## Resizes an entity and updates only the chunks it entered or left. [br]
## The center cannot move with the radius, so the center list stays untouched. [br]
## @param p_id The entity id to resize [br]
## @param p_radius The new effect radius
func set_radius(p_id: int, p_radius: float) -> void:
	_chunkEntityRadius[p_id] = p_radius
	_apply_chunk_area(p_id, _compute_chunk_area(_chunkEntityPosition[p_id], p_radius))


## Checks whether any team other than the asking one holds entities in a chunk. [br]
## @param p_chunkId The chunk to check [br]
## @param p_team The team that asks [br]
## @return true if an opponent stands there
func has_opponent_in_chunk(p_chunkId: int, p_team: int) -> bool:
	for l_team: int in TEAM_COUNT:
		if (l_team != p_team and _chunkCounts[l_team * CHUNK_COUNT + p_chunkId] > 0):
			return true

	return false


## Checks whether any team other than the asking one holds entities in a column. [br]
## @param p_columnIndex The column to check [br]
## @param p_team The team that asks [br]
## @return true if an opponent stands there
func has_opponent_in_column(p_columnIndex: int, p_team: int) -> bool:
	for l_team: int in TEAM_COUNT:
		if (l_team != p_team and _columnCounts[l_team * MAP_CHUNK_COLUMNS + p_columnIndex] > 0):
			return true

	return false


## Checks whether any team other than the asking one stands left of a column. [br]
## Reads the outermost occupied column of every team, so the map width never enters the cost. [br]
## @param p_columnIndex The column to look out from [br]
## @param p_team The team that asks [br]
## @return true if an opponent stands further left
func has_opponent_before_column(p_columnIndex: int, p_team: int) -> bool:
	for l_team: int in TEAM_COUNT:
		var l_minColumn: int = _teamMinColumn[l_team]

		if (l_team != p_team and l_minColumn != NO_COLUMN and l_minColumn < p_columnIndex):
			return true

	return false


## Checks whether any team other than the asking one stands right of a column. [br]
## @param p_columnIndex The column to look out from [br]
## @param p_team The team that asks [br]
## @return true if an opponent stands further right
func has_opponent_after_column(p_columnIndex: int, p_team: int) -> bool:
	for l_team: int in TEAM_COUNT:
		var l_maxColumn: int = _teamMaxColumn[l_team]

		if (l_team != p_team and l_maxColumn != NO_COLUMN and l_maxColumn > p_columnIndex):
			return true

	return false


## Checks whether a chunk holds at least one of the searched groups. [br]
## @param p_chunkId The chunk to check [br]
## @param p_team Team to check, a C_ChunkingServer.TEAM value [br]
## @param p_groupMask Bitmask of the searched groups [br]
## @return true if at least one searched group bit is present
func chunk_has_group(p_chunkId: int, p_team: int, p_groupMask: int) -> bool:
	return (_chunkGroups[p_team * CHUNK_COUNT + p_chunkId] & p_groupMask) != 0


## Checks whether a column holds at least one of the searched groups. [br]
## @param p_columnIndex The column to check [br]
## @param p_team Team to check, a C_ChunkingServer.TEAM value [br]
## @param p_groupMask Bitmask of the searched groups [br]
## @return true if at least one searched group bit is present
func column_has_group(p_columnIndex: int, p_team: int, p_groupMask: int) -> bool:
	return (_columnGroups[p_team * MAP_CHUNK_COLUMNS + p_columnIndex] & p_groupMask) != 0


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
	for l_team: int in TEAM_COUNT:
		if (l_team != p_team and (_chunkGroups[l_team * CHUNK_COUNT + p_chunkId] & p_groupMask) != 0):
			return true

	return false


## Checks whether any opposing team holds one of the searched groups in a column. [br]
## Skipping here skips every chunk of that column at once. [br]
## @param p_columnIndex The column to check [br]
## @param p_team The team that asks [br]
## @param p_groupMask Bitmask of the searched groups [br]
## @return true if the column is worth opening
func column_has_opponent_group(p_columnIndex: int, p_team: int, p_groupMask: int) -> bool:
	for l_team: int in TEAM_COUNT:
		if (l_team != p_team and (_columnGroups[l_team * MAP_CHUNK_COLUMNS + p_columnIndex] & p_groupMask) != 0):
			return true

	return false


## Checks whether any opposing team holds one of the searched groups anywhere. [br]
## Widest step of the filter; a search that fails here never touches a chunk. [br]
## @param p_team The team that asks [br]
## @param p_groupMask Bitmask of the searched groups [br]
## @return true if a search could find anything at all
func map_has_opponent_group(p_team: int, p_groupMask: int) -> bool:
	for l_team: int in TEAM_COUNT:
		if (l_team != p_team and (_mapGroups[l_team] & p_groupMask) != 0):
			return true

	return false


## Calculates the chunk rectangle an axis aligned box covers, clamped to the map. [br]
## Entities reach into every chunk their radius touches, so walking this area finds them all. [br]
## @param p_minCorner Upper left corner of the box [br]
## @param p_maxCorner Lower right corner of the box [br]
## @return The rectangle as (minColumn, minRow, maxColumn, maxRow)
func compute_chunk_area_from_bounds(p_minCorner: Vector2, p_maxCorner: Vector2) -> Vector4i:
	var l_lastColumn: int = MAP_CHUNK_COLUMNS - 1
	var l_lastRow: int = MAP_CHUNK_ROWS - 1

	return Vector4i(
		clampi(floori(p_minCorner.x / CHUNK_SIZE), 0, l_lastColumn),
		clampi(floori(p_minCorner.y / CHUNK_SIZE), 0, l_lastRow),
		clampi(floori(p_maxCorner.x / CHUNK_SIZE), 0, l_lastColumn),
		clampi(floori(p_maxCorner.y / CHUNK_SIZE), 0, l_lastRow))


## Lists every chunk inside a chunk rectangle. [br]
## Only for callers that need the list itself; walking an area is done with two loops. [br]
## @param p_area The rectangle as (minColumn, minRow, maxColumn, maxRow) [br]
## @return The chunk ids inside the rectangle, in ascending order
func collect_chunks_in_area(p_area: Vector4i) -> PackedInt32Array:
	var l_chunkIds: PackedInt32Array = PackedInt32Array()
	l_chunkIds.resize((p_area.z - p_area.x + 1) * (p_area.w - p_area.y + 1))

	var l_writeIndex: int = 0
	for l_row: int in range(p_area.y, p_area.w + 1):
		var l_rowOffset: int = l_row * MAP_CHUNK_COLUMNS

		for l_column: int in range(p_area.x, p_area.z + 1):
			l_chunkIds[l_writeIndex] = l_rowOffset + l_column
			l_writeIndex += 1

	return l_chunkIds

#endregion

extends A_CoreServer
## Autoload that moves and resizes entities inside the shared chunk index. [br]
## The index and its upkeep live on A_CoreServer, because registration and removal need them too.

#region LIFECYCLE_AND_METHODS

## Moves an entity and updates only the chunks it entered or left; a removed entity is ignored with a warning. [br]
## @param p_id The entity to move [br]
## @param p_position The new position
func set_position(p_id: int, p_position: Vector2) -> void:
	if (_reject_removed_id(p_id, "G_ChunkingServer.set_position")):
		return

	var l_radius: float = _entityRadius[p_id]
	var l_extent: Vector2 = Vector2(l_radius, l_radius)

	_entityPosition[p_id] = p_position
	_move_to_chunk_area(p_id, _compute_chunk_area(p_position - l_extent, p_position + l_extent))
	_update_center_chunk(p_id, p_position)


## Resizes an entity and updates only the chunks it entered or left; a removed entity is ignored with a warning. [br]
## The center cannot move with the radius, so the center chain stays untouched. [br]
## @param p_id The entity to resize [br]
## @param p_radius The new radius
func set_radius(p_id: int, p_radius: float) -> void:
	if (_reject_removed_id(p_id, "G_ChunkingServer.set_radius")):
		return

	var l_position: Vector2 = _entityPosition[p_id]
	var l_extent: Vector2 = Vector2(p_radius, p_radius)

	_entityRadius[p_id] = p_radius
	_move_to_chunk_area(p_id, _compute_chunk_area(l_position - l_extent, l_position + l_extent))

#endregion

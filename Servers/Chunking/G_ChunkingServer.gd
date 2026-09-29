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

	_entityPosition[p_id] = p_position
	_move_to_chunk_area(p_id, _compute_circle_chunk_area(p_position, _entityRadius[p_id]))
	_update_center_chunk(p_id, p_position)


## Resizes an entity and updates only the chunks it entered or left; a removed entity is ignored with a warning. [br]
## The center cannot move with the radius, so the center chain stays untouched. [br]
## @param p_id The entity to resize [br]
## @param p_radius The new radius
func set_radius(p_id: int, p_radius: float) -> void:
	if (_reject_removed_id(p_id, "G_ChunkingServer.set_radius")):
		return

	_entityRadius[p_id] = p_radius
	_move_to_chunk_area(p_id, _compute_circle_chunk_area(_entityPosition[p_id], p_radius))

#endregion

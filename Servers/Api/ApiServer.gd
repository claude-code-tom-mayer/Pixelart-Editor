extends RefCounted
class_name ApiServer
## The one path entities talk to; owns the chunk index and the servers built on it. [br]
## Registration happens here once and hands every server only the part it needs.

#region EXPORTS_AND_VARS

## Chunk index every server reads; owned here and never handed out to the outside.
var _chunking: ChunkingServer = null

## Resolves area hits against the shared chunk index.
var _hits: HitServer = null

## Picks and holds targets against the shared chunk index.
var _targeting: TargetingServer = null

## Every server that keeps a slot per entity id, in the order the lifecycle walks them. [br]
## Adding a server here is enough for it to see every removal.
var _servers: Array[A_EntityServer] = []

#endregion

#region LIFECYCLE_AND_METHODS

## Builds the chunk index and the servers that read it. [br]
## The servers only ever know the index, never this one, so nothing here keeps itself alive.
func _init() -> void:
	_chunking = ChunkingServer.new()
	_hits = HitServer.new(_chunking)
	_targeting = TargetingServer.new(_chunking)
	
	_servers.append(_hits)
	_servers.append(_targeting)


## Registers an entity across every server under the one id they all share. [br]
## @param p_position Start position of the entity [br]
## @param p_team Team of the entity, a C_ChunkingServer.TEAM value [br]
## @param p_module Module management of the entity [br]
## @param p_entityData Radius, groups and the setup of every server [br]
## @return The assigned entity id
func create_entity(p_position: Vector2, p_team: int, p_module: M_ModuleManager,
		p_entityData: R_EntityData) -> int:
	var l_id: int = _chunking.register_entity(p_position, p_entityData.radius, p_team, p_entityData.groups)
	
	_hits.register(l_id, p_module, p_entityData.hitProfile)
	_targeting.register(l_id, p_entityData.targetingData)
	
	return l_id


## Announces an entity for removal and lets every server react to it. [br]
## @param p_id The entity id to mark
func pre_unregister_entity(p_id: int) -> void:
	_chunking.pre_unregister_entity(p_id)
	
	for l_server: A_EntityServer in _servers:
		l_server.on_pre_unregister(p_id)


## Removes an entity from the index and from every server on top of it. [br]
## Does nothing for an id that is already removed. [br]
## @param p_id The entity id to remove
func unregister_entity(p_id: int) -> void:
	if (_chunking.is_unregistering(p_id)):
		return
	
	for l_server: A_EntityServer in _servers:
		l_server.on_unregister(p_id)
	
	_chunking.unregister_entity(p_id)


## Lets every server drop what it holds for the removed ids, then releases them.
func release_removed_ids() -> void:
	for l_id: int in _chunking.get_pending_free_ids():
		for l_server: A_EntityServer in _servers:
			l_server.release_entity(l_id)
	
	_chunking.release_removed_ids()


## Moves an entity and updates only the chunks it entered or left. [br]
## @param p_id The entity id to move [br]
## @param p_position The new position
func set_position(p_id: int, p_position: Vector2) -> void:
	_chunking.set_position(p_id, p_position)


## Resizes an entity and updates only the chunks it entered or left. [br]
## @param p_id The entity id to resize [br]
## @param p_radius The new effect radius
func set_radius(p_id: int, p_radius: float) -> void:
	_chunking.set_radius(p_id, p_radius)


## Hits every reachable target inside a circle, in no particular order. [br]
## Forwards to the hit server; see HitServer.hit_circle(). [br]
## @param p_emitterId The entity the hit comes from [br]
## @param p_origin Center of the circle [br]
## @param p_radius Radius of the circle [br]
## @param p_hitYBand Vertical extent of the hit as (bottom, top) [br]
## @param p_maxHits Upper number of hits, or C_HitServer.UNLIMITED_HITS [br]
## @param p_preferredId Target to check first, or C_HitServer.NO_PREFERRED_TARGET [br]
## @param p_hitData Payload handed to every entity that is hit [br]
## @return The impact positions as (x, y, height)
func hit_circle(p_emitterId: int, p_origin: Vector2, p_radius: float, p_hitYBand: Vector2,
		p_maxHits: int, p_preferredId: int, p_hitData: R_HitData) -> PackedVector3Array:
	return _hits.hit_circle(p_emitterId, p_origin, p_radius, p_hitYBand, p_maxHits, p_preferredId, p_hitData)


## Hits every reachable target inside a circle, from the center outwards. [br]
## Forwards to the hit server; see HitServer.hit_circle_ordered(). [br]
## @param p_emitterId The entity the hit comes from [br]
## @param p_origin Center of the circle [br]
## @param p_radius Radius of the circle [br]
## @param p_hitYBand Vertical extent of the hit as (bottom, top) [br]
## @param p_maxHits Upper number of hits, or C_HitServer.UNLIMITED_HITS [br]
## @param p_preferredId Target to check first, or C_HitServer.NO_PREFERRED_TARGET [br]
## @param p_hitData Payload handed to every entity that is hit [br]
## @return The impact positions as (x, y, height), nearest first
func hit_circle_ordered(p_emitterId: int, p_origin: Vector2, p_radius: float, p_hitYBand: Vector2,
		p_maxHits: int, p_preferredId: int, p_hitData: R_HitData) -> PackedVector3Array:
	return _hits.hit_circle_ordered(p_emitterId, p_origin, p_radius, p_hitYBand, p_maxHits, p_preferredId, p_hitData)


## Hits every reachable target inside a directional rect, in no particular order. [br]
## Forwards to the hit server; see HitServer.hit_directional_rect(). [br]
## @param p_emitterId The entity the hit comes from [br]
## @param p_origin Center of the back edge, where the rect starts [br]
## @param p_direction Direction the rect extends in [br]
## @param p_length Reach of the rect along its direction [br]
## @param p_width Full width of the rect across its direction [br]
## @param p_hitYBand Vertical extent of the hit as (bottom, top) [br]
## @param p_maxHits Upper number of hits, or C_HitServer.UNLIMITED_HITS [br]
## @param p_preferredId Target to check first, or C_HitServer.NO_PREFERRED_TARGET [br]
## @param p_hitData Payload handed to every entity that is hit [br]
## @return The impact positions as (x, y, height)
func hit_directional_rect(p_emitterId: int, p_origin: Vector2, p_direction: Vector2, p_length: float,
		p_width: float, p_hitYBand: Vector2, p_maxHits: int, p_preferredId: int,
		p_hitData: R_HitData) -> PackedVector3Array:
	return _hits.hit_directional_rect(p_emitterId, p_origin, p_direction, p_length, p_width,
		p_hitYBand, p_maxHits, p_preferredId, p_hitData)


## Hits every reachable target inside a directional rect, starting from one of its edges. [br]
## Forwards to the hit server; see HitServer.hit_directional_rect_ordered(). [br]
## @param p_emitterId The entity the hit comes from [br]
## @param p_origin Center of the back edge, where the rect starts [br]
## @param p_direction Direction the rect extends in [br]
## @param p_length Reach of the rect along its direction [br]
## @param p_width Full width of the rect across its direction [br]
## @param p_hitYBand Vertical extent of the hit as (bottom, top) [br]
## @param p_maxHits Upper number of hits, or C_HitServer.UNLIMITED_HITS [br]
## @param p_preferredId Target to check first, or C_HitServer.NO_PREFERRED_TARGET [br]
## @param p_hitData Payload handed to every entity that is hit [br]
## @param p_startEdge Edge the order starts at, as a C_HitServer.RECT_EDGE value [br]
## @return The impact positions as (x, y, height), ordered from that edge
func hit_directional_rect_ordered(p_emitterId: int, p_origin: Vector2, p_direction: Vector2, p_length: float,
		p_width: float, p_hitYBand: Vector2, p_maxHits: int, p_preferredId: int,
		p_hitData: R_HitData, p_startEdge: int) -> PackedVector3Array:
	return _hits.hit_directional_rect_ordered(p_emitterId, p_origin, p_direction, p_length, p_width,
		p_hitYBand, p_maxHits, p_preferredId, p_hitData, p_startEdge)


## Hits every reachable target inside a cake slice, in no particular order. [br]
## Forwards to the hit server; see HitServer.hit_cake_slice(). [br]
## @param p_emitterId The entity the hit comes from [br]
## @param p_origin Tip of the slice [br]
## @param p_direction Direction the slice is centered on [br]
## @param p_radius Reach of the slice [br]
## @param p_angle Full opening angle in radians [br]
## @param p_hitYBand Vertical extent of the hit as (bottom, top) [br]
## @param p_maxHits Upper number of hits, or C_HitServer.UNLIMITED_HITS [br]
## @param p_preferredId Target to check first, or C_HitServer.NO_PREFERRED_TARGET [br]
## @param p_hitData Payload handed to every entity that is hit [br]
## @return The impact positions as (x, y, height)
func hit_cake_slice(p_emitterId: int, p_origin: Vector2, p_direction: Vector2, p_radius: float,
		p_angle: float, p_hitYBand: Vector2, p_maxHits: int, p_preferredId: int,
		p_hitData: R_HitData) -> PackedVector3Array:
	return _hits.hit_cake_slice(p_emitterId, p_origin, p_direction, p_radius, p_angle,
		p_hitYBand, p_maxHits, p_preferredId, p_hitData)


## Hits every reachable target inside a cake slice, sweeping from its right edge to its left. [br]
## Forwards to the hit server; see HitServer.hit_cake_slice_ordered(). [br]
## @param p_emitterId The entity the hit comes from [br]
## @param p_origin Tip of the slice [br]
## @param p_direction Direction the slice is centered on [br]
## @param p_radius Reach of the slice [br]
## @param p_angle Full opening angle in radians [br]
## @param p_hitYBand Vertical extent of the hit as (bottom, top) [br]
## @param p_maxHits Upper number of hits, or C_HitServer.UNLIMITED_HITS [br]
## @param p_preferredId Target to check first, or C_HitServer.NO_PREFERRED_TARGET [br]
## @param p_hitData Payload handed to every entity that is hit [br]
## @param p_isReversed Sweeps from the left edge to the right instead [br]
## @return The impact positions as (x, y, height), in sweep order
func hit_cake_slice_ordered(p_emitterId: int, p_origin: Vector2, p_direction: Vector2, p_radius: float,
		p_angle: float, p_hitYBand: Vector2, p_maxHits: int, p_preferredId: int,
		p_hitData: R_HitData, p_isReversed: bool) -> PackedVector3Array:
	return _hits.hit_cake_slice_ordered(p_emitterId, p_origin, p_direction, p_radius, p_angle,
		p_hitYBand, p_maxHits, p_preferredId, p_hitData, p_isReversed)


## Advances the state of one entity; cheap enough to run every tick. [br]
## @param p_id The entity to advance [br]
## @return Its new C_TargetingServer.STATE
func update_entity(p_id: int) -> int:
	return _targeting.update_entity(p_id)


## Scans the search area of an entity and gives it the best scoring target. [br]
## @param p_id The entity that searches [br]
## @return The target it got, or C_TargetingServer.NO_TARGET
func search_target(p_id: int) -> int:
	return _targeting.search_target(p_id)


## Returns where an entity should move this tick. [br]
## @param p_id The entity to move [br]
## @return The position the movement should head for
func get_target_position(p_id: int) -> Vector2:
	return _targeting.get_target_position(p_id)


## Returns the current state of an entity. [br]
## @param p_id The entity to read [br]
## @return Its C_TargetingServer.STATE
func get_state(p_id: int) -> int:
	return _targeting.get_state(p_id)


## Returns the target of an entity. [br]
## @param p_id The entity to read [br]
## @return Its target, or C_TargetingServer.NO_TARGET
func get_target(p_id: int) -> int:
	return _targeting.get_target(p_id)


## Returns everyone targeting an entity as a snapshot of the moment it is asked. [br]
## @param p_id The entity to read [br]
## @return The ids currently targeting it
func get_targeters(p_id: int) -> PackedInt32Array:
	return _targeting.get_targeters(p_id)


## Makes every entity that targets this one drop it and look for something else. [br]
## @param p_id The entity that is no longer worth targeting
func drop_targeters(p_id: int) -> void:
	_targeting.drop_targeters(p_id)


## Hides an entity from searchers, or reveals it again. [br]
## @param p_id The entity to change [br]
## @param p_isInvisible Whether it becomes invisible
func set_invisible(p_id: int, p_isInvisible: bool) -> void:
	_targeting.set_invisible(p_id, p_isInvisible)


## Sets whether an entity can see invisible enemies. [br]
## @param p_id The entity to change [br]
## @param p_isEnabled Whether it sees them
func set_targets_invisible(p_id: int, p_isEnabled: bool) -> void:
	_targeting.set_targets_invisible(p_id, p_isEnabled)


## Sets whether an entity is a focus target other entities prefer. [br]
## @param p_id The entity to change [br]
## @param p_isEnabled Whether it carries focus
func set_focused(p_id: int, p_isEnabled: bool) -> void:
	_targeting.set_focused(p_id, p_isEnabled)


## Sets whether an entity scores candidates without the focus bonus. [br]
## @param p_id The entity to change [br]
## @param p_isEnabled Whether it ignores focus
func set_ignores_focus(p_id: int, p_isEnabled: bool) -> void:
	_targeting.set_ignores_focus(p_id, p_isEnabled)


## Sets how far a search of this entity reaches. [br]
## @param p_id The entity to change [br]
## @param p_searchChunks Reach in chunks per direction
func set_search_chunks(p_id: int, p_searchChunks: int) -> void:
	_targeting.set_search_chunks(p_id, p_searchChunks)


## Sets how close a targeter has to come before the entity flees. [br]
## @param p_id The entity to change [br]
## @param p_fleeChunks Threat distance in chunks
func set_flee_chunks(p_id: int, p_fleeChunks: int) -> void:
	_targeting.set_flee_chunks(p_id, p_fleeChunks)


## Sets the real distance at which the entity enters combat. [br]
## @param p_id The entity to change [br]
## @param p_hitRange The distance to the silhouette of the target
func set_hit_range(p_id: int, p_hitRange: float) -> void:
	_targeting.set_hit_range(p_id, p_hitRange)


## Sets the groups the entity goes after before it considers the normal ones. [br]
## @param p_id The entity to change [br]
## @param p_priorityTargetedGroups Bitmask of the preferred groups
func set_priority_targeted_groups(p_id: int, p_priorityTargetedGroups: int) -> void:
	_targeting.set_priority_targeted_groups(p_id, p_priorityTargetedGroups)


## Sets the vertical extent an entity occupies. [br]
## @param p_id The entity to change [br]
## @param p_yBand The extent as (bottom, top)
func set_y_band(p_id: int, p_yBand: Vector2) -> void:
	_hits.set_y_band(p_id, p_yBand)


## Sets the hit groups an entity can be harmed by. [br]
## @param p_id The entity to change [br]
## @param p_hurtGroups Bitmask of the hit groups that may connect with it
func set_hurt_groups(p_id: int, p_hurtGroups: int) -> void:
	_hits.set_hurt_groups(p_id, p_hurtGroups)


## Sets the hit groups the hits of an entity carry. [br]
## @param p_id The entity to change [br]
## @param p_hitGroups Bitmask matched against the hurt groups of every target
func set_hit_groups(p_id: int, p_hitGroups: int) -> void:
	_hits.set_hit_groups(p_id, p_hitGroups)


## Sets the hurt groups that end a hit of this entity on the target they match. [br]
## @param p_id The entity to change [br]
## @param p_stopGroups Bitmask of the hurt groups that block its hits
func set_stop_groups(p_id: int, p_stopGroups: int) -> void:
	_hits.set_stop_groups(p_id, p_stopGroups)


## Sets the radius profile of an entity; null gives it a constant radius again. [br]
## @param p_id The entity to change [br]
## @param p_curve The profile to sample, or null
func set_radius_curve(p_id: int, p_curve: Curve) -> void:
	_hits.set_radius_curve(p_id, p_curve)

#endregion

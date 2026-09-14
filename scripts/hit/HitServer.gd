extends ChunkingServer
## Resolves area hits through the chunk index, so only entities near the shape are tested. [br]
## Hit and hurt groups decide whether a hit connects at all, stop groups end it at the first blocker.
class_name HitServer

#region PRIVATE_VARIABLES

## Vertical extent per entity as (bottom, top); the third axis next to the 2D position.
var _entityYBand: PackedVector2Array = PackedVector2Array()

## Bitmask of the hit groups an entity can be harmed by.
var _entityHurtGroups: PackedInt32Array = PackedInt32Array()

## Bitmask of the hit groups the hits of an entity carry.
var _entityHitGroups: PackedInt32Array = PackedInt32Array()

## Bitmask of the hurt groups that end a hit of this entity on the target they match.
var _entityStopGroups: PackedInt32Array = PackedInt32Array()

## Curve slot per entity, or C_HitServer.NO_CURVE while its radius is constant over the height.
var _entityCurveIndex: PackedInt32Array = PackedInt32Array()

## Radius profile per curve slot; x is the percent along the y band, y the percent of the radius.
var _radiiCurves: Array[Curve] = []

## Curve slots of removed entities, ready to be handed out again.
var _freeCurveIndices: PackedInt32Array = PackedInt32Array()

#endregion

#region LIFECYCLE

## Takes an id from the chunking server and clears the hit data of that slot. [br]
## Without the reset a recycled id would inherit the groups and curve of its predecessor. [br]
## @return The id the next entity is stored under
func _acquire_id() -> int:
	var l_id: int = super()
	
	if (l_id == _entityYBand.size()):
		_entityYBand.append(Vector2.ZERO)
		_entityHurtGroups.append(0)
		_entityHitGroups.append(0)
		_entityStopGroups.append(0)
		_entityCurveIndex.append(C_HitServer.NO_CURVE)
		return l_id
	
	_entityYBand[l_id] = Vector2.ZERO
	_entityHurtGroups[l_id] = 0
	_entityHitGroups[l_id] = 0
	_entityStopGroups[l_id] = 0
	_release_curve(l_id)
	
	return l_id

#endregion

#region PUBLIC_METHODS

## Sets the vertical extent an entity occupies. [br]
## @param p_id The entity to change [br]
## @param p_yBand The extent as (bottom, top)
func set_y_band(p_id: int, p_yBand: Vector2) -> void:
	_entityYBand[p_id] = p_yBand


## Sets the hit groups an entity can be harmed by. [br]
## @param p_id The entity to change [br]
## @param p_hurtGroups Bitmask of the hit groups that may connect with it
func set_hurt_groups(p_id: int, p_hurtGroups: int) -> void:
	_entityHurtGroups[p_id] = p_hurtGroups


## Sets the hit groups the hits of an entity carry. [br]
## @param p_id The entity to change [br]
## @param p_hitGroups Bitmask matched against the hurt groups of every target
func set_hit_groups(p_id: int, p_hitGroups: int) -> void:
	_entityHitGroups[p_id] = p_hitGroups


## Sets the hurt groups that end a hit of this entity on the target they match. [br]
## @param p_id The entity to change [br]
## @param p_stopGroups Bitmask of the hurt groups that block its hits
func set_stop_groups(p_id: int, p_stopGroups: int) -> void:
	_entityStopGroups[p_id] = p_stopGroups


## Sets the radius profile of an entity; null gives it a constant radius again. [br]
## The curve maps the percent along the y band to the percent of the radius, both from 0 to 100. [br]
## @param p_id The entity to change [br]
## @param p_curve The profile to sample, or null
func set_radius_curve(p_id: int, p_curve: Curve) -> void:
	if (p_curve == null):
		_release_curve(p_id)
		return
	
	p_curve.bake()
	
	var l_curveIndex: int = _entityCurveIndex[p_id]
	if (l_curveIndex != C_HitServer.NO_CURVE):
		_radiiCurves[l_curveIndex] = p_curve
		return
	
	var l_lastFreeIndex: int = _freeCurveIndices.size() - 1
	if (l_lastFreeIndex >= 0):
		l_curveIndex = _freeCurveIndices[l_lastFreeIndex]
		_freeCurveIndices.remove_at(l_lastFreeIndex)
		_radiiCurves[l_curveIndex] = p_curve
	else:
		l_curveIndex = _radiiCurves.size()
		_radiiCurves.append(p_curve)
	
	_entityCurveIndex[p_id] = l_curveIndex

#endregion

#region PUBLIC_HITS

## Hits every reachable target inside a circle, in no particular order. [br]
## Stop groups need an order to be meaningful and are therefore not evaluated here. [br]
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
	return _resolve_circle(p_emitterId, p_origin, p_radius, p_hitYBand, p_maxHits, p_preferredId, p_hitData, false)


## Hits every reachable target inside a circle, from the center outwards. [br]
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
	return _resolve_circle(p_emitterId, p_origin, p_radius, p_hitYBand, p_maxHits, p_preferredId, p_hitData, true)


## Hits every reachable target inside a directional rect, in no particular order. [br]
## Stop groups need an order to be meaningful and are therefore not evaluated here. [br]
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
	return _resolve_directional_rect(p_emitterId, p_origin, p_direction, p_length, p_width, p_hitYBand,
		p_maxHits, p_preferredId, p_hitData, false, C_HitServer.RECT_EDGE.BACK)


## Hits every reachable target inside a directional rect, starting from one of its edges. [br]
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
	return _resolve_directional_rect(p_emitterId, p_origin, p_direction, p_length, p_width, p_hitYBand,
		p_maxHits, p_preferredId, p_hitData, true, p_startEdge)


## Hits every reachable target inside a cake slice, in no particular order. [br]
## Stop groups need an order to be meaningful and are therefore not evaluated here. [br]
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
	return _resolve_cake_slice(p_emitterId, p_origin, p_direction, p_radius, p_angle, p_hitYBand,
		p_maxHits, p_preferredId, p_hitData, false, false)


## Hits every reachable target inside a cake slice, sweeping from its right edge to its left. [br]
## @param p_emitterId The entity the hit comes from [br]
## @param p_origin Tip of the slice [br]
## @param p_direction Direction the slice is centered on [br]
## @param p_radius Reach of the slice [br]
## @param p_angle Full opening angle in radians [br]
## @param p_hitYBand Vertical extent of the hit as (bottom, top) [br]
## @param p_maxHits Upper number of hits, or C_HitServer.UNLIMITED_HITS [br]
## @param p_preferredId Target to check first, or C_HitServer.NO_PREFERRED_TARGET [br]
## @param p_hitData Payload handed to every entity that is hit [br]
## @param p_reversed Sweeps from the left edge to the right instead [br]
## @return The impact positions as (x, y, height), in sweep order
func hit_cake_slice_ordered(p_emitterId: int, p_origin: Vector2, p_direction: Vector2, p_radius: float,
		p_angle: float, p_hitYBand: Vector2, p_maxHits: int, p_preferredId: int,
		p_hitData: R_HitData, p_reversed: bool) -> PackedVector3Array:
	return _resolve_cake_slice(p_emitterId, p_origin, p_direction, p_radius, p_angle, p_hitYBand,
		p_maxHits, p_preferredId, p_hitData, true, p_reversed)

#endregion

#region PRIVATE_SHAPES

## Runs a circle hit against the preferred target first and the chunks of its area second. [br]
## @return The impact positions as (x, y, height)
func _resolve_circle(p_emitterId: int, p_origin: Vector2, p_radius: float, p_hitYBand: Vector2,
		p_maxHits: int, p_preferredId: int, p_hitData: R_HitData, p_ordered: bool) -> PackedVector3Array:
	var l_preferred: PackedInt32Array = _get_preferred_candidates(p_emitterId, p_preferredId, p_maxHits, p_hitYBand)
	var l_result: PackedVector3Array = _test_circle(l_preferred, p_emitterId, p_origin, p_radius,
		p_hitYBand, p_maxHits, p_hitData, p_ordered)
	
	if (not l_result.is_empty()):
		return l_result
	
	var l_extent: Vector2 = Vector2(p_radius, p_radius)
	var l_candidateIds: PackedInt32Array = _gather_chunk_candidates(p_emitterId,
		p_origin - l_extent, p_origin + l_extent, p_hitYBand)
	
	return _test_circle(l_candidateIds, p_emitterId, p_origin, p_radius, p_hitYBand, p_maxHits, p_hitData, p_ordered)


## Keeps the candidates whose silhouette reaches into the circle. [br]
## @return The impact positions as (x, y, height)
func _test_circle(p_candidateIds: PackedInt32Array, p_emitterId: int, p_origin: Vector2, p_radius: float,
		p_hitYBand: Vector2, p_maxHits: int, p_hitData: R_HitData, p_ordered: bool) -> PackedVector3Array:
	var l_hitIds: PackedInt32Array = PackedInt32Array()
	var l_keys: PackedFloat32Array = PackedFloat32Array()
	var l_positions: PackedVector3Array = PackedVector3Array()
	
	for l_id: int in p_candidateIds:
		var l_height: float = _get_sample_height(l_id, p_hitYBand)
		var l_radius: float = _get_effective_radius(l_id, l_height)
		var l_distanceSquared: float = _entityPosition[l_id].distance_squared_to(p_origin)
		var l_reach: float = p_radius + l_radius
		
		if (l_distanceSquared > l_reach * l_reach):
			continue
		
		l_hitIds.append(l_id)
		l_keys.append(l_distanceSquared)
		l_positions.append(_get_impact_position(l_id, l_radius, l_height, p_origin))
	
	return _apply_hits(p_emitterId, l_hitIds, l_keys, l_positions, p_maxHits, p_hitData, p_ordered)


## Runs a rect hit against the preferred target first and the chunks of its area second. [br]
## @return The impact positions as (x, y, height)
func _resolve_directional_rect(p_emitterId: int, p_origin: Vector2, p_direction: Vector2, p_length: float,
		p_width: float, p_hitYBand: Vector2, p_maxHits: int, p_preferredId: int, p_hitData: R_HitData,
		p_ordered: bool, p_startEdge: int) -> PackedVector3Array:
	var l_preferred: PackedInt32Array = _get_preferred_candidates(p_emitterId, p_preferredId, p_maxHits, p_hitYBand)
	var l_result: PackedVector3Array = _test_directional_rect(l_preferred, p_emitterId, p_origin, p_direction,
		p_length, p_width, p_hitYBand, p_maxHits, p_hitData, p_ordered, p_startEdge)
	
	if (not l_result.is_empty()):
		return l_result
	
	var l_forward: Vector2 = p_direction.normalized()
	var l_sideStep: Vector2 = l_forward.orthogonal() * p_width * 0.5
	var l_cornerA: Vector2 = p_origin + l_sideStep
	var l_cornerB: Vector2 = p_origin - l_sideStep
	var l_cornerC: Vector2 = l_cornerA + l_forward * p_length
	var l_cornerD: Vector2 = l_cornerB + l_forward * p_length
	
	var l_candidateIds: PackedInt32Array = _gather_chunk_candidates(p_emitterId,
		l_cornerA.min(l_cornerB).min(l_cornerC).min(l_cornerD),
		l_cornerA.max(l_cornerB).max(l_cornerC).max(l_cornerD),
		p_hitYBand)
	
	return _test_directional_rect(l_candidateIds, p_emitterId, p_origin, p_direction, p_length, p_width,
		p_hitYBand, p_maxHits, p_hitData, p_ordered, p_startEdge)


## Keeps the candidates whose silhouette reaches into the rect. [br]
## @return The impact positions as (x, y, height)
func _test_directional_rect(p_candidateIds: PackedInt32Array, p_emitterId: int, p_origin: Vector2,
		p_direction: Vector2, p_length: float, p_width: float, p_hitYBand: Vector2, p_maxHits: int,
		p_hitData: R_HitData, p_ordered: bool, p_startEdge: int) -> PackedVector3Array:
	var l_hitIds: PackedInt32Array = PackedInt32Array()
	var l_keys: PackedFloat32Array = PackedFloat32Array()
	var l_positions: PackedVector3Array = PackedVector3Array()
	var l_forward: Vector2 = p_direction.normalized()
	var l_side: Vector2 = -l_forward.orthogonal()
	var l_halfWidth: float = p_width * 0.5
	
	for l_id: int in p_candidateIds:
		var l_height: float = _get_sample_height(l_id, p_hitYBand)
		var l_radius: float = _get_effective_radius(l_id, l_height)
		var l_toTarget: Vector2 = _entityPosition[l_id] - p_origin
		var l_along: float = l_toTarget.dot(l_forward)
		var l_across: float = l_toTarget.dot(l_side)
		var l_gapAlong: float = l_along - clampf(l_along, 0.0, p_length)
		var l_gapAcross: float = l_across - clampf(l_across, -l_halfWidth, l_halfWidth)
		
		if (l_gapAlong * l_gapAlong + l_gapAcross * l_gapAcross > l_radius * l_radius):
			continue
		
		l_hitIds.append(l_id)
		l_keys.append(_get_rect_key(p_startEdge, l_along, l_across, p_length))
		l_positions.append(_get_impact_position(l_id, l_radius, l_height, p_origin))
	
	return _apply_hits(p_emitterId, l_hitIds, l_keys, l_positions, p_maxHits, p_hitData, p_ordered)


## Runs a slice hit against the preferred target first and the chunks of its area second. [br]
## @return The impact positions as (x, y, height)
func _resolve_cake_slice(p_emitterId: int, p_origin: Vector2, p_direction: Vector2, p_radius: float,
		p_angle: float, p_hitYBand: Vector2, p_maxHits: int, p_preferredId: int, p_hitData: R_HitData,
		p_ordered: bool, p_reversed: bool) -> PackedVector3Array:
	var l_preferred: PackedInt32Array = _get_preferred_candidates(p_emitterId, p_preferredId, p_maxHits, p_hitYBand)
	var l_result: PackedVector3Array = _test_cake_slice(l_preferred, p_emitterId, p_origin, p_direction,
		p_radius, p_angle, p_hitYBand, p_maxHits, p_hitData, p_ordered, p_reversed)
	
	if (not l_result.is_empty()):
		return l_result
	
	var l_extent: Vector2 = Vector2(p_radius, p_radius)
	var l_candidateIds: PackedInt32Array = _gather_chunk_candidates(p_emitterId,
		p_origin - l_extent, p_origin + l_extent, p_hitYBand)
	
	return _test_cake_slice(l_candidateIds, p_emitterId, p_origin, p_direction, p_radius, p_angle,
		p_hitYBand, p_maxHits, p_hitData, p_ordered, p_reversed)


## Keeps the candidates whose silhouette reaches into the slice. [br]
## @return The impact positions as (x, y, height)
func _test_cake_slice(p_candidateIds: PackedInt32Array, p_emitterId: int, p_origin: Vector2,
		p_direction: Vector2, p_radius: float, p_angle: float, p_hitYBand: Vector2, p_maxHits: int,
		p_hitData: R_HitData, p_ordered: bool, p_reversed: bool) -> PackedVector3Array:
	var l_hitIds: PackedInt32Array = PackedInt32Array()
	var l_keys: PackedFloat32Array = PackedFloat32Array()
	var l_positions: PackedVector3Array = PackedVector3Array()
	var l_forward: Vector2 = p_direction.normalized()
	var l_halfAngle: float = p_angle * 0.5
	var l_rightEdge: Vector2 = p_origin + l_forward.rotated(l_halfAngle) * p_radius
	var l_leftEdge: Vector2 = p_origin + l_forward.rotated(-l_halfAngle) * p_radius
	
	for l_id: int in p_candidateIds:
		var l_height: float = _get_sample_height(l_id, p_hitYBand)
		var l_radius: float = _get_effective_radius(l_id, l_height)
		var l_position: Vector2 = _entityPosition[l_id]
		var l_toTarget: Vector2 = l_position - p_origin
		var l_reach: float = p_radius + l_radius
		
		if (l_toTarget.length_squared() > l_reach * l_reach):
			continue
		
		var l_signedAngle: float = l_forward.angle_to(l_toTarget)
		if (not _touches_slice(l_position, l_radius, l_signedAngle, l_halfAngle, p_origin, l_rightEdge, l_leftEdge)):
			continue
		
		l_hitIds.append(l_id)
		l_keys.append(l_signedAngle if p_reversed else -l_signedAngle)
		l_positions.append(_get_impact_position(l_id, l_radius, l_height, p_origin))
	
	return _apply_hits(p_emitterId, l_hitIds, l_keys, l_positions, p_maxHits, p_hitData, p_ordered)

#endregion

#region PRIVATE_METHODS

## Gives the curve slot of an entity back for reuse, if it holds one. [br]
## @param p_id The entity whose profile is dropped
func _release_curve(p_id: int) -> void:
	var l_curveIndex: int = _entityCurveIndex[p_id]
	
	if (l_curveIndex == C_HitServer.NO_CURVE):
		return
	
	_radiiCurves[l_curveIndex] = null
	_freeCurveIndices.append(l_curveIndex)
	_entityCurveIndex[p_id] = C_HitServer.NO_CURVE


## Collects every entity of another team that a hit in this area could reach. [br]
## Skips whole chunks that hold no opponent and lists an entity spanning several chunks once. [br]
## @param p_emitterId The entity the hit comes from [br]
## @param p_minCorner Upper left corner of the shape bounds [br]
## @param p_maxCorner Lower right corner of the shape bounds [br]
## @param p_hitYBand Vertical extent of the hit [br]
## @return The ids worth testing against the shape
func _gather_chunk_candidates(p_emitterId: int, p_minCorner: Vector2, p_maxCorner: Vector2,
		p_hitYBand: Vector2) -> PackedInt32Array:
	var l_candidateIds: PackedInt32Array = PackedInt32Array()
	var l_area: Vector4i = _compute_chunk_area_from_bounds(p_minCorner, p_maxCorner)
	var l_emitterTeam: int = _entityTeam[p_emitterId]
	
	for l_chunkId: int in _collect_chunks_in_area(l_area):
		if (_get_opponent_count_in_chunk(l_chunkId, l_emitterTeam) == 0):
			continue
		
		for l_id: int in _entitiesInChunk[l_chunkId]:
			if (not _can_be_hit(p_emitterId, l_id, p_hitYBand)):
				continue
			
			if (_entityChunkIds[l_id].size() > 1 and l_candidateIds.has(l_id)):
				continue
			
			l_candidateIds.append(l_id)
	
	return l_candidateIds


## Returns the preferred target as the only candidate, or nothing when it cannot be used. [br]
## Warns and falls back to a normal hit when a preference is passed with more than one allowed hit. [br]
## @param p_emitterId The entity the hit comes from [br]
## @param p_preferredId The target to check first [br]
## @param p_maxHits Upper number of hits of this hit [br]
## @param p_hitYBand Vertical extent of the hit [br]
## @return The preferred id as a single candidate, or an empty list
func _get_preferred_candidates(p_emitterId: int, p_preferredId: int, p_maxHits: int,
		p_hitYBand: Vector2) -> PackedInt32Array:
	if (p_preferredId == C_HitServer.NO_PREFERRED_TARGET):
		return PackedInt32Array()
	
	if (p_maxHits != 1):
		push_warning("HitServer: a preferred target is only used when p_maxHits is 1, ignoring it.")
		return PackedInt32Array()
	
	if (not _can_be_hit(p_emitterId, p_preferredId, p_hitYBand)):
		return PackedInt32Array()
	
	return PackedInt32Array([p_preferredId])


## Checks everything about a target that does not depend on the hit shape. [br]
## @param p_emitterId The entity the hit comes from [br]
## @param p_targetId The entity to check [br]
## @param p_hitYBand Vertical extent of the hit [br]
## @return true if only the geometry is left to decide
func _can_be_hit(p_emitterId: int, p_targetId: int, p_hitYBand: Vector2) -> bool:
	if (_entityTeam[p_targetId] == _entityTeam[p_emitterId]):
		return false
	
	if (_entityPreUnregistered[p_targetId] == 1 or _entityUnregistering[p_targetId] == 1):
		return false
	
	if ((_entityHitGroups[p_emitterId] & _entityHurtGroups[p_targetId]) == 0):
		return false
	
	var l_band: Vector2 = _entityYBand[p_targetId]
	return p_hitYBand.x <= l_band.y and p_hitYBand.y >= l_band.x


## Counts the entities of every other team inside a chunk. [br]
## @param p_chunkId The chunk to look at [br]
## @param p_team The team the hit comes from [br]
## @return How many entities there could be hit
func _get_opponent_count_in_chunk(p_chunkId: int, p_team: int) -> int:
	var l_count: int = 0
	
	for l_team: int in C_ChunkingServer.TEAM_COUNT:
		if (l_team != p_team):
			l_count += _chunkCounts[_get_team_chunk_index(l_team, p_chunkId)]
	
	return l_count


## Picks the height a hit is measured at: the middle of the hit band, held inside the target. [br]
## @param p_id The entity that is hit [br]
## @param p_hitYBand Vertical extent of the hit [br]
## @return The height on the target the hit lands at
func _get_sample_height(p_id: int, p_hitYBand: Vector2) -> float:
	var l_band: Vector2 = _entityYBand[p_id]
	return clampf((p_hitYBand.x + p_hitYBand.y) * 0.5, l_band.x, l_band.y)


## Reads the radius a target offers at one height from its profile. [br]
## Entities without a profile keep their full radius over the whole height. [br]
## @param p_id The entity that is hit [br]
## @param p_sampleHeight The height the hit lands at [br]
## @return The radius that counts for this hit
func _get_effective_radius(p_id: int, p_sampleHeight: float) -> float:
	var l_radius: float = _entityRadius[p_id]
	var l_curveIndex: int = _entityCurveIndex[p_id]
	
	if (l_curveIndex == C_HitServer.NO_CURVE):
		return l_radius
	
	var l_band: Vector2 = _entityYBand[p_id]
	var l_height: float = l_band.y - l_band.x
	
	if (l_height <= 0.0):
		return l_radius
	
	var l_percent: float = (p_sampleHeight - l_band.x) / l_height * C_HitServer.CURVE_PERCENT_MAX
	return l_radius * _radiiCurves[l_curveIndex].sample_baked(l_percent) / C_HitServer.CURVE_PERCENT_MAX


## Places the impact on the silhouette of the target, facing the origin of the hit. [br]
## @param p_id The entity that is hit [br]
## @param p_radius Its radius at the hit height [br]
## @param p_height The height the hit lands at [br]
## @param p_origin Where the hit comes from [br]
## @return The impact as (x, y, height)
func _get_impact_position(p_id: int, p_radius: float, p_height: float, p_origin: Vector2) -> Vector3:
	var l_position: Vector2 = _entityPosition[p_id]
	var l_toOrigin: Vector2 = p_origin - l_position
	var l_distance: float = l_toOrigin.length()
	
	if (l_distance == 0.0):
		return Vector3(l_position.x, l_position.y, p_height)
	
	var l_impact: Vector2 = l_position + l_toOrigin / l_distance * minf(p_radius, l_distance)
	return Vector3(l_impact.x, l_impact.y, p_height)


## Checks a target against the opening angle and the two straight edges of a slice. [br]
## @param p_position Center of the target [br]
## @param p_radius Its radius at the hit height [br]
## @param p_signedAngle Its angle against the slice direction [br]
## @param p_halfAngle Half the opening angle of the slice [br]
## @param p_origin Tip of the slice [br]
## @param p_rightEdge End of the right edge [br]
## @param p_leftEdge End of the left edge [br]
## @return true if the target reaches into the slice
func _touches_slice(p_position: Vector2, p_radius: float, p_signedAngle: float, p_halfAngle: float,
		p_origin: Vector2, p_rightEdge: Vector2, p_leftEdge: Vector2) -> bool:
	if (absf(p_signedAngle) <= p_halfAngle):
		return true
	
	var l_radiusSquared: float = p_radius * p_radius
	if (p_position.distance_squared_to(p_origin) <= l_radiusSquared):
		return true
	
	if (p_position.distance_squared_to(Geometry2D.get_closest_point_to_segment(p_position, p_origin, p_rightEdge)) <= l_radiusSquared):
		return true
	
	return p_position.distance_squared_to(Geometry2D.get_closest_point_to_segment(p_position, p_origin, p_leftEdge)) <= l_radiusSquared


## Turns the position inside a rect into the sort key of the chosen start edge. [br]
## @param p_startEdge The edge the order starts at [br]
## @param p_along Distance along the direction of the rect [br]
## @param p_across Distance across it, positive towards the right of the direction [br]
## @param p_length Reach of the rect [br]
## @return The key to sort ascending by
func _get_rect_key(p_startEdge: int, p_along: float, p_across: float, p_length: float) -> float:
	match p_startEdge:
		C_HitServer.RECT_EDGE.FRONT:
			return p_length - p_along
		C_HitServer.RECT_EDGE.RIGHT:
			return -p_across
		C_HitServer.RECT_EDGE.LEFT:
			return p_across
	
	return p_along


## Orders the hits, cuts them at the stop group and the hit limit, and hands them to their modules. [br]
## Dispatching after the walk keeps a module free to remove its entity while it takes the hit. [br]
## @param p_emitterId The entity the hit comes from [br]
## @param p_hitIds The targets the shape accepted [br]
## @param p_keys Their sort keys [br]
## @param p_positions Their impact positions [br]
## @param p_maxHits Upper number of hits, or C_HitServer.UNLIMITED_HITS [br]
## @param p_hitData Payload handed to every entity that is hit [br]
## @param p_ordered Whether the keys decide the order and the stop group applies [br]
## @return The impact positions of the hits that landed
func _apply_hits(p_emitterId: int, p_hitIds: PackedInt32Array, p_keys: PackedFloat32Array,
		p_positions: PackedVector3Array, p_maxHits: int, p_hitData: R_HitData,
		p_ordered: bool) -> PackedVector3Array:
	var l_order: PackedInt32Array = _get_hit_order(p_keys) if p_ordered else _get_gathered_order(p_hitIds.size())
	var l_stopGroups: int = _entityStopGroups[p_emitterId]
	var l_appliedIds: PackedInt32Array = PackedInt32Array()
	var l_result: PackedVector3Array = PackedVector3Array()
	
	for l_index: int in l_order:
		if (p_maxHits != C_HitServer.UNLIMITED_HITS and l_result.size() >= p_maxHits):
			break
		
		l_appliedIds.append(p_hitIds[l_index])
		l_result.append(p_positions[l_index])
		
		if (p_ordered and (l_stopGroups & _entityHurtGroups[p_hitIds[l_index]]) != 0):
			break
	
	for l_id: int in l_appliedIds:
		var l_module: M_ModuleManager = _entityModules[l_id]
		
		if (l_module != null):
			l_module.hit(p_hitData)
	
	return l_result


## Sorts the hits ascending by key without moving the hit data itself. [br]
## @param p_keys The key of every hit [br]
## @return The indices of the hits in the order they have to be applied
func _get_hit_order(p_keys: PackedFloat32Array) -> PackedInt32Array:
	var l_order: PackedInt32Array = PackedInt32Array()
	
	for l_index: int in p_keys.size():
		var l_insertAt: int = l_order.size()
		
		while (l_insertAt > 0 and p_keys[l_order[l_insertAt - 1]] > p_keys[l_index]):
			l_insertAt -= 1
		
		l_order.insert(l_insertAt, l_index)
	
	return l_order


## Builds the order of an unordered hit: the sequence the candidates were gathered in. [br]
## @param p_size How many hits were gathered [br]
## @return The indices from 0 upwards
func _get_gathered_order(p_size: int) -> PackedInt32Array:
	var l_order: PackedInt32Array = PackedInt32Array()
	l_order.resize(p_size)
	
	for l_index: int in p_size:
		l_order[l_index] = l_index
	
	return l_order

#endregion

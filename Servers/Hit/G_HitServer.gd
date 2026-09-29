extends A_CoreServer
## Autoload that resolves area hits through the chunk index, so only entities near the shape are tested. [br]
## Hit and hurt groups decide whether a hit connects at all, stop groups end an ordered hit at the first blocker.

#region CACHED_VARS

## Cached C_HitServer.BUFFER_MIN_CAPACITY.
var BUFFER_MIN_CAPACITY: int

## Cached C_HitServer.UNLIMITED_HITS.
var UNLIMITED_HITS: int

#endregion

#region EXPORTS_AND_VARS

## Candidates of the running hit, valid up to _candidateCount.
var _candidateIds: PackedInt32Array = PackedInt32Array()

## How many entries of _candidateIds belong to the running hit.
var _candidateCount: int = 0

## Targets the shape accepted, valid up to _acceptedCount.
var _acceptedIds: PackedInt32Array = PackedInt32Array()

## Sort key of every accepted target, parallel to _acceptedIds; lower lands first.
var _acceptedSortKeys: PackedFloat32Array = PackedFloat32Array()

## Impact position of every accepted target as (x, y, height), parallel to _acceptedIds.
var _acceptedImpacts: PackedVector3Array = PackedVector3Array()

## How many entries of the accepted buffers belong to the running hit.
var _acceptedCount: int = 0

## Indices into the accepted buffers, sorted by sort key for an ordered hit.
var _acceptedOrder: PackedInt32Array = PackedInt32Array()

## Visit stamp of the running gather; raised before every gather, so older stamps never match.
var _visitStamp: int = 0

## Visit stamp per entity of the gather that last saw it; makes the candidate dedup one compare.
var _entityVisitStamp: PackedInt32Array = PackedInt32Array()

## Set once a preferred target came with a hit limit other than one. [br]
## Keeps the warning about that out of the per hit path after it was reported.
var _hasWarnedPreferredMisuse: bool = false

#endregion

#region LIFECYCLE_AND_METHODS

## Caches the constants only hit queries need; the shared ones are inherited from A_CoreServer.
func _init() -> void:
	BUFFER_MIN_CAPACITY = C_HitServer.BUFFER_MIN_CAPACITY
	UNLIMITED_HITS = C_HitServer.UNLIMITED_HITS


## Sets the vertical extent an entity occupies. [br]
## @param p_id The entity to change [br]
## @param p_heightBand The extent as (bottom, top)
func set_height_band(p_id: int, p_heightBand: Vector2) -> void:
	_entityHeightBand[p_id] = p_heightBand


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


## Sets the hurt groups that end an ordered hit of this entity on the target they match. [br]
## @param p_id The entity to change [br]
## @param p_stopGroups Bitmask of the hurt groups that block its hits
func set_stop_groups(p_id: int, p_stopGroups: int) -> void:
	_entityStopGroups[p_id] = p_stopGroups


## Sets the radius curve of an entity; null gives it a constant radius again. [br]
## @param p_id The entity to change [br]
## @param p_curve The curve to sample, or null
func set_radius_curve(p_id: int, p_curve: Curve) -> void:
	_set_radius_curve(p_id, p_curve)


## Hits every reachable target inside a circle, optionally from the center outwards. [br]
## Stop groups only apply to an ordered hit, because they need an order to be meaningful. [br]
## @param p_emitterId The entity the hit comes from [br]
## @param p_origin Center of the circle [br]
## @param p_radius Radius of the circle [br]
## @param p_heightBand Vertical extent of the hit as (bottom, top) [br]
## @param p_maxHits Upper number of hits, or C_HitServer.UNLIMITED_HITS [br]
## @param p_preferredTargetId Target to check first, or C_CoreServer.NO_ID [br]
## @param p_hitData Payload handed to every entity that is hit [br]
## @param p_isOrdered Whether targets land from the center outwards [br]
## @return The impact positions as (x, y, height), in landing order
func hit_circle(p_emitterId: int, p_origin: Vector2, p_radius: float, p_heightBand: Vector2, p_maxHits: int,
		p_preferredTargetId: int, p_hitData: R_HitData, p_isOrdered: bool) -> PackedVector3Array:
	if (_gather_preferred_candidate(p_emitterId, p_preferredTargetId, p_maxHits, p_heightBand)):
		var l_preferredImpacts: PackedVector3Array = _resolve_circle_hit(p_emitterId, p_origin, p_radius,
			p_heightBand, p_maxHits, p_hitData, p_isOrdered)

		if (not l_preferredImpacts.is_empty()):
			return l_preferredImpacts

	_gather_chunk_candidates(p_emitterId, _compute_circle_chunk_area(p_origin, p_radius), p_heightBand)

	return _resolve_circle_hit(p_emitterId, p_origin, p_radius, p_heightBand, p_maxHits, p_hitData, p_isOrdered)


## Hits every reachable target inside a directional rect, optionally ordered from one of its edges. [br]
## Stop groups only apply to an ordered hit, because they need an order to be meaningful. [br]
## @param p_emitterId The entity the hit comes from [br]
## @param p_origin Center of the back edge, where the rect starts [br]
## @param p_direction Direction the rect extends in [br]
## @param p_length Reach of the rect along its direction [br]
## @param p_width Full width of the rect across its direction [br]
## @param p_heightBand Vertical extent of the hit as (bottom, top) [br]
## @param p_maxHits Upper number of hits, or C_HitServer.UNLIMITED_HITS [br]
## @param p_preferredTargetId Target to check first, or C_CoreServer.NO_ID [br]
## @param p_hitData Payload handed to every entity that is hit [br]
## @param p_order Order the targets land in [br]
## @return The impact positions as (x, y, height), in landing order
func hit_directional_rect(p_emitterId: int, p_origin: Vector2, p_direction: Vector2, p_length: float,
		p_width: float, p_heightBand: Vector2, p_maxHits: int, p_preferredTargetId: int,
		p_hitData: R_HitData, p_order: C_HitServer.RECT_ORDER) -> PackedVector3Array:
	var l_forward: Vector2 = p_direction.normalized()

	if (_gather_preferred_candidate(p_emitterId, p_preferredTargetId, p_maxHits, p_heightBand)):
		var l_preferredImpacts: PackedVector3Array = _resolve_directional_rect_hit(p_emitterId, p_origin, l_forward,
			p_length, p_width, p_heightBand, p_maxHits, p_hitData, p_order)

		if (not l_preferredImpacts.is_empty()):
			return l_preferredImpacts

	var l_sideStep: Vector2 = l_forward.orthogonal() * p_width * 0.5
	var l_backCornerA: Vector2 = p_origin + l_sideStep
	var l_backCornerB: Vector2 = p_origin - l_sideStep
	var l_frontCornerA: Vector2 = l_backCornerA + l_forward * p_length
	var l_frontCornerB: Vector2 = l_backCornerB + l_forward * p_length

	var l_area: Vector4i = _compute_chunk_area(
		l_backCornerA.min(l_backCornerB).min(l_frontCornerA).min(l_frontCornerB),
		l_backCornerA.max(l_backCornerB).max(l_frontCornerA).max(l_frontCornerB))

	_gather_chunk_candidates(p_emitterId, l_area, p_heightBand)

	return _resolve_directional_rect_hit(p_emitterId, p_origin, l_forward, p_length, p_width,
		p_heightBand, p_maxHits, p_hitData, p_order)


## Hits every reachable target inside a sector (a cake slice), optionally sweeping across it. [br]
## Stop groups only apply to an ordered hit, because they need an order to be meaningful. [br]
## @param p_emitterId The entity the hit comes from [br]
## @param p_origin Tip of the sector [br]
## @param p_direction Direction the sector is centered on [br]
## @param p_radius Reach of the sector [br]
## @param p_openingAngle Full opening angle in radians [br]
## @param p_heightBand Vertical extent of the hit as (bottom, top) [br]
## @param p_maxHits Upper number of hits, or C_HitServer.UNLIMITED_HITS [br]
## @param p_preferredTargetId Target to check first, or C_CoreServer.NO_ID [br]
## @param p_hitData Payload handed to every entity that is hit [br]
## @param p_order Order the targets land in [br]
## @return The impact positions as (x, y, height), in landing order
func hit_sector(p_emitterId: int, p_origin: Vector2, p_direction: Vector2, p_radius: float,
		p_openingAngle: float, p_heightBand: Vector2, p_maxHits: int, p_preferredTargetId: int,
		p_hitData: R_HitData, p_order: C_HitServer.SECTOR_ORDER) -> PackedVector3Array:
	var l_forward: Vector2 = p_direction.normalized()

	if (_gather_preferred_candidate(p_emitterId, p_preferredTargetId, p_maxHits, p_heightBand)):
		var l_preferredImpacts: PackedVector3Array = _resolve_sector_hit(p_emitterId, p_origin, l_forward,
			p_radius, p_openingAngle, p_heightBand, p_maxHits, p_hitData, p_order)

		if (not l_preferredImpacts.is_empty()):
			return l_preferredImpacts

	_gather_chunk_candidates(p_emitterId, _compute_circle_chunk_area(p_origin, p_radius), p_heightBand)

	return _resolve_sector_hit(p_emitterId, p_origin, l_forward, p_radius, p_openingAngle,
		p_heightBand, p_maxHits, p_hitData, p_order)


## Accepts the candidates whose silhouette reaches into the circle, then dispatches the hit. [br]
## @param p_emitterId The entity the hit comes from [br]
## @param p_origin Center of the circle [br]
## @param p_radius Radius of the circle [br]
## @param p_heightBand Vertical extent of the hit as (bottom, top) [br]
## @param p_maxHits Upper number of hits, or C_HitServer.UNLIMITED_HITS [br]
## @param p_hitData Payload handed to every entity that is hit [br]
## @param p_isOrdered Whether targets land from the center outwards [br]
## @return The impact positions as (x, y, height), in landing order
func _resolve_circle_hit(p_emitterId: int, p_origin: Vector2, p_radius: float, p_heightBand: Vector2,
		p_maxHits: int, p_hitData: R_HitData, p_isOrdered: bool) -> PackedVector3Array:
	_acceptedCount = 0

	var l_positions: PackedVector2Array = _entityPosition

	for l_candidateIndex: int in _candidateCount:
		var l_id: int = _candidateIds[l_candidateIndex]
		var l_height: float = _get_sample_height(l_id, p_heightBand)
		var l_radius: float = _get_effective_radius(l_id, l_height)
		var l_distanceSquared: float = l_positions[l_id].distance_squared_to(p_origin)
		var l_reach: float = p_radius + l_radius

		if (l_distanceSquared > l_reach * l_reach):
			continue

		_accept_target(l_id, l_distanceSquared, _get_impact_position(l_id, l_radius, l_height, p_origin))

	return _dispatch_hits(p_emitterId, p_maxHits, p_hitData, p_isOrdered)


## Accepts the candidates whose silhouette reaches into the rect, then dispatches the hit. [br]
## @param p_emitterId The entity the hit comes from [br]
## @param p_origin Center of the back edge, where the rect starts [br]
## @param p_forward Normalized direction the rect extends in [br]
## @param p_length Reach of the rect along its direction [br]
## @param p_width Full width of the rect across its direction [br]
## @param p_heightBand Vertical extent of the hit as (bottom, top) [br]
## @param p_maxHits Upper number of hits, or C_HitServer.UNLIMITED_HITS [br]
## @param p_hitData Payload handed to every entity that is hit [br]
## @param p_order Order the targets land in [br]
## @return The impact positions as (x, y, height), in landing order
func _resolve_directional_rect_hit(p_emitterId: int, p_origin: Vector2, p_forward: Vector2, p_length: float,
		p_width: float, p_heightBand: Vector2, p_maxHits: int, p_hitData: R_HitData,
		p_order: C_HitServer.RECT_ORDER) -> PackedVector3Array:
	_acceptedCount = 0

	var l_positions: PackedVector2Array = _entityPosition
	var l_right: Vector2 = -p_forward.orthogonal()
	var l_halfWidth: float = p_width * 0.5

	for l_candidateIndex: int in _candidateCount:
		var l_id: int = _candidateIds[l_candidateIndex]
		var l_height: float = _get_sample_height(l_id, p_heightBand)
		var l_radius: float = _get_effective_radius(l_id, l_height)
		var l_toTarget: Vector2 = l_positions[l_id] - p_origin
		var l_along: float = l_toTarget.dot(p_forward)
		var l_across: float = l_toTarget.dot(l_right)
		var l_gapAlong: float = l_along - clampf(l_along, 0.0, p_length)
		var l_gapAcross: float = l_across - clampf(l_across, -l_halfWidth, l_halfWidth)

		if (l_gapAlong * l_gapAlong + l_gapAcross * l_gapAcross > l_radius * l_radius):
			continue

		_accept_target(l_id, _get_rect_sort_key(p_order, l_along, l_across, p_length),
			_get_impact_position(l_id, l_radius, l_height, p_origin))

	return _dispatch_hits(p_emitterId, p_maxHits, p_hitData, p_order != C_HitServer.RECT_ORDER.NONE)


## Accepts the candidates whose silhouette reaches into the sector, then dispatches the hit. [br]
## @param p_emitterId The entity the hit comes from [br]
## @param p_origin Tip of the sector [br]
## @param p_forward Normalized direction the sector is centered on [br]
## @param p_radius Reach of the sector [br]
## @param p_openingAngle Full opening angle in radians [br]
## @param p_heightBand Vertical extent of the hit as (bottom, top) [br]
## @param p_maxHits Upper number of hits, or C_HitServer.UNLIMITED_HITS [br]
## @param p_hitData Payload handed to every entity that is hit [br]
## @param p_order Order the targets land in [br]
## @return The impact positions as (x, y, height), in landing order
func _resolve_sector_hit(p_emitterId: int, p_origin: Vector2, p_forward: Vector2, p_radius: float,
		p_openingAngle: float, p_heightBand: Vector2, p_maxHits: int, p_hitData: R_HitData,
		p_order: C_HitServer.SECTOR_ORDER) -> PackedVector3Array:
	_acceptedCount = 0

	var l_positions: PackedVector2Array = _entityPosition
	var l_halfAngle: float = p_openingAngle * 0.5
	var l_rightEdgeEnd: Vector2 = p_origin + p_forward.rotated(l_halfAngle) * p_radius
	var l_leftEdgeEnd: Vector2 = p_origin + p_forward.rotated(-l_halfAngle) * p_radius
	var l_isLeftToRight: bool = p_order == C_HitServer.SECTOR_ORDER.LEFT_TO_RIGHT

	for l_candidateIndex: int in _candidateCount:
		var l_id: int = _candidateIds[l_candidateIndex]
		var l_height: float = _get_sample_height(l_id, p_heightBand)
		var l_radius: float = _get_effective_radius(l_id, l_height)
		var l_position: Vector2 = l_positions[l_id]
		var l_toTarget: Vector2 = l_position - p_origin
		var l_reach: float = p_radius + l_radius

		if (l_toTarget.length_squared() > l_reach * l_reach):
			continue

		var l_signedAngle: float = p_forward.angle_to(l_toTarget)
		if (not _touches_sector(l_position, l_radius, l_signedAngle, l_halfAngle, p_origin, l_rightEdgeEnd, l_leftEdgeEnd)):
			continue

		_accept_target(l_id, l_signedAngle if l_isLeftToRight else -l_signedAngle,
			_get_impact_position(l_id, l_radius, l_height, p_origin))

	return _dispatch_hits(p_emitterId, p_maxHits, p_hitData, p_order != C_HitServer.SECTOR_ORDER.NONE)


## Records one candidate in the reused candidate buffer, growing it only when it is full. [br]
## @param p_id The entity worth testing against the shape
func _add_candidate(p_id: int) -> void:
	if (_candidateCount == _candidateIds.size()):
		_candidateIds.resize(maxi(_candidateCount * 2, BUFFER_MIN_CAPACITY))

	_candidateIds[_candidateCount] = p_id
	_candidateCount += 1


## Records one target the shape accepted in the reused buffers, growing them only when they are full. [br]
## @param p_id The accepted target [br]
## @param p_sortKey Its sort key; lower lands first in an ordered hit [br]
## @param p_impact Its impact position as (x, y, height)
func _accept_target(p_id: int, p_sortKey: float, p_impact: Vector3) -> void:
	if (_acceptedCount == _acceptedIds.size()):
		var l_capacity: int = maxi(_acceptedCount * 2, BUFFER_MIN_CAPACITY)
		_acceptedIds.resize(l_capacity)
		_acceptedSortKeys.resize(l_capacity)
		_acceptedImpacts.resize(l_capacity)

	_acceptedIds[_acceptedCount] = p_id
	_acceptedSortKeys[_acceptedCount] = p_sortKey
	_acceptedImpacts[_acceptedCount] = p_impact
	_acceptedCount += 1


## Collects every entity of another team standing in a chunk area that a hit could reach. [br]
## Skips columns and chunks without opponents, and stamps every entity so each is collected once. [br]
## @param p_emitterId The entity the hit comes from [br]
## @param p_area Chunks under the bounds of the hit shape, as (minColumn, minRow, maxColumn, maxRow) [br]
## @param p_heightBand Vertical extent of the hit
func _gather_chunk_candidates(p_emitterId: int, p_area: Vector4i, p_heightBand: Vector2) -> void:
	_candidateCount = 0
	_visitStamp += 1

	if (_entityVisitStamp.size() < _entityTeam.size()):
		_entityVisitStamp.resize(_entityTeam.size())

	var l_emitterTeam: int = _entityTeam[p_emitterId]
	var l_visitStamp: int = _visitStamp
	var l_chunkFirstSlot: PackedInt32Array = _chunkFirstSlot
	var l_slotEntity: PackedInt32Array = _slotEntity
	var l_slotChunkNext: PackedInt32Array = _slotChunkNext

	for l_column: int in range(p_area.x, p_area.z + 1):
		if (not _column_has_opponent(l_column, l_emitterTeam)):
			continue

		for l_row: int in range(p_area.y, p_area.w + 1):
			var l_chunkId: int = l_row * CHUNK_COLUMNS + l_column

			if (not _chunk_has_opponent(l_chunkId, l_emitterTeam)):
				continue

			var l_slot: int = l_chunkFirstSlot[l_chunkId]
			while (l_slot != NO_ID):
				var l_id: int = l_slotEntity[l_slot]
				l_slot = l_slotChunkNext[l_slot]

				if (_entityVisitStamp[l_id] == l_visitStamp):
					continue

				_entityVisitStamp[l_id] = l_visitStamp

				if (_can_be_hit(p_emitterId, l_id, p_heightBand)):
					_add_candidate(l_id)


## Checks whether any team other than the given one stands in a column. [br]
## @param p_column The column to check [br]
## @param p_team The team that asks [br]
## @return true if an opponent stands there
func _column_has_opponent(p_column: int, p_team: int) -> bool:
	for l_team: int in TEAM_COUNT:
		if (l_team != p_team and _teamColumnMembershipCount[l_team * CHUNK_COLUMNS + p_column] > 0):
			return true

	return false


## Checks whether any team other than the given one stands in a chunk. [br]
## @param p_chunkId The chunk to check [br]
## @param p_team The team that asks [br]
## @return true if an opponent stands there
func _chunk_has_opponent(p_chunkId: int, p_team: int) -> bool:
	for l_team: int in TEAM_COUNT:
		if (l_team != p_team and _teamChunkMembershipCount[l_team * CHUNK_COUNT + p_chunkId] > 0):
			return true

	return false


## Puts the preferred target into the candidate buffer as its only entry. [br]
## Warns once and falls back to a normal hit when a preference comes with more than one allowed hit. [br]
## @param p_emitterId The entity the hit comes from [br]
## @param p_preferredTargetId The target to check first, or NO_ID [br]
## @param p_maxHits Upper number of hits of this hit [br]
## @param p_heightBand Vertical extent of the hit [br]
## @return true if the preferred target is worth testing on its own
func _gather_preferred_candidate(p_emitterId: int, p_preferredTargetId: int, p_maxHits: int,
		p_heightBand: Vector2) -> bool:
	_candidateCount = 0

	if (p_preferredTargetId == NO_ID):
		return false

	if (p_maxHits != 1):
		if (not _hasWarnedPreferredMisuse):
			_hasWarnedPreferredMisuse = true
			push_warning("G_HitServer: a preferred target is only used when p_maxHits is 1, ignoring it.")

		return false

	if (not _can_be_hit(p_emitterId, p_preferredTargetId, p_heightBand)):
		return false

	_add_candidate(p_preferredTargetId)
	return true


## Checks everything about a target that does not depend on the hit shape. [br]
## @param p_emitterId The entity the hit comes from [br]
## @param p_targetId The entity to check [br]
## @param p_heightBand Vertical extent of the hit [br]
## @return true if only the geometry is left to decide
func _can_be_hit(p_emitterId: int, p_targetId: int, p_heightBand: Vector2) -> bool:
	if (_entityTeam[p_targetId] == _entityTeam[p_emitterId]):
		return false

	if (_isEntityPendingRemoval[p_targetId] == 1 or _isEntityRemoved[p_targetId] == 1):
		return false

	if ((_entityHitGroups[p_emitterId] & _entityHurtGroups[p_targetId]) == 0):
		return false

	var l_targetBand: Vector2 = _entityHeightBand[p_targetId]
	return p_heightBand.x <= l_targetBand.y and p_heightBand.y >= l_targetBand.x


## Picks the height a hit is measured at: the middle of the hit band, held inside the target. [br]
## @param p_id The entity that is hit [br]
## @param p_heightBand Vertical extent of the hit [br]
## @return The height on the target the hit lands at
func _get_sample_height(p_id: int, p_heightBand: Vector2) -> float:
	var l_targetBand: Vector2 = _entityHeightBand[p_id]
	return clampf((p_heightBand.x + p_heightBand.y) * 0.5, l_targetBand.x, l_targetBand.y)


## Reads the radius a target offers at one height from the baked radius factors of its curve. [br]
## Entities without a curve keep their full radius over the whole height. [br]
## @param p_id The entity that is hit [br]
## @param p_sampleHeight The height the hit lands at [br]
## @return The radius that counts for this hit
func _get_effective_radius(p_id: int, p_sampleHeight: float) -> float:
	var l_radius: float = _entityRadius[p_id]
	var l_curveId: int = _entityCurveId[p_id]

	if (l_curveId == NO_ID):
		return l_radius

	var l_band: Vector2 = _entityHeightBand[p_id]
	var l_bandHeight: float = l_band.y - l_band.x

	if (l_bandHeight <= 0.0):
		return l_radius

	var l_lastSampleIndex: int = CURVE_SAMPLE_COUNT - 1
	var l_sampleCursor: float = clampf((p_sampleHeight - l_band.x) / l_bandHeight, 0.0, 1.0) * l_lastSampleIndex
	var l_lowerSampleIndex: int = mini(int(l_sampleCursor), l_lastSampleIndex - 1)
	var l_factorIndex: int = l_curveId * CURVE_SAMPLE_COUNT + l_lowerSampleIndex
	var l_lowerFactor: float = _curveRadiusFactors[l_factorIndex]
	var l_factor: float = l_lowerFactor + (_curveRadiusFactors[l_factorIndex + 1] - l_lowerFactor) * (l_sampleCursor - l_lowerSampleIndex)

	return l_radius * l_factor


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


## Checks a target against the opening angle and the two straight edges of a sector. [br]
## The tip is an endpoint of both edges, so the edge tests already cover it. [br]
## @param p_position Center of the target [br]
## @param p_radius Its radius at the hit height [br]
## @param p_signedAngle Its angle against the sector direction [br]
## @param p_halfAngle Half the opening angle of the sector [br]
## @param p_origin Tip of the sector [br]
## @param p_rightEdgeEnd Far end of the right edge [br]
## @param p_leftEdgeEnd Far end of the left edge [br]
## @return true if the target reaches into the sector
func _touches_sector(p_position: Vector2, p_radius: float, p_signedAngle: float, p_halfAngle: float,
		p_origin: Vector2, p_rightEdgeEnd: Vector2, p_leftEdgeEnd: Vector2) -> bool:
	if (absf(p_signedAngle) <= p_halfAngle):
		return true

	var l_radiusSquared: float = p_radius * p_radius
	var l_closestOnRightEdge: Vector2 = Geometry2D.get_closest_point_to_segment(p_position, p_origin, p_rightEdgeEnd)

	if (p_position.distance_squared_to(l_closestOnRightEdge) <= l_radiusSquared):
		return true

	var l_closestOnLeftEdge: Vector2 = Geometry2D.get_closest_point_to_segment(p_position, p_origin, p_leftEdgeEnd)
	return p_position.distance_squared_to(l_closestOnLeftEdge) <= l_radiusSquared


## Turns a position inside a rect into the sort key of the chosen order. [br]
## @param p_order The order the targets land in [br]
## @param p_along Distance along the direction of the rect [br]
## @param p_across Distance across it, positive towards the right of the direction [br]
## @param p_length Reach of the rect [br]
## @return The key to sort ascending by
func _get_rect_sort_key(p_order: C_HitServer.RECT_ORDER, p_along: float, p_across: float, p_length: float) -> float:
	match p_order:
		C_HitServer.RECT_ORDER.FROM_FRONT:
			return p_length - p_along
		C_HitServer.RECT_ORDER.FROM_RIGHT:
			return -p_across
		C_HitServer.RECT_ORDER.FROM_LEFT:
			return p_across

	return p_along


## Orders the accepted targets, cuts them at the stop groups and the hit limit, and hands them to their module managers. [br]
## Dispatches from a snapshot, so a module manager may fire hits meanwhile; targets it removed are skipped. [br]
## @param p_emitterId The entity the hit comes from [br]
## @param p_maxHits Upper number of hits, or C_HitServer.UNLIMITED_HITS [br]
## @param p_hitData Payload handed to every entity that is hit [br]
## @param p_isOrdered Whether the sort keys decide the order and the stop groups apply [br]
## @return The impact positions of the hits that landed, in landing order
func _dispatch_hits(p_emitterId: int, p_maxHits: int, p_hitData: R_HitData,
		p_isOrdered: bool) -> PackedVector3Array:
	var l_limit: int = _acceptedCount

	if (p_maxHits != UNLIMITED_HITS):
		l_limit = mini(p_maxHits, _acceptedCount)

	if (l_limit <= 0):
		return PackedVector3Array()

	var l_chosenImpacts: PackedVector3Array = PackedVector3Array()
	var l_chosenIds: PackedInt32Array = PackedInt32Array()

	if (not p_isOrdered):
		l_chosenImpacts = _acceptedImpacts.slice(0, l_limit)
		l_chosenIds = _acceptedIds.slice(0, l_limit)
	elif (l_limit == 1):
		var l_firstIndex: int = _find_lowest_sort_key_index()
		l_chosenImpacts.append(_acceptedImpacts[l_firstIndex])
		l_chosenIds.append(_acceptedIds[l_firstIndex])
	else:
		_sort_accepted_by_key()

		var l_stopGroups: int = _entityStopGroups[p_emitterId]

		for l_rank: int in l_limit:
			var l_acceptedIndex: int = _acceptedOrder[l_rank]
			var l_targetId: int = _acceptedIds[l_acceptedIndex]

			l_chosenImpacts.append(_acceptedImpacts[l_acceptedIndex])
			l_chosenIds.append(l_targetId)

			if ((l_stopGroups & _entityHurtGroups[l_targetId]) != 0):
				break

	var l_landedImpacts: PackedVector3Array = PackedVector3Array()

	for l_rank: int in l_chosenIds.size():
		var l_targetId: int = l_chosenIds[l_rank]

		if (_isEntityPendingRemoval[l_targetId] == 1 or _isEntityRemoved[l_targetId] == 1):
			continue

		l_landedImpacts.append(l_chosenImpacts[l_rank])

		var l_moduleManager: M_ModuleManager = _entityModuleManager[l_targetId]

		if (l_moduleManager != null):
			l_moduleManager.hit(p_hitData)

	return l_landedImpacts


## Finds the accepted target with the lowest sort key, for ordered hits that land exactly once. [br]
## @return Its index in the accepted buffers
func _find_lowest_sort_key_index() -> int:
	var l_lowestIndex: int = 0

	for l_acceptedIndex: int in range(1, _acceptedCount):
		if (_acceptedSortKeys[l_acceptedIndex] < _acceptedSortKeys[l_lowestIndex]):
			l_lowestIndex = l_acceptedIndex

	return l_lowestIndex


## Fills _acceptedOrder with the accepted indices sorted ascending by sort key. [br]
## Insertion sort; only an area hit accepting dozens of targets reaches its quadratic case.
func _sort_accepted_by_key() -> void:
	if (_acceptedOrder.size() < _acceptedCount):
		_acceptedOrder.resize(_acceptedCount)

	for l_acceptedIndex: int in _acceptedCount:
		var l_sortKey: float = _acceptedSortKeys[l_acceptedIndex]
		var l_insertAt: int = l_acceptedIndex

		while (l_insertAt > 0 and _acceptedSortKeys[_acceptedOrder[l_insertAt - 1]] > l_sortKey):
			_acceptedOrder[l_insertAt] = _acceptedOrder[l_insertAt - 1]
			l_insertAt -= 1

		_acceptedOrder[l_insertAt] = l_acceptedIndex

#endregion

extends Node
## Autoload that resolves area hits through the chunk index, so only entities near the shape are tested. [br]
## Hit and hurt groups decide whether a hit connects at all, stop groups end it at the first blocker.

#region CACHED_VARS

## Cached C_ChunkingServer.MAP_CHUNK_COLUMNS; the candidate gather reads it constantly.
var MAP_CHUNK_COLUMNS: int

## Cached C_ChunkingServer.NO_SLOT.
var NO_SLOT: int

## Cached C_HitServer.NO_CURVE.
var NO_CURVE: int

## Cached C_HitServer.CURVE_SAMPLE_COUNT.
var CURVE_SAMPLE_COUNT: int

## Cached C_HitServer.CURVE_PERCENT_MAX.
var CURVE_PERCENT_MAX: float

## Cached C_HitServer.BUFFER_MIN_CAPACITY.
var BUFFER_MIN_CAPACITY: int

## Cached C_HitServer.NO_PREFERRED_TARGET.
var NO_PREFERRED_TARGET: int

## Cached C_HitServer.UNLIMITED_HITS.
var UNLIMITED_HITS: int

#endregion

#region EXPORTS_AND_VARS

## Module management per entity id; receives every hit that connects with it.
var _entityModules: Array[M_ModuleManager] = []

## Vertical extent per entity as (bottom, top); the third axis next to the 2D position.
var _entityYBand: PackedVector2Array = PackedVector2Array()

## Bitmask of the hit groups an entity can be harmed by.
var _entityHurtGroups: PackedInt64Array = PackedInt64Array()

## Bitmask of the hit groups the hits of an entity carry.
var _entityHitGroups: PackedInt64Array = PackedInt64Array()

## Bitmask of the hurt groups that end a hit of this entity on the target they match.
var _entityStopGroups: PackedInt64Array = PackedInt64Array()

## Curve slot per entity, or C_HitServer.NO_CURVE while its radius is constant over the height.
var _entityCurveIndex: PackedInt32Array = PackedInt32Array()

## Hit query that last looked at an entity; turns the candidate dedup into one compare.
var _entityVisitStamp: PackedInt32Array = PackedInt32Array()

## Curve stored in every slot; kept only to recognise it again and to free the slot.
var _radiiCurves: Array[Curve] = []

## Every curve slot baked into C_HitServer.CURVE_SAMPLE_COUNT samples, one block per slot. [br]
## A hit reads two floats and interpolates, instead of calling into the Curve object.
var _curveSamples: PackedFloat32Array = PackedFloat32Array()

## Slot every stored curve sits in, so one archetype never fills more than one slot.
var _curveSlotOf: Dictionary[Curve, int] = {}

## Entities using each curve slot; the slot returns to the free list when it drops to zero.
var _curveUsers: PackedInt32Array = PackedInt32Array()

## Curve slots of dropped profiles, ready to be handed out again.
var _freeCurveIndices: PackedInt32Array = PackedInt32Array()

## Profile every entity registered without one falls back to.
var _defaultHitProfile: R_HitProfile = null

## Set once a preferred target was passed with a hit limit other than one. [br]
## Keeps the warning about that out of the per hit path after it was reported.
var _hasWarnedPreferredMisuse: bool = false

## Candidates of the running hit, live up to _candidateCount.
var _candidateIds: PackedInt32Array = PackedInt32Array()

## How many candidates of _candidateIds belong to the running hit.
var _candidateCount: int = 0

## Targets the shape accepted, live up to _hitCount.
var _hitIds: PackedInt32Array = PackedInt32Array()

## Sort key of every accepted target, parallel to _hitIds.
var _hitKeys: PackedFloat32Array = PackedFloat32Array()

## Impact position of every accepted target, parallel to _hitIds.
var _hitPositions: PackedVector3Array = PackedVector3Array()

## How many targets of the hit buffers belong to the running hit.
var _hitCount: int = 0

## Indices into the hit buffers in the order an ordered hit applies them.
var _hitOrder: PackedInt32Array = PackedInt32Array()

## Counter handed to every gather, so stamps of earlier hits can never collide.
var _visitStamp: int = 0

#endregion

#region LIFECYCLE_AND_METHODS

## Follows the id lifecycle of the G_ChunkingServer autoload, which is loaded before this one. [br]
## Runs before any entity can register, so every id the index hands out gets a slot here.
func _ready() -> void:
	G_ChunkingServer.s_entitySlotAppended.connect(_append_slot)
	G_ChunkingServer.s_entityReleased.connect(_reset_slot)
	
	MAP_CHUNK_COLUMNS = C_ChunkingServer.MAP_CHUNK_COLUMNS
	NO_SLOT = C_ChunkingServer.NO_SLOT
	NO_CURVE = C_HitServer.NO_CURVE
	CURVE_SAMPLE_COUNT = C_HitServer.CURVE_SAMPLE_COUNT
	CURVE_PERCENT_MAX = C_HitServer.CURVE_PERCENT_MAX
	BUFFER_MIN_CAPACITY = C_HitServer.BUFFER_MIN_CAPACITY
	NO_PREFERRED_TARGET = C_HitServer.NO_PREFERRED_TARGET
	UNLIMITED_HITS = C_HitServer.UNLIMITED_HITS


## Gives an entity its hit side; an entity that never calls this can never be hit. [br]
## @param p_id The id G_ChunkingServer.register_entity() returned [br]
## @param p_module Module management that receives its hits [br]
## @param p_hitProfile Band, groups and radius profile of the entity
func register(p_id: int, p_module: M_ModuleManager, p_hitProfile: R_HitProfile) -> void:
	var l_hitProfile: R_HitProfile = p_hitProfile
	
	if (l_hitProfile == null):
		push_error("G_HitServer: entity %d was registered without a hit profile, using the default one." % p_id)
		l_hitProfile = _get_default_hit_profile()
	
	_entityModules[p_id] = p_module
	_entityYBand[p_id] = l_hitProfile.yBand
	_entityHurtGroups[p_id] = l_hitProfile.hurtGroups
	_entityHitGroups[p_id] = l_hitProfile.hitGroups
	_entityStopGroups[p_id] = l_hitProfile.stopGroups
	
	set_radius_curve(p_id, l_hitProfile.radiusCurve)


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
## Entities sharing one curve share its slot, so profiles cost per archetype, not per entity. [br]
## @param p_id The entity to change [br]
## @param p_curve The profile to sample, or null
func set_radius_curve(p_id: int, p_curve: Curve) -> void:
	if (p_curve == null):
		_release_curve(p_id)
		return
	
	var l_curveIndex: int = _curveSlotOf.get(p_curve, NO_CURVE)
	
	if (l_curveIndex != NO_CURVE and l_curveIndex == _entityCurveIndex[p_id]):
		return
	
	_release_curve(p_id)
	
	if (l_curveIndex == NO_CURVE):
		l_curveIndex = _acquire_curve_slot(p_curve)
	
	_curveUsers[l_curveIndex] += 1
	_entityCurveIndex[p_id] = l_curveIndex


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
## @param p_isReversed Sweeps from the left edge to the right instead [br]
## @return The impact positions as (x, y, height), in sweep order
func hit_cake_slice_ordered(p_emitterId: int, p_origin: Vector2, p_direction: Vector2, p_radius: float,
		p_angle: float, p_hitYBand: Vector2, p_maxHits: int, p_preferredId: int,
		p_hitData: R_HitData, p_isReversed: bool) -> PackedVector3Array:
	return _resolve_cake_slice(p_emitterId, p_origin, p_direction, p_radius, p_angle, p_hitYBand,
		p_maxHits, p_preferredId, p_hitData, true, p_isReversed)


## Runs a circle hit against the preferred target first and the chunks of its area second. [br]
## @param p_emitterId The entity the hit comes from [br]
## @param p_origin Center of the circle [br]
## @param p_radius Radius of the circle [br]
## @param p_hitYBand Vertical extent of the hit as (bottom, top) [br]
## @param p_maxHits Upper number of hits, or C_HitServer.UNLIMITED_HITS [br]
## @param p_preferredId Target to check first, or C_HitServer.NO_PREFERRED_TARGET [br]
## @param p_hitData Payload handed to every entity that is hit [br]
## @param p_isOrdered Whether the order from the center outwards decides [br]
## @return The impact positions as (x, y, height)
func _resolve_circle(p_emitterId: int, p_origin: Vector2, p_radius: float, p_hitYBand: Vector2,
		p_maxHits: int, p_preferredId: int, p_hitData: R_HitData, p_isOrdered: bool) -> PackedVector3Array:
	if (_gather_preferred_candidate(p_emitterId, p_preferredId, p_maxHits, p_hitYBand)):
		var l_preferredResult: PackedVector3Array = _test_circle(p_emitterId, p_origin, p_radius,
			p_hitYBand, p_maxHits, p_hitData, p_isOrdered)
		
		if (not l_preferredResult.is_empty()):
			return l_preferredResult
	
	var l_extent: Vector2 = Vector2(p_radius, p_radius)
	_gather_chunk_candidates(p_emitterId, p_origin - l_extent, p_origin + l_extent, p_hitYBand)
	
	return _test_circle(p_emitterId, p_origin, p_radius, p_hitYBand, p_maxHits, p_hitData, p_isOrdered)


## Keeps the gathered candidates whose silhouette reaches into the circle. [br]
## @param p_emitterId The entity the hit comes from [br]
## @param p_origin Center of the circle [br]
## @param p_radius Radius of the circle [br]
## @param p_hitYBand Vertical extent of the hit as (bottom, top) [br]
## @param p_maxHits Upper number of hits, or C_HitServer.UNLIMITED_HITS [br]
## @param p_hitData Payload handed to every entity that is hit [br]
## @param p_isOrdered Whether the order from the center outwards decides [br]
## @return The impact positions as (x, y, height)
func _test_circle(p_emitterId: int, p_origin: Vector2, p_radius: float, p_hitYBand: Vector2,
		p_maxHits: int, p_hitData: R_HitData, p_isOrdered: bool) -> PackedVector3Array:
	_hitCount = 0
	
	var l_positions: PackedVector2Array = G_ChunkingServer._entityPosition
	
	for l_slot: int in _candidateCount:
		var l_id: int = _candidateIds[l_slot]
		var l_height: float = _get_sample_height(l_id, p_hitYBand)
		var l_radius: float = _get_effective_radius(l_id, l_height)
		var l_distanceSquared: float = l_positions[l_id].distance_squared_to(p_origin)
		var l_reach: float = p_radius + l_radius
		
		if (l_distanceSquared > l_reach * l_reach):
			continue
		
		_push_hit(l_id, l_distanceSquared, _get_impact_position(l_id, l_radius, l_height, p_origin))
	
	return _apply_hits(p_emitterId, p_maxHits, p_hitData, p_isOrdered)


## Runs a rect hit against the preferred target first and the chunks of its area second. [br]
## @param p_emitterId The entity the hit comes from [br]
## @param p_origin Center of the back edge, where the rect starts [br]
## @param p_direction Direction the rect extends in [br]
## @param p_length Reach of the rect along its direction [br]
## @param p_width Full width of the rect across its direction [br]
## @param p_hitYBand Vertical extent of the hit as (bottom, top) [br]
## @param p_maxHits Upper number of hits, or C_HitServer.UNLIMITED_HITS [br]
## @param p_preferredId Target to check first, or C_HitServer.NO_PREFERRED_TARGET [br]
## @param p_hitData Payload handed to every entity that is hit [br]
## @param p_isOrdered Whether the order from the start edge decides [br]
## @param p_startEdge Edge the order starts at, as a C_HitServer.RECT_EDGE value [br]
## @return The impact positions as (x, y, height)
func _resolve_directional_rect(p_emitterId: int, p_origin: Vector2, p_direction: Vector2, p_length: float,
		p_width: float, p_hitYBand: Vector2, p_maxHits: int, p_preferredId: int, p_hitData: R_HitData,
		p_isOrdered: bool, p_startEdge: int) -> PackedVector3Array:
	if (_gather_preferred_candidate(p_emitterId, p_preferredId, p_maxHits, p_hitYBand)):
		var l_preferredResult: PackedVector3Array = _test_directional_rect(p_emitterId, p_origin, p_direction,
			p_length, p_width, p_hitYBand, p_maxHits, p_hitData, p_isOrdered, p_startEdge)
		
		if (not l_preferredResult.is_empty()):
			return l_preferredResult
	
	var l_forward: Vector2 = p_direction.normalized()
	var l_sideStep: Vector2 = l_forward.orthogonal() * p_width * 0.5
	var l_cornerA: Vector2 = p_origin + l_sideStep
	var l_cornerB: Vector2 = p_origin - l_sideStep
	var l_cornerC: Vector2 = l_cornerA + l_forward * p_length
	var l_cornerD: Vector2 = l_cornerB + l_forward * p_length
	
	_gather_chunk_candidates(p_emitterId,
		l_cornerA.min(l_cornerB).min(l_cornerC).min(l_cornerD),
		l_cornerA.max(l_cornerB).max(l_cornerC).max(l_cornerD),
		p_hitYBand)
	
	return _test_directional_rect(p_emitterId, p_origin, p_direction, p_length, p_width,
		p_hitYBand, p_maxHits, p_hitData, p_isOrdered, p_startEdge)


## Keeps the gathered candidates whose silhouette reaches into the rect. [br]
## @param p_emitterId The entity the hit comes from [br]
## @param p_origin Center of the back edge, where the rect starts [br]
## @param p_direction Direction the rect extends in [br]
## @param p_length Reach of the rect along its direction [br]
## @param p_width Full width of the rect across its direction [br]
## @param p_hitYBand Vertical extent of the hit as (bottom, top) [br]
## @param p_maxHits Upper number of hits, or C_HitServer.UNLIMITED_HITS [br]
## @param p_hitData Payload handed to every entity that is hit [br]
## @param p_isOrdered Whether the order from the start edge decides [br]
## @param p_startEdge Edge the order starts at, as a C_HitServer.RECT_EDGE value [br]
## @return The impact positions as (x, y, height)
func _test_directional_rect(p_emitterId: int, p_origin: Vector2, p_direction: Vector2, p_length: float,
		p_width: float, p_hitYBand: Vector2, p_maxHits: int, p_hitData: R_HitData,
		p_isOrdered: bool, p_startEdge: int) -> PackedVector3Array:
	_hitCount = 0
	
	var l_positions: PackedVector2Array = G_ChunkingServer._entityPosition
	var l_forward: Vector2 = p_direction.normalized()
	var l_side: Vector2 = -l_forward.orthogonal()
	var l_halfWidth: float = p_width * 0.5
	
	for l_slot: int in _candidateCount:
		var l_id: int = _candidateIds[l_slot]
		var l_height: float = _get_sample_height(l_id, p_hitYBand)
		var l_radius: float = _get_effective_radius(l_id, l_height)
		var l_toTarget: Vector2 = l_positions[l_id] - p_origin
		var l_along: float = l_toTarget.dot(l_forward)
		var l_across: float = l_toTarget.dot(l_side)
		var l_gapAlong: float = l_along - clampf(l_along, 0.0, p_length)
		var l_gapAcross: float = l_across - clampf(l_across, -l_halfWidth, l_halfWidth)
		
		if (l_gapAlong * l_gapAlong + l_gapAcross * l_gapAcross > l_radius * l_radius):
			continue
		
		_push_hit(l_id, _get_rect_key(p_startEdge, l_along, l_across, p_length),
			_get_impact_position(l_id, l_radius, l_height, p_origin))
	
	return _apply_hits(p_emitterId, p_maxHits, p_hitData, p_isOrdered)


## Runs a slice hit against the preferred target first and the chunks of its area second. [br]
## @param p_emitterId The entity the hit comes from [br]
## @param p_origin Tip of the slice [br]
## @param p_direction Direction the slice is centered on [br]
## @param p_radius Reach of the slice [br]
## @param p_angle Full opening angle in radians [br]
## @param p_hitYBand Vertical extent of the hit as (bottom, top) [br]
## @param p_maxHits Upper number of hits, or C_HitServer.UNLIMITED_HITS [br]
## @param p_preferredId Target to check first, or C_HitServer.NO_PREFERRED_TARGET [br]
## @param p_hitData Payload handed to every entity that is hit [br]
## @param p_isOrdered Whether the sweep order decides [br]
## @param p_isReversed Sweeps from the left edge to the right instead [br]
## @return The impact positions as (x, y, height)
func _resolve_cake_slice(p_emitterId: int, p_origin: Vector2, p_direction: Vector2, p_radius: float,
		p_angle: float, p_hitYBand: Vector2, p_maxHits: int, p_preferredId: int, p_hitData: R_HitData,
		p_isOrdered: bool, p_isReversed: bool) -> PackedVector3Array:
	if (_gather_preferred_candidate(p_emitterId, p_preferredId, p_maxHits, p_hitYBand)):
		var l_preferredResult: PackedVector3Array = _test_cake_slice(p_emitterId, p_origin, p_direction,
			p_radius, p_angle, p_hitYBand, p_maxHits, p_hitData, p_isOrdered, p_isReversed)
		
		if (not l_preferredResult.is_empty()):
			return l_preferredResult
	
	var l_extent: Vector2 = Vector2(p_radius, p_radius)
	_gather_chunk_candidates(p_emitterId, p_origin - l_extent, p_origin + l_extent, p_hitYBand)
	
	return _test_cake_slice(p_emitterId, p_origin, p_direction, p_radius, p_angle,
		p_hitYBand, p_maxHits, p_hitData, p_isOrdered, p_isReversed)


## Keeps the gathered candidates whose silhouette reaches into the slice. [br]
## @param p_emitterId The entity the hit comes from [br]
## @param p_origin Tip of the slice [br]
## @param p_direction Direction the slice is centered on [br]
## @param p_radius Reach of the slice [br]
## @param p_angle Full opening angle in radians [br]
## @param p_hitYBand Vertical extent of the hit as (bottom, top) [br]
## @param p_maxHits Upper number of hits, or C_HitServer.UNLIMITED_HITS [br]
## @param p_hitData Payload handed to every entity that is hit [br]
## @param p_isOrdered Whether the sweep order decides [br]
## @param p_isReversed Sweeps from the left edge to the right instead [br]
## @return The impact positions as (x, y, height)
func _test_cake_slice(p_emitterId: int, p_origin: Vector2, p_direction: Vector2, p_radius: float,
		p_angle: float, p_hitYBand: Vector2, p_maxHits: int, p_hitData: R_HitData,
		p_isOrdered: bool, p_isReversed: bool) -> PackedVector3Array:
	_hitCount = 0
	
	var l_positions: PackedVector2Array = G_ChunkingServer._entityPosition
	var l_forward: Vector2 = p_direction.normalized()
	var l_halfAngle: float = p_angle * 0.5
	var l_rightEdge: Vector2 = p_origin + l_forward.rotated(l_halfAngle) * p_radius
	var l_leftEdge: Vector2 = p_origin + l_forward.rotated(-l_halfAngle) * p_radius
	
	for l_slot: int in _candidateCount:
		var l_id: int = _candidateIds[l_slot]
		var l_height: float = _get_sample_height(l_id, p_hitYBand)
		var l_radius: float = _get_effective_radius(l_id, l_height)
		var l_position: Vector2 = l_positions[l_id]
		var l_toTarget: Vector2 = l_position - p_origin
		var l_reach: float = p_radius + l_radius
		
		if (l_toTarget.length_squared() > l_reach * l_reach):
			continue
		
		var l_signedAngle: float = l_forward.angle_to(l_toTarget)
		if (not _touches_slice(l_position, l_radius, l_signedAngle, l_halfAngle, p_origin, l_rightEdge, l_leftEdge)):
			continue
		
		_push_hit(l_id, l_signedAngle if p_isReversed else -l_signedAngle,
			_get_impact_position(l_id, l_radius, l_height, p_origin))
	
	return _apply_hits(p_emitterId, p_maxHits, p_hitData, p_isOrdered)


## Appends one fresh slot to every column of this server. [br]
## Connected to G_ChunkingServer.s_entitySlotAppended, so ids of both servers always match. [br]
## @param p_id The id the slot is appended for
@warning_ignore("unused_parameter")
func _append_slot(p_id: int) -> void:
	_entityModules.append(null)
	_entityYBand.append(Vector2.ZERO)
	_entityHurtGroups.append(0)
	_entityHitGroups.append(0)
	_entityStopGroups.append(0)
	_entityCurveIndex.append(NO_CURVE)
	_entityVisitStamp.append(0)


## Clears one slot once its id is handed back, so a reused id inherits nothing. [br]
## Connected to G_ChunkingServer.s_entityReleased. [br]
## @param p_id The entity slot to reset
func _reset_slot(p_id: int) -> void:
	_entityModules[p_id] = null
	_entityYBand[p_id] = Vector2.ZERO
	_entityHurtGroups[p_id] = 0
	_entityHitGroups[p_id] = 0
	_entityStopGroups[p_id] = 0
	_entityVisitStamp[p_id] = 0
	_release_curve(p_id)


## Builds the fallback profile for entities registered without one, once. [br]
## @return The shared default profile
func _get_default_hit_profile() -> R_HitProfile:
	if (_defaultHitProfile == null):
		_defaultHitProfile = R_HitProfile.new()
	
	return _defaultHitProfile


## Takes a free curve slot or appends one, and remembers which curve sits in it. [br]
## @param p_curve The profile to store [br]
## @return The slot the curve was stored in
func _acquire_curve_slot(p_curve: Curve) -> int:
	p_curve.bake()
	
	var l_lastFreeIndex: int = _freeCurveIndices.size() - 1
	var l_curveIndex: int = 0
	
	if (l_lastFreeIndex >= 0):
		l_curveIndex = _freeCurveIndices[l_lastFreeIndex]
		_freeCurveIndices.resize(l_lastFreeIndex)
		_radiiCurves[l_curveIndex] = p_curve
	else:
		l_curveIndex = _radiiCurves.size()
		_radiiCurves.append(p_curve)
		_curveUsers.append(0)
		_curveSamples.resize(_radiiCurves.size() * CURVE_SAMPLE_COUNT)
	
	_curveUsers[l_curveIndex] = 0
	_curveSlotOf[p_curve] = l_curveIndex
	_bake_curve_samples(l_curveIndex, p_curve)
	
	return l_curveIndex


## Reads a curve into the flat sample block of its slot, once when the slot is taken. [br]
## @param p_curveIndex The slot to fill [br]
## @param p_curve The profile to read
func _bake_curve_samples(p_curveIndex: int, p_curve: Curve) -> void:
	var l_base: int = p_curveIndex * CURVE_SAMPLE_COUNT
	var l_lastSample: float = CURVE_SAMPLE_COUNT - 1
	
	for l_sample: int in CURVE_SAMPLE_COUNT:
		var l_percent: float = l_sample / l_lastSample * CURVE_PERCENT_MAX
		_curveSamples[l_base + l_sample] = p_curve.sample_baked(l_percent)


## Gives the curve slot of an entity back, and frees the slot once nobody uses it. [br]
## @param p_id The entity whose profile is dropped
func _release_curve(p_id: int) -> void:
	var l_curveIndex: int = _entityCurveIndex[p_id]
	
	if (l_curveIndex == NO_CURVE):
		return
	
	_entityCurveIndex[p_id] = NO_CURVE
	_curveUsers[l_curveIndex] -= 1
	
	if (_curveUsers[l_curveIndex] > 0):
		return
	
	_curveSlotOf.erase(_radiiCurves[l_curveIndex])
	_radiiCurves[l_curveIndex] = null
	_freeCurveIndices.append(l_curveIndex)


## Records one candidate in the reused buffer, growing it only when it is full. [br]
## @param p_id The entity worth testing against the shape
func _push_candidate(p_id: int) -> void:
	if (_candidateCount == _candidateIds.size()):
		_candidateIds.resize(maxi(_candidateCount * 2, BUFFER_MIN_CAPACITY))
	
	_candidateIds[_candidateCount] = p_id
	_candidateCount += 1


## Records one accepted target in the reused hit buffers, growing them only when they are full. [br]
## @param p_id The target the shape accepted [br]
## @param p_key Its sort key [br]
## @param p_position Its impact position as (x, y, height)
func _push_hit(p_id: int, p_key: float, p_position: Vector3) -> void:
	if (_hitCount == _hitIds.size()):
		var l_capacity: int = maxi(_hitCount * 2, BUFFER_MIN_CAPACITY)
		_hitIds.resize(l_capacity)
		_hitKeys.resize(l_capacity)
		_hitPositions.resize(l_capacity)
	
	_hitIds[_hitCount] = p_id
	_hitKeys[_hitCount] = p_key
	_hitPositions[_hitCount] = p_position
	_hitCount += 1


## Collects every entity of another team that a hit in this area could reach. [br]
## Skips empty columns and chunks, and stamps every entity so one is gathered exactly once. [br]
## @param p_emitterId The entity the hit comes from [br]
## @param p_minCorner Upper left corner of the shape bounds [br]
## @param p_maxCorner Lower right corner of the shape bounds [br]
## @param p_hitYBand Vertical extent of the hit
func _gather_chunk_candidates(p_emitterId: int, p_minCorner: Vector2, p_maxCorner: Vector2,
		p_hitYBand: Vector2) -> void:
	_candidateCount = 0
	_visitStamp += 1
	
	var l_area: Vector4i = G_ChunkingServer.compute_chunk_area_from_bounds(p_minCorner, p_maxCorner)
	var l_emitterTeam: int = G_ChunkingServer._entityTeam[p_emitterId]
	var l_stamp: int = _visitStamp
	var l_columns: int = MAP_CHUNK_COLUMNS
	var l_chunkHead: PackedInt32Array = G_ChunkingServer._chunkHead
	var l_slotEntity: PackedInt32Array = G_ChunkingServer._slotEntity
	var l_slotChunkNext: PackedInt32Array = G_ChunkingServer._slotChunkNext
	
	for l_column: int in range(l_area.x, l_area.z + 1):
		if (not G_ChunkingServer.has_opponent_in_column(l_column, l_emitterTeam)):
			continue
		
		for l_row: int in range(l_area.y, l_area.w + 1):
			var l_chunkId: int = l_row * l_columns + l_column
			
			if (not G_ChunkingServer.has_opponent_in_chunk(l_chunkId, l_emitterTeam)):
				continue
			
			var l_slot: int = l_chunkHead[l_chunkId]
			while (l_slot != NO_SLOT):
				var l_id: int = l_slotEntity[l_slot]
				l_slot = l_slotChunkNext[l_slot]
				
				if (_entityVisitStamp[l_id] == l_stamp):
					continue
				
				_entityVisitStamp[l_id] = l_stamp
				
				if (_can_be_hit(p_emitterId, l_id, p_hitYBand)):
					_push_candidate(l_id)


## Puts the preferred target into the candidate buffer as the only entry. [br]
## Warns once and falls back to a normal hit when a preference comes with more than one allowed hit. [br]
## @param p_emitterId The entity the hit comes from [br]
## @param p_preferredId The target to check first [br]
## @param p_maxHits Upper number of hits of this hit [br]
## @param p_hitYBand Vertical extent of the hit [br]
## @return true if the preferred target is worth testing on its own
func _gather_preferred_candidate(p_emitterId: int, p_preferredId: int, p_maxHits: int,
		p_hitYBand: Vector2) -> bool:
	_candidateCount = 0
	
	if (p_preferredId == NO_PREFERRED_TARGET):
		return false
	
	if (p_maxHits != 1):
		if (not _hasWarnedPreferredMisuse):
			_hasWarnedPreferredMisuse = true
			push_warning("G_HitServer: a preferred target is only used when p_maxHits is 1, ignoring it.")
		
		return false
	
	if (not _can_be_hit(p_emitterId, p_preferredId, p_hitYBand)):
		return false
	
	_push_candidate(p_preferredId)
	return true


## Checks everything about a target that does not depend on the hit shape. [br]
## @param p_emitterId The entity the hit comes from [br]
## @param p_targetId The entity to check [br]
## @param p_hitYBand Vertical extent of the hit [br]
## @return true if only the geometry is left to decide
func _can_be_hit(p_emitterId: int, p_targetId: int, p_hitYBand: Vector2) -> bool:
	if (G_ChunkingServer._entityTeam[p_targetId] == G_ChunkingServer._entityTeam[p_emitterId]):
		return false
	
	if (G_ChunkingServer._entityPreUnregistered[p_targetId] == 1 or G_ChunkingServer._entityUnregistering[p_targetId] == 1):
		return false
	
	if ((_entityHitGroups[p_emitterId] & _entityHurtGroups[p_targetId]) == 0):
		return false
	
	var l_band: Vector2 = _entityYBand[p_targetId]
	return p_hitYBand.x <= l_band.y and p_hitYBand.y >= l_band.x


## Picks the height a hit is measured at: the middle of the hit band, held inside the target. [br]
## @param p_id The entity that is hit [br]
## @param p_hitYBand Vertical extent of the hit [br]
## @return The height on the target the hit lands at
func _get_sample_height(p_id: int, p_hitYBand: Vector2) -> float:
	var l_band: Vector2 = _entityYBand[p_id]
	return clampf((p_hitYBand.x + p_hitYBand.y) * 0.5, l_band.x, l_band.y)


## Reads the radius a target offers at one height from the baked samples of its profile. [br]
## Entities without a profile keep their full radius over the whole height. [br]
## @param p_id The entity that is hit [br]
## @param p_sampleHeight The height the hit lands at [br]
## @return The radius that counts for this hit
func _get_effective_radius(p_id: int, p_sampleHeight: float) -> float:
	var l_radius: float = G_ChunkingServer._entityRadius[p_id]
	var l_curveIndex: int = _entityCurveIndex[p_id]
	
	if (l_curveIndex == NO_CURVE):
		return l_radius
	
	var l_band: Vector2 = _entityYBand[p_id]
	var l_height: float = l_band.y - l_band.x
	
	if (l_height <= 0.0):
		return l_radius
	
	var l_lastSample: int = CURVE_SAMPLE_COUNT - 1
	var l_position: float = clampf((p_sampleHeight - l_band.x) / l_height, 0.0, 1.0) * l_lastSample
	var l_sample: int = mini(int(l_position), l_lastSample - 1)
	var l_base: int = l_curveIndex * CURVE_SAMPLE_COUNT + l_sample
	var l_low: float = _curveSamples[l_base]
	var l_percent: float = l_low + (_curveSamples[l_base + 1] - l_low) * (l_position - l_sample)
	
	return l_radius * l_percent / CURVE_PERCENT_MAX


## Places the impact on the silhouette of the target, facing the origin of the hit. [br]
## @param p_id The entity that is hit [br]
## @param p_radius Its radius at the hit height [br]
## @param p_height The height the hit lands at [br]
## @param p_origin Where the hit comes from [br]
## @return The impact as (x, y, height)
func _get_impact_position(p_id: int, p_radius: float, p_height: float, p_origin: Vector2) -> Vector3:
	var l_position: Vector2 = G_ChunkingServer._entityPosition[p_id]
	var l_toOrigin: Vector2 = p_origin - l_position
	var l_distance: float = l_toOrigin.length()
	
	if (l_distance == 0.0):
		return Vector3(l_position.x, l_position.y, p_height)
	
	var l_impact: Vector2 = l_position + l_toOrigin / l_distance * minf(p_radius, l_distance)
	return Vector3(l_impact.x, l_impact.y, p_height)


## Checks a target against the opening angle and the two straight edges of a slice. [br]
## The tip is an endpoint of both edges, so the edge tests already cover it. [br]
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
## @param p_maxHits Upper number of hits, or C_HitServer.UNLIMITED_HITS [br]
## @param p_hitData Payload handed to every entity that is hit [br]
## @param p_isOrdered Whether the keys decide the order and the stop group applies [br]
## @return The impact positions of the hits that landed
func _apply_hits(p_emitterId: int, p_maxHits: int, p_hitData: R_HitData,
		p_isOrdered: bool) -> PackedVector3Array:
	var l_result: PackedVector3Array = PackedVector3Array()
	var l_limit: int = _hitCount
	
	if (p_maxHits != UNLIMITED_HITS):
		l_limit = mini(p_maxHits, _hitCount)
	
	if (l_limit <= 0):
		return l_result
	
	if (p_isOrdered and l_limit == 1):
		var l_nearest: int = _get_nearest_hit()
		l_result.append(_hitPositions[l_nearest])
		_dispatch_hit(_hitIds[l_nearest], p_hitData)
		
		return l_result
	
	if (not p_isOrdered):
		for l_index: int in l_limit:
			l_result.append(_hitPositions[l_index])
		
		for l_index: int in l_limit:
			_dispatch_hit(_hitIds[l_index], p_hitData)
		
		return l_result
	
	_build_hit_order()
	
	var l_stopGroups: int = _entityStopGroups[p_emitterId]
	var l_appliedCount: int = 0
	
	while (l_appliedCount < l_limit):
		var l_index: int = _hitOrder[l_appliedCount]
		l_result.append(_hitPositions[l_index])
		l_appliedCount += 1
		
		if ((l_stopGroups & _entityHurtGroups[_hitIds[l_index]]) != 0):
			break
	
	for l_slot: int in l_appliedCount:
		_dispatch_hit(_hitIds[_hitOrder[l_slot]], p_hitData)
	
	return l_result


## Hands one hit to the module management of its target, if the target has one. [br]
## @param p_id The entity that was hit [br]
## @param p_hitData The payload of the hit
func _dispatch_hit(p_id: int, p_hitData: R_HitData) -> void:
	var l_module: M_ModuleManager = _entityModules[p_id]
	
	if (l_module != null):
		l_module.hit(p_hitData)


## Finds the hit with the smallest key, for ordered hits that land exactly once. [br]
## @return The index of the first hit in key order
func _get_nearest_hit() -> int:
	var l_nearest: int = 0
	
	for l_index: int in range(1, _hitCount):
		if (_hitKeys[l_index] < _hitKeys[l_nearest]):
			l_nearest = l_index
	
	return l_nearest


## Fills _hitOrder with the hit indices sorted ascending by key. [br]
## Insertion sort; only an area hit accepting dozens of targets reaches its quadratic case.
func _build_hit_order() -> void:
	if (_hitOrder.size() < _hitCount):
		_hitOrder.resize(_hitCount)
	
	for l_index: int in _hitCount:
		var l_key: float = _hitKeys[l_index]
		var l_insertAt: int = l_index
		
		while (l_insertAt > 0 and _hitKeys[_hitOrder[l_insertAt - 1]] > l_key):
			_hitOrder[l_insertAt] = _hitOrder[l_insertAt - 1]
			l_insertAt -= 1
		
		_hitOrder[l_insertAt] = l_index

#endregion

extends Node
## Autoload that picks and holds a target per entity and reports where it should move. [br]
## Searches are chunk counted and event driven: a target is only ever lost, never re-checked.

#region CACHED_VARS

## Cached C_ChunkingServer.MAP_CHUNK_COLUMNS; the ring scan reads it constantly.
var MAP_CHUNK_COLUMNS: int

## Cached C_ChunkingServer.MAP_CHUNK_ROWS.
var MAP_CHUNK_ROWS: int

## Cached C_ChunkingServer.NO_ENTITY.
var NO_ENTITY: int

## Cached C_TargetingServer.NO_TARGET.
var NO_TARGET: int

## Cached C_TargetingServer.FLAG_INVISIBLE.
var FLAG_INVISIBLE: int

## Cached C_TargetingServer.FLAG_TARGETS_INVISIBLE.
var FLAG_TARGETS_INVISIBLE: int

## Cached C_TargetingServer.FLAG_HAS_FOCUS.
var FLAG_HAS_FOCUS: int

## Cached C_TargetingServer.FLAG_IGNORES_FOCUS.
var FLAG_IGNORES_FOCUS: int

## Cached C_TargetingServer.BASE_REACHED_EPSILON.
var BASE_REACHED_EPSILON: float

## Cached C_TargetingServer.DIAGONAL_CHUNK_COST.
var DIAGONAL_CHUNK_COST: float

## Cached C_TargetingServer.TEAM_BASE_X.
var TEAM_BASE_X: PackedFloat32Array

## Cached C_TargetingServer.TEAM_MARCH_X.
var TEAM_MARCH_X: PackedFloat32Array

## Cached C_TargetingServer.TEAM_FORWARD_SIGN.
var TEAM_FORWARD_SIGN: PackedInt32Array

## Cached C_TargetingServer.WEIGHT_CLOSENESS.
var WEIGHT_CLOSENESS: float

## Cached C_TargetingServer.WEIGHT_FOCUS.
var WEIGHT_FOCUS: float

## Cached C_TargetingServer.WEIGHT_BEHIND.
var WEIGHT_BEHIND: float

## Cached C_TargetingServer.WEIGHT_CROWDING.
var WEIGHT_CROWDING: float

## Cached C_TargetingServer.WEIGHT_MUTUAL.
var WEIGHT_MUTUAL: float

#endregion

#region EXPORTS_AND_VARS

## Bitmask of the groups an entity may go after.
var _entityTargetedGroups: PackedInt64Array = PackedInt64Array()

## Current C_TargetingServer.STATE per entity.
var _entityState: PackedByteArray = PackedByteArray()

## How many chunks in each direction a search of this entity covers.
var _entitySearchChunks: PackedInt32Array = PackedInt32Array()

## A targeter closer than this many chunks makes the entity flee.
var _entityFleeChunks: PackedInt32Array = PackedInt32Array()

## Real distance at which approaching turns into combat, measured to the edge of the target.
var _entityHitRange: PackedFloat32Array = PackedFloat32Array()

## Bitmask of the groups an entity goes after before it considers the normal ones.
var _entityPriorityTargetedGroups: PackedInt64Array = PackedInt64Array()

## Invisibility and focus flags of an entity, as C_TargetingServer.FLAG bits.
var _entityFlags: PackedByteArray = PackedByteArray()

## Target of an entity, or C_TargetingServer.NO_TARGET.
var _entityTarget: PackedInt32Array = PackedInt32Array()

## Own slot inside the targeter list of the target; makes dropping a target O(1).
var _entityTargeterIndex: PackedInt32Array = PackedInt32Array()

## Ids that currently target this entity; its size is the crowding count.
var _targetersOf: Array[PackedInt32Array] = []

# State of the running search, hoisted out of the candidate loop because none of it changes there.
# Only meaningful while _find_best_target() runs.

## The entity the running search belongs to.
var _searchId: int = C_TargetingServer.NO_TARGET

## Team of the searcher, a C_ChunkingServer.TEAM value.
var _searchTeam: int = 0

## Column of the center chunk of the searcher.
var _searchColumn: int = 0

## Row of the center chunk of the searcher.
var _searchRow: int = 0

## Flags of the searcher, as C_TargetingServer.FLAG bits.
var _searchFlags: int = 0

## How many chunks in each direction the running search covers.
var _searchReach: int = 0

## Direction the searcher marches in along x; decides what counts as behind it.
var _searchForwardSign: int = 1

## Every group the searcher accepts, priority ones included.
var _searchGroups: int = 0

## Groups the searcher goes after before it considers the normal ones.
var _searchPriorityGroups: int = 0

## Best priority candidate so far, or C_TargetingServer.NO_TARGET.
var _searchBestPriorityId: int = C_TargetingServer.NO_TARGET

## Score of the best priority candidate so far.
var _searchBestPriorityScore: float = 0.0

## Best normal candidate so far, or C_TargetingServer.NO_TARGET.
var _searchBestNormalId: int = C_TargetingServer.NO_TARGET

## Score of the best normal candidate so far.
var _searchBestNormalScore: float = 0.0

#endregion

#region LIFECYCLE_AND_METHODS

## Follows the id lifecycle of the ChunkingServer autoload, which is loaded before this one. [br]
## Runs before any entity can register, so every id the index hands out gets a slot here.
func _ready() -> void:
	ChunkingServer.s_entitySlotAppended.connect(_append_slot)
	ChunkingServer.s_entityPreUnregistered.connect(drop_targeters)
	ChunkingServer.s_entityUnregistered.connect(_unlink_entity)
	ChunkingServer.s_entityReleased.connect(_reset_slot)
	
	MAP_CHUNK_COLUMNS = C_ChunkingServer.MAP_CHUNK_COLUMNS
	MAP_CHUNK_ROWS = C_ChunkingServer.MAP_CHUNK_ROWS
	NO_ENTITY = C_ChunkingServer.NO_ENTITY
	NO_TARGET = C_TargetingServer.NO_TARGET
	FLAG_INVISIBLE = C_TargetingServer.FLAG_INVISIBLE
	FLAG_TARGETS_INVISIBLE = C_TargetingServer.FLAG_TARGETS_INVISIBLE
	FLAG_HAS_FOCUS = C_TargetingServer.FLAG_HAS_FOCUS
	FLAG_IGNORES_FOCUS = C_TargetingServer.FLAG_IGNORES_FOCUS
	BASE_REACHED_EPSILON = C_TargetingServer.BASE_REACHED_EPSILON
	DIAGONAL_CHUNK_COST = C_TargetingServer.DIAGONAL_CHUNK_COST
	TEAM_BASE_X = C_TargetingServer.TEAM_BASE_X
	TEAM_MARCH_X = C_TargetingServer.TEAM_MARCH_X
	TEAM_FORWARD_SIGN = C_TargetingServer.TEAM_FORWARD_SIGN
	WEIGHT_CLOSENESS = C_TargetingServer.WEIGHT_CLOSENESS
	WEIGHT_FOCUS = C_TargetingServer.WEIGHT_FOCUS
	WEIGHT_BEHIND = C_TargetingServer.WEIGHT_BEHIND
	WEIGHT_CROWDING = C_TargetingServer.WEIGHT_CROWDING
	WEIGHT_MUTUAL = C_TargetingServer.WEIGHT_MUTUAL


## Gives an entity its targeting side; without it the entity never searches or picks a target. [br]
## @param p_id The id ChunkingServer.register_entity() returned [br]
## @param p_targetingData Groups, ranges and flags of the entity
func register(p_id: int, p_targetingData: R_TargetingData) -> void:
	var l_targetingData: R_TargetingData = p_targetingData
	
	if (l_targetingData == null):
		push_error("TargetingServer: entity %d was registered without targeting data, using the defaults." % p_id)
		l_targetingData = R_TargetingData.new()
	
	_entityTargetedGroups[p_id] = l_targetingData.targetedGroups
	_entitySearchChunks[p_id] = l_targetingData.searchChunks
	_entityFleeChunks[p_id] = l_targetingData.fleeChunks
	_entityHitRange[p_id] = l_targetingData.hitRange
	_entityPriorityTargetedGroups[p_id] = l_targetingData.priorityTargetedGroups
	_entityFlags[p_id] = _build_flags(l_targetingData)


## Advances the state of one entity; cheap enough to run every tick. [br]
## Never searches — the entity asks for that itself through search_target(). [br]
## @param p_id The entity to advance [br]
## @return Its new C_TargetingServer.STATE
func update_entity(p_id: int) -> int:
	if (_can_still_flee(p_id) and _is_threatened(p_id)):
		_drop_target(p_id)
		_entityState[p_id] = C_TargetingServer.STATE.FLEE
		
		return C_TargetingServer.STATE.FLEE
	
	var l_state: int = _evaluate_state(p_id)
	_entityState[p_id] = l_state
	
	return l_state


## Scans the search area of an entity and gives it the best scoring target. [br]
## @param p_id The entity that searches [br]
## @return The target it got, or C_TargetingServer.NO_TARGET
func search_target(p_id: int) -> int:
	var l_targetId: int = _find_best_target(p_id)
	
	if (l_targetId != NO_TARGET):
		_assign_target(p_id, l_targetId)
	
	return l_targetId


## Makes every entity that targets this one drop it and look for something else. [br]
## Also runs on ChunkingServer.s_entityPreUnregistered, so an announced entity is let go at once. [br]
## @param p_id The entity that is no longer worth targeting
func drop_targeters(p_id: int) -> void:
	var l_targeters: PackedInt32Array = _targetersOf[p_id].duplicate()
	
	for l_targeterId: int in l_targeters:
		_drop_target(l_targeterId)


## Hides an entity from searchers, or reveals it again. [br]
## Hiding drops every targeter that cannot see invisible entities. [br]
## @param p_id The entity to change [br]
## @param p_isInvisible Whether it becomes invisible
func set_invisible(p_id: int, p_isInvisible: bool) -> void:
	_set_flag(p_id, FLAG_INVISIBLE, p_isInvisible)
	
	if (not p_isInvisible):
		return
	
	var l_targeters: PackedInt32Array = _targetersOf[p_id].duplicate()
	for l_targeterId: int in l_targeters:
		if ((_entityFlags[l_targeterId] & FLAG_TARGETS_INVISIBLE) == 0):
			_drop_target(l_targeterId)


## Sets whether an entity can see invisible enemies. [br]
## @param p_id The entity to change [br]
## @param p_isEnabled Whether it sees them
func set_targets_invisible(p_id: int, p_isEnabled: bool) -> void:
	_set_flag(p_id, FLAG_TARGETS_INVISIBLE, p_isEnabled)


## Sets whether an entity is a focus target other entities prefer. [br]
## @param p_id The entity to change [br]
## @param p_isEnabled Whether it carries focus
func set_focused(p_id: int, p_isEnabled: bool) -> void:
	_set_flag(p_id, FLAG_HAS_FOCUS, p_isEnabled)


## Sets whether an entity scores candidates without the focus bonus. [br]
## @param p_id The entity to change [br]
## @param p_isEnabled Whether it ignores focus
func set_ignores_focus(p_id: int, p_isEnabled: bool) -> void:
	_set_flag(p_id, FLAG_IGNORES_FOCUS, p_isEnabled)


## Sets how far a search of this entity reaches. [br]
## @param p_id The entity to change [br]
## @param p_searchChunks Reach in chunks per direction
func set_search_chunks(p_id: int, p_searchChunks: int) -> void:
	_entitySearchChunks[p_id] = p_searchChunks


## Sets how close a targeter has to come before the entity flees. [br]
## @param p_id The entity to change [br]
## @param p_fleeChunks Threat distance in chunks
func set_flee_chunks(p_id: int, p_fleeChunks: int) -> void:
	_entityFleeChunks[p_id] = p_fleeChunks


## Sets the real distance at which the entity enters combat. [br]
## Measured to the edge of the target, so the radius of the target is added on top. [br]
## @param p_id The entity to change [br]
## @param p_hitRange The distance to the silhouette of the target
func set_hit_range(p_id: int, p_hitRange: float) -> void:
	_entityHitRange[p_id] = p_hitRange


## Sets the groups the entity goes after before it considers the normal ones. [br]
## @param p_id The entity to change [br]
## @param p_priorityTargetedGroups Bitmask of the preferred groups
func set_priority_targeted_groups(p_id: int, p_priorityTargetedGroups: int) -> void:
	_entityPriorityTargetedGroups[p_id] = p_priorityTargetedGroups


## Returns where the entity should move this tick. [br]
## Fleeing and marching aim at a fixed x of the map, fighting aims at the target itself. [br]
## @param p_id The entity to move [br]
## @return The position the movement should head for
func get_target_position(p_id: int) -> Vector2:
	var l_team: int = ChunkingServer._entityTeam[p_id]
	var l_ownY: float = ChunkingServer._entityPosition[p_id].y
	
	if (_entityState[p_id] == C_TargetingServer.STATE.FLEE):
		return Vector2(TEAM_BASE_X[l_team], l_ownY)
	
	var l_targetId: int = _entityTarget[p_id]
	if (l_targetId != NO_TARGET):
		return ChunkingServer._entityPosition[l_targetId]
	
	if (_has_enemy_behind(p_id) or not _has_opponent_on_map(p_id)):
		return Vector2(TEAM_BASE_X[l_team], l_ownY)
	
	return Vector2(TEAM_MARCH_X[l_team], l_ownY)


## Returns the current state of an entity. [br]
## @param p_id The entity to read [br]
## @return Its C_TargetingServer.STATE
func get_state(p_id: int) -> int:
	return _entityState[p_id]


## Returns the target of an entity. [br]
## @param p_id The entity to read [br]
## @return Its target, or C_TargetingServer.NO_TARGET
func get_target(p_id: int) -> int:
	return _entityTarget[p_id]


## Returns everyone targeting an entity as a snapshot of the moment it is asked. [br]
## Packed arrays copy on write, so the result never follows later changes and editing it changes nothing. [br]
## @param p_id The entity to read [br]
## @return The ids currently targeting it
func get_targeters(p_id: int) -> PackedInt32Array:
	return _targetersOf[p_id]


## Unlinks a removed entity from both sides of the targeting graph. [br]
## Connected to ChunkingServer.s_entityUnregistered. [br]
## @param p_id The entity that was removed
func _unlink_entity(p_id: int) -> void:
	_drop_target(p_id)
	drop_targeters(p_id)


## Appends one fresh slot to every column of this server. [br]
## Connected to ChunkingServer.s_entitySlotAppended, so ids of both servers always match. [br]
## @param p_id The id the slot is appended for
@warning_ignore("unused_parameter")
func _append_slot(p_id: int) -> void:
	_entityTargetedGroups.append(0)
	_entityState.append(C_TargetingServer.STATE.SEARCH)
	_entitySearchChunks.append(0)
	_entityFleeChunks.append(0)
	_entityHitRange.append(0.0)
	_entityPriorityTargetedGroups.append(0)
	_entityFlags.append(0)
	_entityTarget.append(NO_TARGET)
	_entityTargeterIndex.append(0)
	_targetersOf.append(PackedInt32Array())


## Clears one slot once its id is handed back, so a reused id inherits no target or flag. [br]
## Connected to ChunkingServer.s_entityReleased. [br]
## @param p_id The entity slot to reset
func _reset_slot(p_id: int) -> void:
	_entityTargetedGroups[p_id] = 0
	_entityState[p_id] = C_TargetingServer.STATE.SEARCH
	_entitySearchChunks[p_id] = 0
	_entityFleeChunks[p_id] = 0
	_entityHitRange[p_id] = 0.0
	_entityPriorityTargetedGroups[p_id] = 0
	_entityFlags[p_id] = 0
	_entityTarget[p_id] = NO_TARGET
	_entityTargeterIndex[p_id] = 0
	_targetersOf[p_id] = PackedInt32Array()


## Packs the flag booleans of a targeting setup into one byte. [br]
## @param p_targetingData The setup to read [br]
## @return The packed flags
func _build_flags(p_targetingData: R_TargetingData) -> int:
	var l_flags: int = 0
	
	if (p_targetingData.isInvisible):
		l_flags |= FLAG_INVISIBLE
	
	if (p_targetingData.canTargetInvisible):
		l_flags |= FLAG_TARGETS_INVISIBLE
	
	if (p_targetingData.hasFocus):
		l_flags |= FLAG_HAS_FOCUS
	
	if (p_targetingData.isIgnoringFocus):
		l_flags |= FLAG_IGNORES_FOCUS
	
	return l_flags


## Switches one flag of an entity on or off. [br]
## @param p_id The entity to change [br]
## @param p_flag The C_TargetingServer.FLAG bit [br]
## @param p_isEnabled Whether the bit is set
func _set_flag(p_id: int, p_flag: int, p_isEnabled: bool) -> void:
	if (p_isEnabled):
		_entityFlags[p_id] |= p_flag
	else:
		_entityFlags[p_id] &= ~p_flag


## Decides what an entity is doing right now, without changing anything about it. [br]
## Fleeing is decided by the caller, because it has to drop the target first. [br]
## @param p_id The entity to judge [br]
## @return Its C_TargetingServer.STATE
func _evaluate_state(p_id: int) -> int:
	var l_targetId: int = _entityTarget[p_id]
	
	if (l_targetId == NO_TARGET):
		return C_TargetingServer.STATE.SEARCH
	
	var l_squaredDistance: float = ChunkingServer._entityPosition[p_id].distance_squared_to(ChunkingServer._entityPosition[l_targetId])
	var l_reach: float = _entityHitRange[p_id] + ChunkingServer._entityRadius[l_targetId]
	
	if (l_squaredDistance <= l_reach * l_reach):
		return C_TargetingServer.STATE.COMBAT
	
	return C_TargetingServer.STATE.APPROACH


## Checks whether the entity is still away from its own base and may keep fleeing. [br]
## @param p_id The entity to check [br]
## @return true while it has not reached its own side
func _can_still_flee(p_id: int) -> bool:
	var l_baseX: float = TEAM_BASE_X[ChunkingServer._entityTeam[p_id]]
	return absf(ChunkingServer._entityPosition[p_id].x - l_baseX) > BASE_REACHED_EPSILON


## Checks whether any entity targeting this one is inside its flee distance. [br]
## @param p_id The entity to check [br]
## @return true if it should run
func _is_threatened(p_id: int) -> bool:
	var l_fleeChunks: int = _entityFleeChunks[p_id]
	var l_column: int = ChunkingServer._entityCenterColumn[p_id]
	var l_row: int = ChunkingServer._entityCenterRow[p_id]
	
	for l_targeterId: int in _targetersOf[p_id]:
		if (_get_chunk_distance(l_column, l_row, l_targeterId) <= l_fleeChunks):
			return true
	
	return false


## Scans the search area ring by ring and keeps the best priority and the best normal candidate. [br]
## Stops as soon as no further ring can beat what was already found. [br]
## @param p_id The entity that searches [br]
## @return The best target, or C_TargetingServer.NO_TARGET
func _find_best_target(p_id: int) -> int:
	var l_priorityGroups: int = _entityPriorityTargetedGroups[p_id]
	var l_searchedGroups: int = l_priorityGroups | _entityTargetedGroups[p_id]
	var l_team: int = ChunkingServer._entityTeam[p_id]
	
	if (not ChunkingServer.map_has_opponent_group(l_team, l_searchedGroups)):
		return NO_TARGET
	
	_searchId = p_id
	_searchTeam = l_team
	_searchColumn = ChunkingServer._entityCenterColumn[p_id]
	_searchRow = ChunkingServer._entityCenterRow[p_id]
	_searchFlags = _entityFlags[p_id]
	_searchReach = _entitySearchChunks[p_id]
	_searchForwardSign = TEAM_FORWARD_SIGN[l_team]
	_searchGroups = l_searchedGroups
	_searchPriorityGroups = l_priorityGroups
	_searchBestPriorityId = NO_TARGET
	_searchBestPriorityScore = 0.0
	_searchBestNormalId = NO_TARGET
	_searchBestNormalScore = 0.0
	
	var l_isPriorityPossible: bool = l_priorityGroups != 0 \
		and ChunkingServer.map_has_opponent_group(l_team, l_priorityGroups)
	var l_maxBonus: float = _get_max_score_bonus()
	
	for l_ring: int in range(0, _searchReach + 1):
		if (_is_search_settled(l_ring, l_maxBonus, l_isPriorityPossible)):
			break
		
		_scan_ring(l_ring)
	
	if (_searchBestPriorityId != NO_TARGET):
		return _searchBestPriorityId
	
	return _searchBestNormalId


## Sums up every bonus a candidate of the running search could possibly score. [br]
## Crowding only ever subtracts, so leaving it out keeps the sum an upper bound. [br]
## @return The largest bonus any candidate can add on top of its closeness
func _get_max_score_bonus() -> float:
	var l_bonus: float = WEIGHT_BEHIND + WEIGHT_MUTUAL
	
	if ((_searchFlags & FLAG_IGNORES_FOCUS) == 0):
		l_bonus += WEIGHT_FOCUS
	
	return l_bonus


## Checks whether no ring from here outwards could still beat what the search already holds. [br]
## A chunk of ring r is at least r steps away, so its closeness can never top the bound. [br]
## @param p_ring The ring that would be scanned next [br]
## @param p_maxBonus The largest bonus a candidate can score on top of its closeness [br]
## @param p_isPriorityPossible Whether a priority target exists on the map at all [br]
## @return true if the search can stop here
func _is_search_settled(p_ring: int, p_maxBonus: float, p_isPriorityPossible: bool) -> bool:
	var l_bound: float = (_searchReach - p_ring) * WEIGHT_CLOSENESS + p_maxBonus
	
	if (_searchBestPriorityId != NO_TARGET):
		return _searchBestPriorityScore >= l_bound
	
	if (p_isPriorityPossible):
		return false
	
	return _searchBestNormalId != NO_TARGET and _searchBestNormalScore >= l_bound


## Scans every chunk at exactly one ring distance around the searcher. [br]
## Walks the ring column by column so one column that holds nothing skips all its chunks at once. [br]
## @param p_ring The ring distance to scan, 0 being the chunk of the searcher itself
func _scan_ring(p_ring: int) -> void:
	var l_leftColumn: int = _searchColumn - p_ring
	var l_rightColumn: int = _searchColumn + p_ring
	var l_topRow: int = _searchRow - p_ring
	var l_bottomRow: int = _searchRow + p_ring
	var l_firstRow: int = maxi(l_topRow, 0)
	var l_lastRow: int = mini(l_bottomRow, MAP_CHUNK_ROWS - 1)
	
	for l_column: int in range(maxi(l_leftColumn, 0), mini(l_rightColumn, MAP_CHUNK_COLUMNS - 1) + 1):
		if (not ChunkingServer.column_has_opponent_group(l_column, _searchTeam, _searchGroups)):
			continue
		
		if (l_column == l_leftColumn or l_column == l_rightColumn):
			for l_row: int in range(l_firstRow, l_lastRow + 1):
				_scan_chunk(l_row * MAP_CHUNK_COLUMNS + l_column)
			
			continue
		
		if (l_topRow >= 0):
			_scan_chunk(l_topRow * MAP_CHUNK_COLUMNS + l_column)
		
		if (l_bottomRow < MAP_CHUNK_ROWS):
			_scan_chunk(l_bottomRow * MAP_CHUNK_COLUMNS + l_column)


## Scores every center that sits in one chunk and keeps the best of each category. [br]
## Only centers hang in this chain, so an entity spanning several chunks is still seen exactly once. [br]
## @param p_chunkId The chunk to open
func _scan_chunk(p_chunkId: int) -> void:
	if (not ChunkingServer.chunk_has_opponent_group(p_chunkId, _searchTeam, _searchGroups)):
		return
	
	var l_candidateId: int = ChunkingServer._centerHead[p_chunkId]
	while (l_candidateId != NO_ENTITY):
		var l_nextId: int = ChunkingServer._centerNext[l_candidateId]
		
		if (not _can_target(l_candidateId)):
			l_candidateId = l_nextId
			continue
		
		var l_score: float = _score_candidate(l_candidateId)
		
		if ((ChunkingServer._entityGroups[l_candidateId] & _searchPriorityGroups) != 0):
			if (_is_better(l_score, l_candidateId, _searchBestPriorityScore, _searchBestPriorityId)):
				_searchBestPriorityScore = l_score
				_searchBestPriorityId = l_candidateId
		elif (_is_better(l_score, l_candidateId, _searchBestNormalScore, _searchBestNormalId)):
			_searchBestNormalScore = l_score
			_searchBestNormalId = l_candidateId
		
		l_candidateId = l_nextId


## Compares a candidate against the best one so far, the lower id winning a tie. [br]
## Without the id the winner of a tie would depend on the order chunks happen to be stored in. [br]
## @param p_score Score of the candidate [br]
## @param p_candidateId The candidate itself [br]
## @param p_bestScore Score of the best candidate so far [br]
## @param p_bestId The best candidate so far, or C_TargetingServer.NO_TARGET [br]
## @return true if the candidate takes the lead
func _is_better(p_score: float, p_candidateId: int, p_bestScore: float, p_bestId: int) -> bool:
	if (p_bestId == NO_TARGET or p_score > p_bestScore):
		return true
	
	return p_score == p_bestScore and p_candidateId < p_bestId


## Checks everything about a candidate of the running search that does not depend on the score. [br]
## @param p_candidateId The entity to check [br]
## @return true if the candidate is worth scoring
func _can_target(p_candidateId: int) -> bool:
	if (ChunkingServer._entityTeam[p_candidateId] == _searchTeam):
		return false
	
	if (ChunkingServer._entityPreUnregistered[p_candidateId] == 1 or ChunkingServer._entityUnregistering[p_candidateId] == 1):
		return false
	
	if ((ChunkingServer._entityGroups[p_candidateId] & _searchGroups) == 0):
		return false
	
	return (_entityFlags[p_candidateId] & FLAG_INVISIBLE) == 0 \
		or (_searchFlags & FLAG_TARGETS_INVISIBLE) != 0


## Weighs a candidate of the running search; every term is a comparison, a bit test or an array size. [br]
## @param p_candidateId The candidate to weigh [br]
## @return Its score, higher is better
func _score_candidate(p_candidateId: int) -> float:
	var l_distance: float = _get_chunk_distance(_searchColumn, _searchRow, p_candidateId)
	var l_score: float = (_searchReach - l_distance) * WEIGHT_CLOSENESS
	
	if ((_entityFlags[p_candidateId] & FLAG_HAS_FOCUS) != 0 \
			and (_searchFlags & FLAG_IGNORES_FOCUS) == 0):
		l_score += WEIGHT_FOCUS
	
	if ((ChunkingServer._entityCenterColumn[p_candidateId] - _searchColumn) * _searchForwardSign < 0):
		l_score += WEIGHT_BEHIND
	
	if (_entityTarget[p_candidateId] == _searchId):
		l_score += WEIGHT_MUTUAL
	
	return l_score - _targetersOf[p_candidateId].size() * WEIGHT_CROWDING


## Measures the distance from a center chunk to the center chunk of an entity, in chunk steps. [br]
## @param p_column Column of the chunk to measure from [br]
## @param p_row Row of the chunk to measure from [br]
## @param p_otherId The entity to measure to [br]
## @return The steps, diagonals counted as C_TargetingServer.DIAGONAL_CHUNK_COST
func _get_chunk_distance(p_column: int, p_row: int, p_otherId: int) -> float:
	var l_columnDelta: int = absi(ChunkingServer._entityCenterColumn[p_otherId] - p_column)
	var l_rowDelta: int = absi(ChunkingServer._entityCenterRow[p_otherId] - p_row)
	var l_diagonal: int = mini(l_columnDelta, l_rowDelta)
	var l_straight: int = maxi(l_columnDelta, l_rowDelta) - l_diagonal
	
	return l_straight + l_diagonal * DIAGONAL_CHUNK_COST


## Checks whether anything hostile got past an entity, counting invisible ones too. [br]
## Reads the outermost column each team occupies, so the width of the map never enters the cost. [br]
## @param p_id The entity to check [br]
## @return true if an opponent stands behind it
func _has_enemy_behind(p_id: int) -> bool:
	var l_team: int = ChunkingServer._entityTeam[p_id]
	var l_column: int = ChunkingServer._entityCenterColumn[p_id]
	
	if (TEAM_FORWARD_SIGN[l_team] > 0):
		return ChunkingServer.has_opponent_before_column(l_column, l_team)
	
	return ChunkingServer.has_opponent_after_column(l_column, l_team)


## Checks whether anything the entity may go after exists anywhere on the map. [br]
## @param p_id The entity that asks [br]
## @return true if a search could find something
func _has_opponent_on_map(p_id: int) -> bool:
	var l_searchedGroups: int = _entityPriorityTargetedGroups[p_id] | _entityTargetedGroups[p_id]
	return ChunkingServer.map_has_opponent_group(ChunkingServer._entityTeam[p_id], l_searchedGroups)


## Links an entity to a target and records its slot in the targeter list. [br]
## @param p_id The entity that targets [br]
## @param p_targetId The entity it targets
func _assign_target(p_id: int, p_targetId: int) -> void:
	_drop_target(p_id)
	
	var l_targeters: PackedInt32Array = _targetersOf[p_targetId]
	_entityTargeterIndex[p_id] = l_targeters.size()
	l_targeters.append(p_id)
	_targetersOf[p_targetId] = l_targeters
	_entityTarget[p_id] = p_targetId


## Unlinks an entity from its target by swap-and-pop and sends it back to searching. [br]
## @param p_id The entity that gives up its target
func _drop_target(p_id: int) -> void:
	var l_targetId: int = _entityTarget[p_id]
	
	if (l_targetId == NO_TARGET):
		return
	
	var l_targeters: PackedInt32Array = _targetersOf[l_targetId]
	var l_slot: int = _entityTargeterIndex[p_id]
	var l_lastSlot: int = l_targeters.size() - 1
	var l_movedId: int = l_targeters[l_lastSlot]
	
	l_targeters[l_slot] = l_movedId
	l_targeters.resize(l_lastSlot)
	_targetersOf[l_targetId] = l_targeters
	_entityTargeterIndex[l_movedId] = l_slot
	
	_entityTarget[p_id] = NO_TARGET
	_entityState[p_id] = C_TargetingServer.STATE.SEARCH

#endregion

extends RefCounted
class_name HitGD
## GDScript mirror of the hit kernel in hit_core.h, in the hoisted and inlined style. [br]
## So the comparison against C++ is against competent GDScript, not naive GDScript.

#region ENUMS_AND_CONSTANTS

## Chunks per row.
const COLS: int = 32

## Chunk rows.
const ROWS: int = 32

## Edge length of one chunk.
const CHUNK: float = 128.0

## Radii handed out in turn.
const RADII: Array[float] = [12.0, 24.0, 40.0, 90.0]

## Reach of a single target hit.
const SINGLE_R: float = 64.0

## Reach of a capped area hit.
const CAPPED_R: float = 128.0

## Reach of an uncapped blast.
const BLAST_R: float = 192.0

## Hit limit of a capped area hit.
const CAPPED_MAX: int = 5

#endregion

#region EXPORTS_AND_VARS

## State of the xorshift generator every port seeds identically.
var _randomState: int = 12345

## Number of entities in the built world.
var _entityCount: int = 0

## Team per entity.
var _entityTeam: PackedByteArray = PackedByteArray()

## X position per entity.
var _entityX: PackedFloat64Array = PackedFloat64Array()

## Y position per entity.
var _entityY: PackedFloat64Array = PackedFloat64Array()

## Radius per entity.
var _entityRadius: PackedFloat64Array = PackedFloat64Array()

## First membership slot of every chunk, or -1.
var _chunkHead: PackedInt32Array = PackedInt32Array()

## Entity every membership slot belongs to.
var _slotEntity: PackedInt32Array = PackedInt32Array()

## Next membership slot inside the chain of the same chunk, or -1.
var _slotNext: PackedInt32Array = PackedInt32Array()

## Hit that last looked at an entity; dedups entities standing in several chunks.
var _entityVisitStamp: PackedInt32Array = PackedInt32Array()

## Stamp of the running hit.
var _visitStamp: int = 0

## Candidates the running hit accepted.
var _candidateIds: PackedInt32Array = PackedInt32Array()

## Squared distance of every candidate, parallel to _candidateIds.
var _candidateKeys: PackedFloat64Array = PackedFloat64Array()

## Candidate indices sorted ascending by key, for ordered hits.
var _candidateOrder: PackedInt32Array = PackedInt32Array()

#endregion

#region LIFECYCLE_AND_METHODS

## Advances the xorshift generator shared by every port. [br]
## @return The next value in [0, 1)
func _rand01() -> float:
	_randomState ^= (_randomState << 13) & 0xFFFFFFFF
	_randomState ^= (_randomState >> 17)
	_randomState ^= (_randomState << 5) & 0xFFFFFFFF
	_randomState &= 0xFFFFFFFF
	return float(_randomState >> 8) / 16777216.0


## Builds two fronts and links every entity into each chunk its radius touches. [br]
## @param p_entityCount How many entities to place
func build(p_entityCount: int) -> void:
	_entityCount = p_entityCount
	_randomState = 12345
	_entityTeam.resize(p_entityCount)
	_entityX.resize(p_entityCount)
	_entityY.resize(p_entityCount)
	_entityRadius.resize(p_entityCount)
	_entityVisitStamp.resize(p_entityCount)
	_entityVisitStamp.fill(0)
	_visitStamp = 0
	_chunkHead.resize(COLS * ROWS)
	_chunkHead.fill(-1)
	_slotEntity.clear()
	_slotNext.clear()

	for l_index: int in p_entityCount:
		var l_team: int = l_index % 2
		var l_frontX: float = 4096.0 * (0.35 if l_team == 0 else 0.65)
		var l_x: float = clampf(l_frontX + (_rand01() - 0.5) * 2.0 * 655.36, 0.0, 4095.0)
		var l_y: float = clampf(_rand01() * 4096.0, 0.0, 4095.0)
		_entityTeam[l_index] = l_team
		_entityX[l_index] = l_x
		_entityY[l_index] = l_y

		var l_radius: float = RADII[l_index % 4]
		_entityRadius[l_index] = l_radius

		var l_firstColumn: int = clampi(int(floor((l_x - l_radius) / CHUNK)), 0, COLS - 1)
		var l_lastColumn: int = clampi(int(floor((l_x + l_radius) / CHUNK)), 0, COLS - 1)
		var l_firstRow: int = clampi(int(floor((l_y - l_radius) / CHUNK)), 0, ROWS - 1)
		var l_lastRow: int = clampi(int(floor((l_y + l_radius) / CHUNK)), 0, ROWS - 1)

		for l_row: int in range(l_firstRow, l_lastRow + 1):
			for l_column: int in range(l_firstColumn, l_lastColumn + 1):
				var l_chunkId: int = l_row * COLS + l_column
				_slotEntity.append(l_index)
				_slotNext.append(_chunkHead[l_chunkId])
				_chunkHead[l_chunkId] = _slotEntity.size() - 1


## Resolves one hit per entity from the fixed 60/30/10 mix of single, capped and blast hits. [br]
## @return The checksum every port has to reproduce
func run_hits() -> int:
	var l_entityTeam: PackedByteArray = _entityTeam
	var l_entityX: PackedFloat64Array = _entityX
	var l_entityY: PackedFloat64Array = _entityY
	var l_entityRadius: PackedFloat64Array = _entityRadius
	var l_chunkHead: PackedInt32Array = _chunkHead
	var l_slotEntity: PackedInt32Array = _slotEntity
	var l_slotNext: PackedInt32Array = _slotNext
	var l_entityCount: int = _entityCount
	var l_landed: int = 0
	var l_idSum: int = 0

	for l_emitter: int in l_entityCount:
		var l_kind: int = l_emitter % 10
		var l_hitRadius: float = SINGLE_R
		var l_maxHits: int = 1
		var l_isOrdered: bool = true

		if (l_kind >= 6 and l_kind < 9):
			l_hitRadius = CAPPED_R
			l_maxHits = CAPPED_MAX
		elif (l_kind >= 9):
			l_hitRadius = BLAST_R
			l_maxHits = -1
			l_isOrdered = false

		var l_originX: float = l_entityX[l_emitter]
		var l_originY: float = l_entityY[l_emitter]
		var l_team: int = l_entityTeam[l_emitter]
		_candidateIds.clear()
		_candidateKeys.clear()
		_visitStamp += 1

		var l_stamp: int = _visitStamp
		var l_firstColumn: int = clampi(int(floor((l_originX - l_hitRadius) / CHUNK)), 0, COLS - 1)
		var l_lastColumn: int = clampi(int(floor((l_originX + l_hitRadius) / CHUNK)), 0, COLS - 1)
		var l_firstRow: int = clampi(int(floor((l_originY - l_hitRadius) / CHUNK)), 0, ROWS - 1)
		var l_lastRow: int = clampi(int(floor((l_originY + l_hitRadius) / CHUNK)), 0, ROWS - 1)

		for l_column: int in range(l_firstColumn, l_lastColumn + 1):
			for l_row: int in range(l_firstRow, l_lastRow + 1):
				var l_slot: int = l_chunkHead[l_row * COLS + l_column]
				while (l_slot != -1):
					var l_candidate: int = l_slotEntity[l_slot]
					l_slot = l_slotNext[l_slot]
					if (_entityVisitStamp[l_candidate] == l_stamp):
						continue
					_entityVisitStamp[l_candidate] = l_stamp
					if (l_entityTeam[l_candidate] == l_team):
						continue

					var l_deltaX: float = l_entityX[l_candidate] - l_originX
					var l_deltaY: float = l_entityY[l_candidate] - l_originY
					var l_reach: float = l_hitRadius + l_entityRadius[l_candidate]
					var l_distanceSquared: float = l_deltaX * l_deltaX + l_deltaY * l_deltaY
					if (l_distanceSquared > l_reach * l_reach):
						continue
					_candidateIds.append(l_candidate)
					_candidateKeys.append(l_distanceSquared)

		var l_candidateCount: int = _candidateIds.size()
		if (l_candidateCount == 0):
			continue

		var l_limit: int = l_candidateCount if l_maxHits < 0 else mini(l_maxHits, l_candidateCount)
		if (l_isOrdered and l_limit < l_candidateCount):
			_candidateOrder.resize(l_candidateCount)
			for l_index: int in l_candidateCount:
				_candidateOrder[l_index] = l_index
			for l_index: int in range(1, l_candidateCount):
				var l_value: int = _candidateOrder[l_index]
				var l_insertAt: int = l_index
				while (l_insertAt > 0 and _candidateKeys[_candidateOrder[l_insertAt - 1]] > _candidateKeys[l_value]):
					_candidateOrder[l_insertAt] = _candidateOrder[l_insertAt - 1]
					l_insertAt -= 1
				_candidateOrder[l_insertAt] = l_value
			for l_index: int in l_limit:
				l_landed += 1
				l_idSum += _candidateIds[_candidateOrder[l_index]]
		else:
			for l_index: int in l_limit:
				l_landed += 1
				l_idSum += _candidateIds[l_index]

	return l_landed * 1000003 + l_idSum

#endregion

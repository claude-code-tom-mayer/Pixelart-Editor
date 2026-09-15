extends RefCounted
## GDScript reference implementation of the search kernel benchmark.
class_name KernelGDOpt

const COLS: int = 32
const ROWS: int = 32
const REACH: int = 4
const SEARCH_GROUPS: int = 7
const W_CLOSE: float = 1.0
const W_FOCUS: float = 6.0
const W_BEHIND: float = 3.0
const W_CROWD: float = 1.5
const W_MUTUAL: float = 4.0
const DIAG: float = 1.45

var _state: int = 12345
var _team: PackedByteArray = PackedByteArray()
var _groups: PackedInt64Array = PackedInt64Array()
var _flags: PackedByteArray = PackedByteArray()
var _ccol: PackedInt32Array = PackedInt32Array()
var _crow: PackedInt32Array = PackedInt32Array()
var _target: PackedInt32Array = PackedInt32Array()
var _crowd: PackedInt32Array = PackedInt32Array()
var _centerHead: PackedInt32Array = PackedInt32Array()
var _centerNext: PackedInt32Array = PackedInt32Array()
var _chunkGroups: PackedInt64Array = PackedInt64Array()
var _colGroups: PackedInt64Array = PackedInt64Array()
var _mapGroups: PackedInt64Array = PackedInt64Array()
var _n: int = 0

func _rand01() -> float:
	_state ^= (_state << 13) & 0xFFFFFFFF
	_state ^= (_state >> 17)
	_state ^= (_state << 5) & 0xFFFFFFFF
	_state &= 0xFFFFFFFF
	return float(_state >> 8) / 16777216.0

func build(p_n: int) -> void:
	_n = p_n
	_state = 12345
	_team.resize(p_n); _groups.resize(p_n); _flags.resize(p_n)
	_ccol.resize(p_n); _crow.resize(p_n); _target.resize(p_n); _crowd.resize(p_n)
	_centerNext.resize(p_n)
	_centerHead.resize(COLS * ROWS); _centerHead.fill(-1)
	_chunkGroups.resize(2 * COLS * ROWS); _chunkGroups.fill(0)
	_colGroups.resize(2 * COLS); _colGroups.fill(0)
	_mapGroups.resize(2); _mapGroups.fill(0)
	for i: int in p_n:
		var l_team: int = i % 2
		var l_front: float = 4096.0 * (0.35 if l_team == 0 else 0.65)
		var l_x: float = clampf(l_front + (_rand01() - 0.5) * 2.0 * 655.36, 0.0, 4095.0)
		var l_y: float = clampf(_rand01() * 4096.0, 0.0, 4095.0)
		var l_g: int = 1 << (i % 3)
		_team[i] = l_team; _groups[i] = l_g; _flags[i] = 0
		_target[i] = -1; _crowd[i] = 0
		var l_c: int = clampi(int(floor(l_x / 128.0)), 0, COLS - 1)
		var l_r: int = clampi(int(floor(l_y / 128.0)), 0, ROWS - 1)
		_ccol[i] = l_c; _crow[i] = l_r
		var l_cid: int = l_r * COLS + l_c
		_centerNext[i] = _centerHead[l_cid]; _centerHead[l_cid] = i
		_chunkGroups[l_team * COLS * ROWS + l_cid] |= l_g
		_colGroups[l_team * COLS + l_c] |= l_g
		_mapGroups[l_team] |= l_g

func _map_has(p_team: int) -> bool:
	for t: int in 2:
		if t != p_team and (_mapGroups[t] & SEARCH_GROUPS) != 0: return true
	return false

func _col_has(p_team: int, p_col: int) -> bool:
	for t: int in 2:
		if t != p_team and (_colGroups[t * COLS + p_col] & SEARCH_GROUPS) != 0: return true
	return false

func _chunk_has(p_team: int, p_cid: int) -> bool:
	for t: int in 2:
		if t != p_team and (_chunkGroups[t * COLS * ROWS + p_cid] & SEARCH_GROUPS) != 0: return true
	return false

func run() -> int:
	# hoist every read only column into a local; GDScript member access is a lot
	# slower than a local, and the three has() helpers were a call per check.
	# arrays that are WRITTEN (_target, _crowd) must stay members, otherwise the
	# copy on write unshare would leave the local pointing at a stale buffer.
	var l_team: PackedByteArray = _team
	var l_groups: PackedInt64Array = _groups
	var l_flags: PackedByteArray = _flags
	var l_ccol: PackedInt32Array = _ccol
	var l_crow: PackedInt32Array = _crow
	var l_next: PackedInt32Array = _centerNext
	var l_head: PackedInt32Array = _centerHead
	var l_colG: PackedInt64Array = _colGroups
	var l_chunkG: PackedInt64Array = _chunkGroups
	var l_mapG: PackedInt64Array = _mapGroups
	var l_n: int = _n

	for s: int in l_n:
		var t: int = l_team[s]
		var opp: int = 1 - t
		if (l_mapG[opp] & SEARCH_GROUPS) == 0:
			_target[s] = -1
			continue
		var col: int = l_ccol[s]
		var row: int = l_crow[s]
		var sf: int = l_flags[s]
		var fwd: int = 1 if t == 0 else -1
		var oppColBase: int = opp * COLS
		var oppChunkBase: int = opp * COLS * ROWS
		var bestId: int = -1
		var bestScore: float = 0.0
		var maxBonus: float = W_BEHIND + W_MUTUAL + W_FOCUS
		for ring: int in REACH + 1:
			if bestId != -1 and bestScore >= (REACH - ring) * W_CLOSE + maxBonus: break
			var L: int = col - ring
			var R: int = col + ring
			var T: int = row - ring
			var B: int = row + ring
			for c: int in range(maxi(L, 0), mini(R, COLS - 1) + 1):
				if (l_colG[oppColBase + c] & SEARCH_GROUPS) == 0: continue
				var edge: bool = c == L or c == R
				var r0: int = maxi(T, 0) if edge else T
				var r1: int = mini(B, ROWS - 1) if edge else B
				var step: int = 1 if edge else maxi(B - T, 1)
				var r: int = r0
				while r <= r1:
					if r < 0 or r >= ROWS:
						r += step
						continue
					var cid: int = r * COLS + c
					if (l_chunkG[oppChunkBase + cid] & SEARCH_GROUPS) == 0:
						r += step
						continue
					var k: int = l_head[cid]
					while k != -1:
						if l_team[k] == t: k = l_next[k]; continue
						if (l_groups[k] & SEARCH_GROUPS) == 0: k = l_next[k]; continue
						var kf: int = l_flags[k]
						if (kf & 1) != 0 and (sf & 2) == 0: k = l_next[k]; continue
						var kcol: int = l_ccol[k]
						var dc: int = absi(kcol - col)
						var dr: int = absi(l_crow[k] - row)
						var d: int = mini(dc, dr)
						var sc: float = (REACH - ((maxi(dc, dr) - d) + d * DIAG)) * W_CLOSE
						if (kf & 4) != 0 and (sf & 8) == 0: sc += W_FOCUS
						if (kcol - col) * fwd < 0: sc += W_BEHIND
						if _target[k] == s: sc += W_MUTUAL
						sc -= _crowd[k] * W_CROWD
						if bestId == -1 or sc > bestScore or (sc == bestScore and k < bestId):
							bestScore = sc; bestId = k
						k = l_next[k]
					r += step
		if _target[s] != -1: _crowd[_target[s]] -= 1
		_target[s] = bestId
		if bestId != -1: _crowd[bestId] += 1
	var l_sum: int = 0
	for s: int in l_n: l_sum += _target[s] + 1
	return l_sum

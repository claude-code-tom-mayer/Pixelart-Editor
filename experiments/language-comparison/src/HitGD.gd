extends RefCounted
## GDScript mirror of the hit kernel, written in the hoisted/inlined style so the
## comparison against C++ is against competent GDScript, not naive GDScript.
class_name HitGD

const COLS: int = 32
const ROWS: int = 32
const CHUNK: float = 128.0
const RADII: Array[float] = [12.0, 24.0, 40.0, 90.0]
const SINGLE_R: float = 64.0
const CAPPED_R: float = 128.0
const BLAST_R: float = 192.0
const CAPPED_MAX: int = 5

var _state: int = 12345
var _n: int = 0
var _team: PackedByteArray = PackedByteArray()
var _px: PackedFloat64Array = PackedFloat64Array()
var _py: PackedFloat64Array = PackedFloat64Array()
var _radius: PackedFloat64Array = PackedFloat64Array()
var _chunkHead: PackedInt32Array = PackedInt32Array()
var _slotEntity: PackedInt32Array = PackedInt32Array()
var _slotNext: PackedInt32Array = PackedInt32Array()
var _stamp: PackedInt32Array = PackedInt32Array()
var _curStamp: int = 0
var _cand: PackedInt32Array = PackedInt32Array()
var _key: PackedFloat64Array = PackedFloat64Array()
var _order: PackedInt32Array = PackedInt32Array()

func _rand01() -> float:
	_state ^= (_state << 13) & 0xFFFFFFFF
	_state ^= (_state >> 17)
	_state ^= (_state << 5) & 0xFFFFFFFF
	_state &= 0xFFFFFFFF
	return float(_state >> 8) / 16777216.0

func build(p_n: int) -> void:
	_n = p_n
	_state = 12345
	_team.resize(p_n); _px.resize(p_n); _py.resize(p_n); _radius.resize(p_n)
	_stamp.resize(p_n); _stamp.fill(0); _curStamp = 0
	_chunkHead.resize(COLS * ROWS); _chunkHead.fill(-1)
	_slotEntity.clear(); _slotNext.clear()
	for i: int in p_n:
		var t: int = i % 2
		var front: float = 4096.0 * (0.35 if t == 0 else 0.65)
		var x: float = clampf(front + (_rand01() - 0.5) * 2.0 * 655.36, 0.0, 4095.0)
		var y: float = clampf(_rand01() * 4096.0, 0.0, 4095.0)
		_team[i] = t; _px[i] = x; _py[i] = y
		var r: float = RADII[i % 4]
		_radius[i] = r
		var c0: int = clampi(int(floor((x - r) / CHUNK)), 0, COLS - 1)
		var c1: int = clampi(int(floor((x + r) / CHUNK)), 0, COLS - 1)
		var r0: int = clampi(int(floor((y - r) / CHUNK)), 0, ROWS - 1)
		var r1: int = clampi(int(floor((y + r) / CHUNK)), 0, ROWS - 1)
		for rr: int in range(r0, r1 + 1):
			for cc: int in range(c0, c1 + 1):
				var cid: int = rr * COLS + cc
				_slotEntity.append(i)
				_slotNext.append(_chunkHead[cid])
				_chunkHead[cid] = _slotEntity.size() - 1

func run_hits() -> int:
	var l_team: PackedByteArray = _team
	var l_px: PackedFloat64Array = _px
	var l_py: PackedFloat64Array = _py
	var l_radius: PackedFloat64Array = _radius
	var l_head: PackedInt32Array = _chunkHead
	var l_slotE: PackedInt32Array = _slotEntity
	var l_slotN: PackedInt32Array = _slotNext
	var l_n: int = _n
	var l_landed: int = 0
	var l_idSum: int = 0

	for e: int in l_n:
		var kind: int = e % 10
		var R: float = SINGLE_R
		var maxHits: int = 1
		var ordered: bool = true
		if kind >= 6 and kind < 9:
			R = CAPPED_R; maxHits = CAPPED_MAX
		elif kind >= 9:
			R = BLAST_R; maxHits = -1; ordered = false
		var ox: float = l_px[e]
		var oy: float = l_py[e]
		var t: int = l_team[e]
		_cand.clear(); _key.clear()
		_curStamp += 1
		var cs: int = _curStamp
		var c0: int = clampi(int(floor((ox - R) / CHUNK)), 0, COLS - 1)
		var c1: int = clampi(int(floor((ox + R) / CHUNK)), 0, COLS - 1)
		var r0: int = clampi(int(floor((oy - R) / CHUNK)), 0, ROWS - 1)
		var r1: int = clampi(int(floor((oy + R) / CHUNK)), 0, ROWS - 1)
		for cc: int in range(c0, c1 + 1):
			for rr: int in range(r0, r1 + 1):
				var sl: int = l_head[rr * COLS + cc]
				while sl != -1:
					var k: int = l_slotE[sl]
					sl = l_slotN[sl]
					if _stamp[k] == cs: continue
					_stamp[k] = cs
					if l_team[k] == t: continue
					var dx: float = l_px[k] - ox
					var dy: float = l_py[k] - oy
					var reach: float = R + l_radius[k]
					var d2: float = dx * dx + dy * dy
					if d2 > reach * reach: continue
					_cand.append(k); _key.append(d2)
		var m: int = _cand.size()
		if m == 0: continue
		var limit: int = m if maxHits < 0 else mini(maxHits, m)
		if ordered and limit < m:
			_order.resize(m)
			for i: int in m: _order[i] = i
			for i: int in range(1, m):
				var v: int = _order[i]
				var j: int = i
				while j > 0 and _key[_order[j - 1]] > _key[v]:
					_order[j] = _order[j - 1]; j -= 1
				_order[j] = v
			for i: int in limit:
				l_landed += 1; l_idSum += _cand[_order[i]]
		else:
			for i: int in limit:
				l_landed += 1; l_idSum += _cand[i]
	return l_landed * 1000003 + l_idSum

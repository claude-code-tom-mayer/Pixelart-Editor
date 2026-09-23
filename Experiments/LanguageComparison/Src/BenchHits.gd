extends SceneTree
class_name BenchHits
## N entities, N hits per frame, fixed mix: 60% single target (maxHits 1), 30% capped AoE [br]
## (maxHits 5), 10% uncapped blast; same proportions at every N. Needs the C++ SearchKernel.

#region LIFECYCLE_AND_METHODS

## Times the hit kernel in GDScript and C++ per entity count, then quits.
func _init() -> void:
	print("")
	print("  N | GD hits ms | C++ hits ms | speedup | GD us/hit | C++ us/hit | checksum")
	print("-----+------------+-------------+---------+-----------+------------+---------")
	
	for l_entityCount: int in [500, 1000, 3000, 10000]:
		var l_reps: int = maxi(1, 1500000 / (l_entityCount * 12))
		var l_gd: HitGD = HitGD.new()
		l_gd.build(l_entityCount)
		var l_gdChecksum: int = 0
		var l_start: int = Time.get_ticks_usec()
		for l_rep: int in l_reps:
			l_gdChecksum = l_gd.run_hits()
		var l_gdMs: float = float(Time.get_ticks_usec() - l_start) / 1000.0 / float(l_reps)
		
		var l_nativeReps: int = l_reps * 20
		var l_cpp: SearchKernel = SearchKernel.new()
		l_cpp.build_hits(l_entityCount)
		var l_cppChecksum: int = 0
		l_start = Time.get_ticks_usec()
		for l_rep: int in l_nativeReps:
			l_cppChecksum = l_cpp.run_hits()
		var l_cppMs: float = float(Time.get_ticks_usec() - l_start) / 1000.0 / float(l_nativeReps)
		
		print("%4d | %10.3f | %11.4f | %6.1fx | %9.3f | %10.4f | %s" % [l_entityCount, l_gdMs, l_cppMs,
			l_gdMs / l_cppMs, l_gdMs * 1000.0 / l_entityCount, l_cppMs * 1000.0 / l_entityCount,
			("ok" if l_gdChecksum == l_cppChecksum else "MISMATCH")])
	
	quit()

#endregion

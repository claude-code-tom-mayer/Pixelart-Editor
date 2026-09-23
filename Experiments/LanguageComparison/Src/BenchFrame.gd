extends SceneTree
class_name BenchFrame
## A whole frame: N searches + N hits (60/30/10 mix), optimised GDScript vs C++. [br]
## Needs the C++ SearchKernel GDExtension loaded in the project.

#region LIFECYCLE_AND_METHODS

## Times the search and hit phase of one frame in GDScript and C++ per entity count, then quits.
func _init() -> void:
	print("")
	print("    N |        GDScript (opt)        |          C++ GDExtension      | speedup")
	print("      | search ms  hit ms  total ms  | search ms  hit ms   total ms  |")
	print("------+------------------------------+-------------------------------+--------")
	
	for l_entityCount: int in [500, 1000, 3000, 10000]:
		var l_searchReps: int = maxi(1, 1500000 / (l_entityCount * 30))
		var l_hitReps: int = maxi(1, 1500000 / (l_entityCount * 12))
		
		var l_gdSearch: KernelGDOpt = KernelGDOpt.new()
		l_gdSearch.build(l_entityCount)
		var l_start: int = Time.get_ticks_usec()
		for l_rep: int in l_searchReps:
			l_gdSearch.build(l_entityCount)
			l_gdSearch.run()
		var l_gdSearchMs: float = float(Time.get_ticks_usec() - l_start) / 1000.0 / float(l_searchReps)
		
		var l_gdHits: HitGD = HitGD.new()
		l_gdHits.build(l_entityCount)
		l_start = Time.get_ticks_usec()
		for l_rep: int in l_hitReps:
			l_gdHits.run_hits()
		var l_gdHitMs: float = float(Time.get_ticks_usec() - l_start) / 1000.0 / float(l_hitReps)
		
		var l_cpp: SearchKernel = SearchKernel.new()
		l_cpp.build(l_entityCount)
		l_cpp.build_hits(l_entityCount)
		l_start = Time.get_ticks_usec()
		for l_rep: int in l_searchReps * 20:
			l_cpp.build(l_entityCount)
			l_cpp.run()
		var l_cppSearchMs: float = float(Time.get_ticks_usec() - l_start) / 1000.0 / float(l_searchReps * 20)
		l_start = Time.get_ticks_usec()
		for l_rep: int in l_hitReps * 20:
			l_cpp.run_hits()
		var l_cppHitMs: float = float(Time.get_ticks_usec() - l_start) / 1000.0 / float(l_hitReps * 20)
		
		var l_gdTotalMs: float = l_gdSearchMs + l_gdHitMs
		var l_cppTotalMs: float = l_cppSearchMs + l_cppHitMs
		print("%5d | %8.2f %8.2f %9.2f  | %8.3f %8.3f %9.3f  | %5.1fx" % [l_entityCount, l_gdSearchMs,
			l_gdHitMs, l_gdTotalMs, l_cppSearchMs, l_cppHitMs, l_cppTotalMs, l_gdTotalMs / l_cppTotalMs])
	
	quit()

#endregion

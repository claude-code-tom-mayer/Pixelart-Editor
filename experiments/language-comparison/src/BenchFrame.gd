extends SceneTree
## A whole frame: N searches + N hits (60/30/10 mix), optimised GDScript vs C++.
class_name BenchFrame

func _init() -> void:
	print("")
	print("    N |        GDScript (opt)        |          C++ GDExtension      | speedup")
	print("      | search ms  hit ms  total ms  | search ms  hit ms   total ms  |")
	print("------+------------------------------+-------------------------------+--------")
	for n: int in [500, 1000, 3000, 10000]:
		var sReps: int = maxi(1, 1500000 / (n * 30))
		var hReps: int = maxi(1, 1500000 / (n * 12))

		var gs: KernelGDOpt = KernelGDOpt.new()
		gs.build(n)
		var t: int = Time.get_ticks_usec()
		for i: int in sReps:
			gs.build(n); gs.run()
		var gSearch: float = float(Time.get_ticks_usec() - t) / 1000.0 / float(sReps)

		var gh: HitGD = HitGD.new()
		gh.build(n)
		t = Time.get_ticks_usec()
		for i: int in hReps:
			gh.run_hits()
		var gHit: float = float(Time.get_ticks_usec() - t) / 1000.0 / float(hReps)

		var c: SearchKernel = SearchKernel.new()
		c.build(n); c.build_hits(n)
		t = Time.get_ticks_usec()
		for i: int in sReps * 20:
			c.build(n); c.run()
		var cSearch: float = float(Time.get_ticks_usec() - t) / 1000.0 / float(sReps * 20)
		t = Time.get_ticks_usec()
		for i: int in hReps * 20:
			c.run_hits()
		var cHit: float = float(Time.get_ticks_usec() - t) / 1000.0 / float(hReps * 20)

		var gTot: float = gSearch + gHit
		var cTot: float = cSearch + cHit
		print("%5d | %8.2f %8.2f %9.2f  | %8.3f %8.3f %9.3f  | %5.1fx" % [n,
			gSearch, gHit, gTot, cSearch, cHit, cTot, gTot / cTot])
	quit()

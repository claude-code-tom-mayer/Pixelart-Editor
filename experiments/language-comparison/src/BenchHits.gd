extends SceneTree
## N entities, N hits per frame, fixed mix: 60% single target (maxHits 1),
## 30% capped AoE (maxHits 5), 10% uncapped blast. Same proportions at every N.
class_name BenchHits

func _init() -> void:
	print("")
	print("  N | GD hits ms | C++ hits ms | speedup | GD us/hit | C++ us/hit | checksum")
	print("-----+------------+-------------+---------+-----------+------------+---------")
	for n: int in [500, 1000, 3000, 10000]:
		var reps: int = maxi(1, 1500000 / (n * 12))
		var g: HitGD = HitGD.new()
		g.build(n)
		var gv: int = 0
		var t: int = Time.get_ticks_usec()
		for i: int in reps:
			gv = g.run_hits()
		var gms: float = float(Time.get_ticks_usec() - t) / 1000.0 / float(reps)

		var natReps: int = reps * 20
		var c: SearchKernel = SearchKernel.new()
		c.build_hits(n)
		var cv: int = 0
		t = Time.get_ticks_usec()
		for i: int in natReps:
			cv = c.run_hits()
		var cms: float = float(Time.get_ticks_usec() - t) / 1000.0 / float(natReps)

		print("%4d | %10.3f | %11.4f | %6.1fx | %9.3f | %10.4f | %s" % [n, gms, cms, gms / cms,
			gms * 1000.0 / n, cms * 1000.0 / n, ("ok" if gv == cv else "MISMATCH")])
	quit()

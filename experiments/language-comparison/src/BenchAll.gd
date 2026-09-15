extends SceneTree
## GDScript vs C++ GDExtension vs Rust GDExtension, same kernel, same process.
class_name BenchAll

const CALLS: int = 2000000

func _init() -> void:
	print("")
	print("    n | GDScript us | C++ us | Rust us | C++ vs GD | Rust vs GD | checksums")
	print("------+-------------+--------+---------+-----------+------------+----------")
	for n: int in [500, 1000, 3000, 5000]:
		var l_reps: int = maxi(1, 3000000 / (n * 40))
		var l_gdSum: int = 0
		var l_t: int = Time.get_ticks_usec()
		for rep: int in l_reps:
			var g: KernelGD = KernelGD.new()
			g.build(n)
			l_gdSum = g.run()
		var l_gdUs: float = float(Time.get_ticks_usec() - l_t) / float(n * l_reps)

		var l_natReps: int = l_reps * 20
		var l_cppSum: int = 0
		l_t = Time.get_ticks_usec()
		for rep: int in l_natReps:
			var c: SearchKernel = SearchKernel.new()
			c.build(n)
			l_cppSum = c.run()
		var l_cppUs: float = float(Time.get_ticks_usec() - l_t) / float(n * l_natReps)

		var l_rsSum: int = 0
		l_t = Time.get_ticks_usec()
		for rep: int in l_natReps:
			var r: SearchKernelRs = SearchKernelRs.new()
			r.build(n)
			l_rsSum = r.run()
		var l_rsUs: float = float(Time.get_ticks_usec() - l_t) / float(n * l_natReps)

		var l_ok: String = "match" if (l_gdSum == l_cppSum and l_gdSum == l_rsSum) else "MISMATCH"
		print("%5d | %11.3f | %6.3f | %7.3f | %8.1fx | %9.1fx | %s" % [n, l_gdUs, l_cppUs, l_rsUs,
			l_gdUs / l_cppUs, l_gdUs / l_rsUs, l_ok])

	print("")
	print("=== boundary: %d trivial calls from GDScript ===" % CALLS)
	var l_sum: int = 0
	var l_gd: NoopGD = NoopGD.new()
	var l_t2: int = Time.get_ticks_usec()
	for i: int in CALLS: l_sum += l_gd.noop(i)
	print("GDScript -> GDScript        : %7.1f ns/call" % (float(Time.get_ticks_usec() - l_t2) * 1000.0 / float(CALLS)))
	var l_c: SearchKernel = SearchKernel.new()
	l_t2 = Time.get_ticks_usec()
	for i: int in CALLS: l_sum += l_c.noop(i)
	print("GDScript -> C++ GDExtension : %7.1f ns/call" % (float(Time.get_ticks_usec() - l_t2) * 1000.0 / float(CALLS)))
	var l_r: SearchKernelRs = SearchKernelRs.new()
	l_t2 = Time.get_ticks_usec()
	for i: int in CALLS: l_sum += l_r.noop(i)
	print("GDScript -> Rust GDExtension: %7.1f ns/call" % (float(Time.get_ticks_usec() - l_t2) * 1000.0 / float(CALLS)))
	quit()

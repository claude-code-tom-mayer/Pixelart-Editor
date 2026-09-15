extends SceneTree
## Repeats each measurement so the short runs are not dominated by timer noise.
class_name BenchCpp2

const CALLS: int = 2000000

func _init() -> void:
	print("")
	print("    n | GDScript us/search | C++ ext us/search | speedup | match")
	print("------+--------------------+-------------------+---------+------")
	for n: int in [500, 1000, 3000, 5000]:
		var l_reps: int = maxi(1, 3000000 / (n * 40))
		var l_gdSum: int = 0
		var l_t: int = Time.get_ticks_usec()
		for rep: int in l_reps:
			var l_gd: KernelGD = KernelGD.new()
			l_gd.build(n)
			l_gdSum = l_gd.run()
		var l_gdUs: float = float(Time.get_ticks_usec() - l_t) / float(n * l_reps)

		var l_cppReps: int = l_reps * 20
		var l_cppSum: int = 0
		l_t = Time.get_ticks_usec()
		for rep: int in l_cppReps:
			var l_cpp: SearchKernel = SearchKernel.new()
			l_cpp.build(n)
			l_cppSum = l_cpp.run()
		var l_cppUs: float = float(Time.get_ticks_usec() - l_t) / float(n * l_cppReps)

		print("%5d | %18.3f | %17.3f | %6.1fx | %s" % [n, l_gdUs, l_cppUs, l_gdUs / l_cppUs,
			("yes" if l_gdSum == l_cppSum else "NO")])

	print("")
	var l_noopGd: NoopGD = NoopGD.new()
	var l_sum: int = 0
	var l_t2: int = Time.get_ticks_usec()
	for i: int in CALLS:
		l_sum += l_noopGd.noop(i)
	print("GDScript -> GDScript  : %7.1f ns/call" % (float(Time.get_ticks_usec() - l_t2) * 1000.0 / float(CALLS)))
	var l_noopCpp: SearchKernel = SearchKernel.new()
	l_t2 = Time.get_ticks_usec()
	for i: int in CALLS:
		l_sum += l_noopCpp.noop(i)
	print("GDScript -> C++ GDExt : %7.1f ns/call" % (float(Time.get_ticks_usec() - l_t2) * 1000.0 / float(CALLS)))
	quit()

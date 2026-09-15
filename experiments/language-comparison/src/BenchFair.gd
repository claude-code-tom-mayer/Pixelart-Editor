extends SceneTree
## Naive GDScript vs hand optimised GDScript vs C++, build and run timed separately.
class_name BenchFair

func _init() -> void:
	print("")
	print("    n | GD naive | GD opt | C++   | naive/opt | naive/C++ | opt/C++")
	print("------+----------+--------+-------+-----------+-----------+--------")
	for n: int in [500, 1000, 3000, 5000]:
		var reps: int = maxi(1, 2000000 / (n * 40))
		var nat: int = reps * 20

		var a: KernelGD = KernelGD.new()
		a.build(n)
		var t: int = Time.get_ticks_usec()
		for i: int in reps:
			a.build(n); a.run()
		var naive: float = float(Time.get_ticks_usec() - t) / float(n * reps)

		var b: KernelGDOpt = KernelGDOpt.new()
		b.build(n)
		t = Time.get_ticks_usec()
		for i: int in reps:
			b.build(n); b.run()
		var opt: float = float(Time.get_ticks_usec() - t) / float(n * reps)

		var c: SearchKernel = SearchKernel.new()
		t = Time.get_ticks_usec()
		for i: int in nat:
			c.build(n); c.run()
		var cpp: float = float(Time.get_ticks_usec() - t) / float(n * nat)

		print("%5d | %8.3f | %6.3f | %5.3f | %8.2fx | %8.1fx | %6.1fx" % [n, naive, opt, cpp,
			naive / opt, naive / cpp, opt / cpp])

	print("")
	print("--- build phase alone (us per entity), to show how much of the above is setup ---")
	for n: int in [500, 3000]:
		var reps: int = maxi(1, 400000 / n)
		var b: KernelGDOpt = KernelGDOpt.new()
		var t: int = Time.get_ticks_usec()
		for i: int in reps: b.build(n)
		var gdb: float = float(Time.get_ticks_usec() - t) / float(n * reps)
		var c: SearchKernel = SearchKernel.new()
		t = Time.get_ticks_usec()
		for i: int in reps * 10: c.build(n)
		var cb: float = float(Time.get_ticks_usec() - t) / float(n * reps * 10)
		print("n=%5d  GD opt build=%.3f us/entity   C++ build=%.3f us/entity  (%.0fx)" % [n, gdb, cb, gdb / cb])
	quit()

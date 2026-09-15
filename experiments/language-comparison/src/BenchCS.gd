extends SceneTree
## Compares the GDScript kernel against the same kernel in C#, plus boundary cost.
class_name BenchCS

const CALLS: int = 1000000

func _init() -> void:
	print("")
	print("=== kernel, whole loop inside the language (one boundary crossing) ===")
	print("    n | GDScript us/search | C# us/search | checksums match")
	print("------+--------------------+--------------+----------------")
	for n: int in [500, 1000, 3000, 5000]:
		var l_gd: KernelGD = KernelGD.new()
		l_gd.build(n)
		var l_t: int = Time.get_ticks_usec()
		var l_gdSum: int = l_gd.run()
		var l_gdUs: float = float(Time.get_ticks_usec() - l_t) / float(n)

		var l_cs: Object = _make_cs()
		l_cs.build(n)
		l_cs.run()              # warm the JIT
		l_cs.build(n)
		l_t = Time.get_ticks_usec()
		var l_csSum: int = l_cs.run()
		var l_csUs: float = float(Time.get_ticks_usec() - l_t) / float(n)

		print("%5d | %18.3f | %12.3f | %s" % [n, l_gdUs, l_csUs,
			("yes" if l_gdSum == l_csSum else "NO (%d vs %d)" % [l_gdSum, l_csSum])])

	print("")
	print("=== boundary cost: %d trivial calls from GDScript ===" % CALLS)
	var l_noopGd: NoopGD = NoopGD.new()
	var l_sum: int = 0
	var l_t2: int = Time.get_ticks_usec()
	for i: int in CALLS:
		l_sum += l_noopGd.noop(i)
	var l_gdNs: float = float(Time.get_ticks_usec() - l_t2) * 1000.0 / float(CALLS)

	var l_noopCs: Object = _make_cs()
	l_noopCs.noop(1)
	l_t2 = Time.get_ticks_usec()
	for i: int in CALLS:
		l_sum += l_noopCs.noop(i)
	var l_csNs: float = float(Time.get_ticks_usec() - l_t2) * 1000.0 / float(CALLS)

	print("GDScript -> GDScript : %7.1f ns/call" % l_gdNs)
	print("GDScript -> C#       : %7.1f ns/call" % l_csNs)
	quit()


func _make_cs() -> Object:
	var l_script: Script = load("res://KernelCS.cs")
	return l_script.new()

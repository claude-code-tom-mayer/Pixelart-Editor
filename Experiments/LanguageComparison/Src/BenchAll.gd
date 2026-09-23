extends SceneTree
class_name BenchAll
## GDScript vs C++ GDExtension vs Rust GDExtension, same kernel, same process. [br]
## Needs the C++ SearchKernel and the Rust SearchKernelRs GDExtensions loaded in the project.

#region ENUMS_AND_CONSTANTS

## Trivial calls the boundary cost is averaged over.
const CALLS: int = 2000000

#endregion

#region LIFECYCLE_AND_METHODS

## Times the kernel in all three languages, then the cost of one trivial call, then quits.
func _init() -> void:
	print("")
	print("    n | GDScript us | C++ us | Rust us | C++ vs GD | Rust vs GD | checksums")
	print("------+-------------+--------+---------+-----------+------------+----------")
	
	for l_entityCount: int in [500, 1000, 3000, 5000]:
		var l_reps: int = maxi(1, 3000000 / (l_entityCount * 40))
		var l_gdChecksum: int = 0
		var l_start: int = Time.get_ticks_usec()
		for l_rep: int in l_reps:
			var l_gd: KernelGD = KernelGD.new()
			l_gd.build(l_entityCount)
			l_gdChecksum = l_gd.run()
		var l_gdUs: float = float(Time.get_ticks_usec() - l_start) / float(l_entityCount * l_reps)
		
		var l_nativeReps: int = l_reps * 20
		var l_cppChecksum: int = 0
		l_start = Time.get_ticks_usec()
		for l_rep: int in l_nativeReps:
			var l_cpp: SearchKernel = SearchKernel.new()
			l_cpp.build(l_entityCount)
			l_cppChecksum = l_cpp.run()
		var l_cppUs: float = float(Time.get_ticks_usec() - l_start) / float(l_entityCount * l_nativeReps)
		
		var l_rustChecksum: int = 0
		l_start = Time.get_ticks_usec()
		for l_rep: int in l_nativeReps:
			var l_rust: SearchKernelRs = SearchKernelRs.new()
			l_rust.build(l_entityCount)
			l_rustChecksum = l_rust.run()
		var l_rustUs: float = float(Time.get_ticks_usec() - l_start) / float(l_entityCount * l_nativeReps)
		
		var l_isMatching: bool = l_gdChecksum == l_cppChecksum and l_gdChecksum == l_rustChecksum
		print("%5d | %11.3f | %6.3f | %7.3f | %8.1fx | %9.1fx | %s" % [l_entityCount, l_gdUs, l_cppUs,
			l_rustUs, l_gdUs / l_cppUs, l_gdUs / l_rustUs, ("match" if l_isMatching else "MISMATCH")])
	
	print("")
	print("=== boundary: %d trivial calls from GDScript ===" % CALLS)
	
	var l_sum: int = 0
	var l_noopGd: NoopGD = NoopGD.new()
	var l_callStart: int = Time.get_ticks_usec()
	for l_call: int in CALLS:
		l_sum += l_noopGd.noop(l_call)
	print("GDScript -> GDScript        : %7.1f ns/call" % (float(Time.get_ticks_usec() - l_callStart) * 1000.0 / float(CALLS)))
	
	var l_noopCpp: SearchKernel = SearchKernel.new()
	l_callStart = Time.get_ticks_usec()
	for l_call: int in CALLS:
		l_sum += l_noopCpp.noop(l_call)
	print("GDScript -> C++ GDExtension : %7.1f ns/call" % (float(Time.get_ticks_usec() - l_callStart) * 1000.0 / float(CALLS)))
	
	var l_noopRust: SearchKernelRs = SearchKernelRs.new()
	l_callStart = Time.get_ticks_usec()
	for l_call: int in CALLS:
		l_sum += l_noopRust.noop(l_call)
	print("GDScript -> Rust GDExtension: %7.1f ns/call" % (float(Time.get_ticks_usec() - l_callStart) * 1000.0 / float(CALLS)))
	
	quit()

#endregion

extends SceneTree
class_name BenchCpp2
## Repeats each measurement so the short runs are not dominated by timer noise. [br]
## Needs the C++ SearchKernel GDExtension loaded in the project.

#region ENUMS_AND_CONSTANTS

## Trivial calls the boundary cost is averaged over.
const CALLS: int = 2000000

#endregion

#region LIFECYCLE_AND_METHODS

## Times the kernel in GDScript and C++, then the cost of one trivial call, then quits.
func _init() -> void:
	print("")
	print("    n | GDScript us/search | C++ ext us/search | speedup | match")
	print("------+--------------------+-------------------+---------+------")
	
	for l_entityCount: int in [500, 1000, 3000, 5000]:
		var l_reps: int = maxi(1, 3000000 / (l_entityCount * 40))
		var l_gdChecksum: int = 0
		var l_start: int = Time.get_ticks_usec()
		for l_rep: int in l_reps:
			var l_gd: KernelGD = KernelGD.new()
			l_gd.build(l_entityCount)
			l_gdChecksum = l_gd.run()
		var l_gdUs: float = float(Time.get_ticks_usec() - l_start) / float(l_entityCount * l_reps)
		
		var l_cppReps: int = l_reps * 20
		var l_cppChecksum: int = 0
		l_start = Time.get_ticks_usec()
		for l_rep: int in l_cppReps:
			var l_cpp: SearchKernel = SearchKernel.new()
			l_cpp.build(l_entityCount)
			l_cppChecksum = l_cpp.run()
		var l_cppUs: float = float(Time.get_ticks_usec() - l_start) / float(l_entityCount * l_cppReps)
		
		print("%5d | %18.3f | %17.3f | %6.1fx | %s" % [l_entityCount, l_gdUs, l_cppUs, l_gdUs / l_cppUs,
			("yes" if l_gdChecksum == l_cppChecksum else "NO")])
	
	print("")
	
	var l_noopGd: NoopGD = NoopGD.new()
	var l_sum: int = 0
	var l_callStart: int = Time.get_ticks_usec()
	for l_call: int in CALLS:
		l_sum += l_noopGd.noop(l_call)
	print("GDScript -> GDScript  : %7.1f ns/call" % (float(Time.get_ticks_usec() - l_callStart) * 1000.0 / float(CALLS)))
	
	var l_noopCpp: SearchKernel = SearchKernel.new()
	l_callStart = Time.get_ticks_usec()
	for l_call: int in CALLS:
		l_sum += l_noopCpp.noop(l_call)
	print("GDScript -> C++ GDExt : %7.1f ns/call" % (float(Time.get_ticks_usec() - l_callStart) * 1000.0 / float(CALLS)))
	
	quit()

#endregion

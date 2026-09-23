extends SceneTree
class_name BenchFair
## Naive GDScript vs hand optimised GDScript vs C++, build and run timed separately. [br]
## Needs the C++ SearchKernel GDExtension loaded in the project.

#region LIFECYCLE_AND_METHODS

## Times all three kernels per entity count, then the build phase alone, then quits.
func _init() -> void:
	print("")
	print("    n | GD naive | GD opt | C++   | naive/opt | naive/C++ | opt/C++")
	print("------+----------+--------+-------+-----------+-----------+--------")
	
	for l_entityCount: int in [500, 1000, 3000, 5000]:
		var l_reps: int = maxi(1, 2000000 / (l_entityCount * 40))
		var l_nativeReps: int = l_reps * 20
		
		var l_naive: KernelGD = KernelGD.new()
		l_naive.build(l_entityCount)
		var l_start: int = Time.get_ticks_usec()
		for l_rep: int in l_reps:
			l_naive.build(l_entityCount)
			l_naive.run()
		var l_naiveUs: float = float(Time.get_ticks_usec() - l_start) / float(l_entityCount * l_reps)
		
		var l_optimised: KernelGDOpt = KernelGDOpt.new()
		l_optimised.build(l_entityCount)
		l_start = Time.get_ticks_usec()
		for l_rep: int in l_reps:
			l_optimised.build(l_entityCount)
			l_optimised.run()
		var l_optimisedUs: float = float(Time.get_ticks_usec() - l_start) / float(l_entityCount * l_reps)
		
		var l_cpp: SearchKernel = SearchKernel.new()
		l_start = Time.get_ticks_usec()
		for l_rep: int in l_nativeReps:
			l_cpp.build(l_entityCount)
			l_cpp.run()
		var l_cppUs: float = float(Time.get_ticks_usec() - l_start) / float(l_entityCount * l_nativeReps)
		
		print("%5d | %8.3f | %6.3f | %5.3f | %8.2fx | %8.1fx | %6.1fx" % [l_entityCount, l_naiveUs,
			l_optimisedUs, l_cppUs, l_naiveUs / l_optimisedUs, l_naiveUs / l_cppUs, l_optimisedUs / l_cppUs])
	
	print("")
	print("--- build phase alone (us per entity), to show how much of the above is setup ---")
	
	for l_entityCount: int in [500, 3000]:
		var l_reps: int = maxi(1, 400000 / l_entityCount)
		
		var l_optimised: KernelGDOpt = KernelGDOpt.new()
		var l_start: int = Time.get_ticks_usec()
		for l_rep: int in l_reps:
			l_optimised.build(l_entityCount)
		var l_gdBuildUs: float = float(Time.get_ticks_usec() - l_start) / float(l_entityCount * l_reps)
		
		var l_cpp: SearchKernel = SearchKernel.new()
		l_start = Time.get_ticks_usec()
		for l_rep: int in l_reps * 10:
			l_cpp.build(l_entityCount)
		var l_cppBuildUs: float = float(Time.get_ticks_usec() - l_start) / float(l_entityCount * l_reps * 10)
		
		print("n=%5d  GD opt build=%.3f us/entity   C++ build=%.3f us/entity  (%.0fx)" % [l_entityCount,
			l_gdBuildUs, l_cppBuildUs, l_gdBuildUs / l_cppBuildUs])
	
	quit()

#endregion

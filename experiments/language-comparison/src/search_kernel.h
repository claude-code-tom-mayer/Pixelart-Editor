#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include "kernel_core.h"

namespace godot {

class SearchKernel : public RefCounted {
    GDCLASS(SearchKernel, RefCounted)

    kernel::World world;

protected:
    static void _bind_methods();

public:
    void build(int p_n) { world.build(p_n); }
    int64_t run() { return world.run(); }
    int noop(int p_x) { return p_x; }
    // one entity's search, for the per call boundary scenario
    int64_t step() { return world.run(); }
};

} // namespace godot

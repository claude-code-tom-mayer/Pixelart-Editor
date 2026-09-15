#include "search_kernel.h"
#include <godot_cpp/core/class_db.hpp>

using namespace godot;

void SearchKernel::_bind_methods() {
    ClassDB::bind_method(D_METHOD("build", "n"), &SearchKernel::build);
    ClassDB::bind_method(D_METHOD("run"), &SearchKernel::run);
    ClassDB::bind_method(D_METHOD("noop", "x"), &SearchKernel::noop);
}

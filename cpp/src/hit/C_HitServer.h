#pragma once

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/binder_common.hpp>

namespace godot {

/// Constants and orderings of the hit system.
/// Hit groups are their own bitmask space, unrelated to the chunking groups.
class C_HitServer : public Object {
	GDCLASS(C_HitServer, Object)

protected:
	static void _bind_methods();

public:
	// ===== CONFIGURATION =====

	/// Edge of a directional rect an ordered hit starts from, in the rect's own frame.
	enum RECT_EDGE {
		RECT_EDGE_BACK,
		RECT_EDGE_FRONT,
		RECT_EDGE_LEFT,
		RECT_EDGE_RIGHT
	};

	/// Passed as the hit limit to let a hit connect with every valid target.
	static constexpr int UNLIMITED_HITS = -1;

	/// Passed as the preferred target when the hit has no target to check first.
	static constexpr int NO_PREFERRED_TARGET = -1;

	/// Stored as the curve slot of an entity whose radius is constant over its whole height.
	static constexpr int NO_CURVE = -1;

	/// Upper end of both curve axes; radius curves run from 0 to 100 in x and y.
	static constexpr double CURVE_PERCENT_MAX = 100.0;

	/// Smallest capacity a reused hit buffer grows to, so short hits stop reallocating early.
	static constexpr int BUFFER_MIN_CAPACITY = 16;

	/// Samples one radius curve is baked into; a hit reads these, never the Curve itself.
	static constexpr int CURVE_SAMPLE_COUNT = 65;
};

} // namespace godot

VARIANT_ENUM_CAST(C_HitServer::RECT_EDGE);

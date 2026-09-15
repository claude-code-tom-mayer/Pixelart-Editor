#pragma once

#include "chunking/ChunkingServer.h"

#include <godot_cpp/classes/ref_counted.hpp>

namespace godot {

/// Base of every server that keeps one slot per entity id beside the chunk index.
/// Owns the slot protocol, so no server repeats it; abstract, never registered on its own.
class A_EntityServer : public RefCounted {
	GDCLASS(A_EntityServer, RefCounted)

protected:
	static void _bind_methods();

	// ===== PROTECTED_VARIABLES =====

	/// Chunk index and shared entity columns this server reads; never points back at the api server.
	ChunkingServer *_chunking = nullptr;

	// ===== PROTECTED_METHODS =====

	/// Appends one fresh slot to every column of the server.
	/// Every server has to override this.
	virtual void _append_slot() = 0;

	/// Resets one slot so a reused id inherits nothing of its predecessor.
	/// Every server has to override this.
	/// @param p_id The entity slot to reset
	virtual void _reset_slot(int p_id) = 0;

	/// Reads how many slots the server currently holds.
	/// Every server has to override this.
	/// @return The number of slots
	virtual int _get_slot_count() const = 0;

public:
	// ===== LIFECYCLE =====

	/// Binds the server to the chunk index its loops read.
	/// @param p_chunking The index and shared entity columns every server reads
	void setup(ChunkingServer *p_chunking) { _chunking = p_chunking; }

	// ===== PUBLIC_LIFECYCLE =====

	/// Makes sure the slot of an id exists and holds nothing of a previous entity.
	/// Ids only ever grow by one, so one append covers every id that is not a reused one.
	/// @param p_id The entity slot to prepare
	void ensure_slot(int p_id);

	/// Lets the server drop what it holds for an id that is handed back for reuse.
	/// @param p_id The entity whose slot is released
	virtual void release_entity(int p_id) {}

	/// Lets the server react to an entity that was announced for removal.
	/// @param p_id The entity that was announced
	virtual void on_pre_unregister(int p_id) {}

	/// Lets the server react to an entity that was removed from the index.
	/// @param p_id The entity that was removed
	virtual void on_unregister(int p_id) {}
};

} // namespace godot

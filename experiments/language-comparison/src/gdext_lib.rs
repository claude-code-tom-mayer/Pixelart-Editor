mod world;
use godot::prelude::*;
use world::World;

struct KernelExt;

#[gdextension]
unsafe impl ExtensionLibrary for KernelExt {}

#[derive(GodotClass)]
#[class(base=RefCounted)]
struct SearchKernelRs {
    world: World,
    base: Base<RefCounted>,
}

#[godot_api]
impl IRefCounted for SearchKernelRs {
    fn init(base: Base<RefCounted>) -> Self {
        Self { world: World::new(), base }
    }
}

#[godot_api]
impl SearchKernelRs {
    #[func]
    fn build(&mut self, n: i32) { self.world.build(n); }
    #[func]
    fn run(&mut self) -> i64 { self.world.run() }
    #[func]
    fn noop(&self, x: i32) -> i32 { x }
}

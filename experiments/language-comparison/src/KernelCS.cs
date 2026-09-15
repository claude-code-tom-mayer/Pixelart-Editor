using Godot;

// Godot facing wrapper around the same kernel, so GDScript can drive it.
[GlobalClass]
public partial class KernelCS : RefCounted
{
    private readonly World _world = new World();

    public void build(int n) => _world.Build(n);
    public long run() => _world.Run();
    public int noop(int x) => x;
}

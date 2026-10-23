#nullable enable
#region Models
using static System.Math;
using Alias = System.Collections.Generic.List<int>;

namespace App;

[AttributeUsage(AttributeTargets.Class | AttributeTargets.Method, AllowMultiple = false)]
public sealed class MarkerAttribute : Attribute { }

public abstract partial class Repo<TKey, TEntity> : IRepo<TKey> where TEntity : class, new() where TKey : struct
{
    protected internal readonly Dictionary<TKey, TEntity> _items = new();
    public event EventHandler<EventArgs>? Changed;
    public delegate void Handler(object sender, int code);
    public virtual async ValueTask<TEntity?> FindAsync(TKey key, CancellationToken ct = default)
    {
        await using var scope = Scope();
        lock (_items) { return _items.TryGetValue(key, out var e) ? e : null; }
    }
    public static implicit operator int(Repo<TKey, TEntity> r) => r._items.Count;
    private string Fmt(int n) => n switch { < 0 => "neg", 0 => "zero", > 0 and < 10 => $"small {n,5:N2}", _ => $@"big ""{n}""" };
    public int this[int i] { get => i; set { _ = value; } }
    unsafe void Ptr(int* p) { fixed (int* q = &p[0]) { } }
    void Misc() {
        var x = 0b1010_1010 + 0xFF + 1_000L + 1.5m + 2e3f;
        string? s = null; var l = s?.Length ?? 0;
        var arr = new[] { 1, 2, 3 }[^1..];
        var anon = new { Name = "n", Age = 1 };
        goto done; done: yield break;
        using (var d = new Disposable()) { checked { x++; } }
        var q = from a in arr join b in arr on a equals b orderby a descending select new { a, b };
    }
}
#endregion

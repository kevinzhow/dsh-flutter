using System;
using System.Collections.Generic;
using System.Linq;

namespace Demo.App
{
    /// <summary>Doc comment.</summary>
    public interface IShape { double Area { get; } }

    [Serializable]
    public sealed class Circle : IShape
    {
        private readonly double _r;
        public const int Max = 10;
        public double Area => Math.PI * _r * _r;
        public string Name { get; init; } = "circle";

        public Circle(double r) { _r = r; }

        public static async Task<int> CountAsync(IEnumerable<string> src)
        {
            var q = from s in src where s.Length > 2 select s.ToUpper();
            string verbatim = @"C:\path\""quoted""";
            string interp = $"{q.Count()} items, {Max:D3}";
            char ch = '\t';
            int? maybe = null;
            await Task.Delay(10);
            return maybe ?? q.Count();
        }
    }

    public record Person(string First, string Last);

    public enum Level { Low, High }
}

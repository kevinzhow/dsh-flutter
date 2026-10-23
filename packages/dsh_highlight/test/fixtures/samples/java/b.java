import java.util.function.*;
import java.util.stream.Collectors;

sealed interface Shape permits Circle, Square {}
record Circle(double r) implements Shape {}
record Square(double s) implements Shape {}

public class Main {
    @SuppressWarnings({"unchecked", "rawtypes"})
    static <T extends Comparable<? super T>> T max(List<? extends T> xs) {
        T best = null;
        for (T x : xs) if (best == null || x.compareTo(best) > 0) best = x;
        return best;
    }

    public static void main(String... args) throws Exception {
        int[] a = {1, 2, 3}; int[][] m = new int[2][3];
        String s = "tab\t\"quoted\" \\ é \101";
        char c = 'A';
        var list = List.of(1, 2).stream().map(x -> x * 2).collect(Collectors.toList());
        BiFunction<Integer, Integer, Integer> add = Integer::sum;
        Object o = switch (a.length) { case 1, 2 -> "few"; default -> { yield "many"; } };
        if (o instanceof String str && !str.isEmpty()) System.out.println(str);
        long big = 0xFFFF_FFFFL; float f = 1.5f; double d = 1e-9, h = 0x1.8p1;
        outer: for (;;) { break outer; }
        synchronized (Main.class) { assert a != null : "msg"; }
        try (var in = new java.io.StringReader("x")) { } catch (IOException | RuntimeException e) { throw e; } finally { }
    }
}

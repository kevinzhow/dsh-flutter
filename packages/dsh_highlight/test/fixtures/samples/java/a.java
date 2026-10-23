package com.example.demo;

import java.util.*;
import static java.lang.Math.max;

@FunctionalInterface
interface Visitor<R> { R visit(Node n); }

/**
 * Javadoc comment with {@code code}.
 */
public abstract class Node<T extends Comparable<T>> implements Iterable<T> {
    private static final int LIMIT = 0x7F + 1_000;
    protected final List<T> items = new ArrayList<>();

    @Override
    public Iterator<T> iterator() { return items.iterator(); }

    public synchronized <R> R accept(Visitor<R> v) throws IllegalStateException {
        String s = "quote \" tab\t unicode \u0041";
        char c = '\n';
        long big = 123L;
        double d = 1.5e-3f;
        if (s.isEmpty() || c == 'x' && big > 0) {
            throw new IllegalStateException("empty: " + s);
        }
        for (T item : items) {
            switch (item.toString()) {
                case "a" -> System.out.println(item);
                default -> { continue; }
            }
        }
        var text = """
            text block
            """;
        return null;
    }

    enum Kind { A, B }
    record Pair(int a, int b) {}
}

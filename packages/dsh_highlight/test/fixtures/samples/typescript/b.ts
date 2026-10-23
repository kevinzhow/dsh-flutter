import { readFile } from 'node:fs/promises';
import type { Config } from './config';

enum Level { Low = 1, High = 10 }

interface Shape<T extends object> {
  readonly id: string;
  area(): number;
  tags?: Array<T>;
}

abstract class Base<T> implements Shape<{ a: T }> {
  private cache = new Map<string, T>();
  static count = 0;
  constructor(public readonly id: string, protected size: number) {
    Base.count++;
  }
  abstract area(): number;
  async load(path: string): Promise<string> {
    const raw = await readFile(path, 'utf8');
    return raw.replace(/\s+/g, ' ').trim();
  }
}

type Maybe<T> = T | undefined | null;
declare module 'foo' {
  export const bar: string;
}

const handlers: Record<string, (x: number) => number> = {
  double: x => x * 2,
  square: (x) => x ** 2,
};

/* multi
   line
   comment */
let value = handlers['double']?.(3) ?? 0;
for (const [k, v] of Object.entries(handlers)) {
  value += v(k.length);
}

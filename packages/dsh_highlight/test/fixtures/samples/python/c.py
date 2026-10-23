#!/usr/bin/env python3
# -*- coding: utf-8 -*-
from __future__ import annotations
import asyncio as aio
from . import sibling
from ..pkg import (a,
                   b as bee)

def deco(fn):
    @functools.wraps(fn)
    def wrapper(*a, **kw):
        return fn(*a, **kw)
    return wrapper

class Meta(type):
    def __new__(mcs, name, bases, ns, **kw):
        return super().__new__(mcs, name, bases, ns)

@deco
async def main(argv: list[str] | None = None, /, *, verbose: bool = False) -> int:
    if (n := len(argv or [])) > 3:
        print(f"{n=} {argv!r:^20} {'x' if n else 'y'} {n:>{width}}")
    data = {k: v for k, v in zip("ab", range(2))}
    nums = [x * 2 for x in range(10) if x % 3 == 0 and x not in (3, 9)]
    s = "implicit " "concat" 'it''s'
    total = sum(nums) \
        + len(data)
    lam = lambda x, y=2, *z, **w: (x, y)
    try:
        await aio.sleep(0.1)
    except* ValueError as eg:
        pass
    assert isinstance(total, int), "must be int"
    del data["a"]
    global counter
    print(0b101, 0o17, 0xFF, 1_000, 3.14j, 1e-3, ...)
    return 0

if __name__ == "__main__":
    raise SystemExit(aio.run(main()))

import re, sys
from dataclasses import dataclass

@dataclass(frozen=True)
class Point:
    x: int
    y: int = 0

def parse(line: str):
    m = re.match(r'(\w+)=(\d+)', line)
    if not m:
        return None
    key, val = m.groups()
    match val:
        case "0":
            return key, 0
        case _ if val.isdigit():
            return key, int(val)
    return None

if __name__ == "__main__":
    for ln in sys.stdin:
        print(parse(ln.strip()) or 'skip')
    total = sum(x for x in range(5))
    print(f"total={total!s} {'nested'} {{literal}}")

"""Module docstring spanning
multiple lines."""
import os
from typing import Optional, List

CONSTANT = 3.14e-2
PATTERN = r"^\d+\s*(?P<name>[a-z]+)$"


@decorator(arg=1)
class Account(Base, metaclass=Meta):
    """Class docstring."""

    count: int = 0

    def __init__(self, owner: str, *args, balance: float = 0.0, **kwargs) -> None:
        super().__init__()
        self.owner = owner
        self._items: List[int] = [i ** 2 for i in range(10) if i % 2]

    @property
    def label(self) -> Optional[str]:
        return f"{self.owner!r:>10} has {self.balance:.2f} \n"

    async def fetch(self, url):
        async with session.get(url) as resp:
            return await resp.json()


def helper(x, y=lambda a: a + 1):
    # comment
    try:
        result = x // y(2)
    except (ValueError, ZeroDivisionError) as exc:
        raise RuntimeError("failed: %s" % exc) from exc
    finally:
        print('done', end='')
    return result if result else None

text = '''triple
quoted''' + b"bytes\x00" + 'it\'s'
with open(os.path.join("a", "b")) as fh, open("c") as g:
    data = {**{"k": 1}, "list": [1, 2, *rest]}

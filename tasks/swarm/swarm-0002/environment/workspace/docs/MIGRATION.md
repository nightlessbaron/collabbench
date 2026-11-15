# Migrating from legacy.storage to storex

`legacy.storage` is being removed. Every module must use the `storex` client instead:

```python
from storex import Missing, store
```

| legacy.storage | storex | What changed |
|---|---|---|
| `get(key, default=None)` | `store.fetch(key).value` | `fetch` returns a `Record`; a missing key raises `storex.Missing` (a `KeyError`) instead of returning a default |
| `put(key, value, ttl=None)` | `store.put(key, value, ttl=None)` | `ttl` is keyword-only and must be a `datetime.timedelta`; an int raises `TypeError` |
| `scan(prefix)` | `store.scan(prefix, cursor=None)` | returns one `Page` of at most 50 `Record`s (`.key`, `.value`); pass `page.next_cursor` back to get the next page; `next_cursor` is `None` on the last page |
| `delete(key)` | `store.remove(key)` | returns nothing; a missing key raises `storex.Missing` instead of returning `False` |
| `incr(key, by=1)` | `store.add(key, by=1)` | same behaviour: a missing counter starts at 0; returns the new value |

Reading every record under a prefix:

```python
records, cursor = [], None
while True:
    page = store.scan(prefix, cursor=cursor)
    records += page.items
    if page.next_cursor is None:
        break
    cursor = page.next_cursor
```

Migrated code must keep each module's public functions and their behaviour.

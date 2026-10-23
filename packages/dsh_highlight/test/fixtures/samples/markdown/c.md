# Heading with `code` and *emphasis* #

## Lists and code

1. First
   ```js
   console.log('in list');
   ```
2. Second with **bold _nested italic_ text**
   - sub item [link](<url with spaces> 'title')
   - another

* [ ] unchecked
+ plus item
- minus item

> Quote with `code`
> ```sh
> ls -la
> ```

| Left | Center | Right |
|:-----|:------:|------:|
| `a`  | **b**  | [c](d) |

<details>
<summary>HTML block</summary>

Inside *markdown* again.

</details>

Auto link <mailto:a@b.co> and bare https://example.org and footnote[^1].

[^1]: Footnote text.

Line with trailing backslash\
and hard break.

***

Image ref ![alt][img] and [collapsed][] and [shortcut].

[img]: ./a.png "Title"
[collapsed]: <http://x.y>
[shortcut]: /s

```python title="x.py"
def f(): return 1
```

````md
```inner
nested fence
```
````

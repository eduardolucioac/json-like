# Changelog

## 2026-10-29 — one case rule, and the tests caught up

### Case

The library already followed one rule without exception — `local` inside a
function is `lower_case`, anything at script or global scope is `UPPER_CASE` —
but the test suite and `prov.bash` mixed the two, because I wrote them that
way. They now follow it, and a test enforces it on every file.

It is worth enforcing rather than agreeing to: results come back through
namerefs, and a local whose name matches the caller's variable makes the
reference point at itself. That is why every internal nameref here carries a
suffix, and why the two scopes should not look alike.

The test earned its place immediately: normalising the suite, I renamed a
`local rtn_code` inside `t_fails` to upper case, and the new check failed the
build on it.

### Tests caught up

- The `to_json` target-first signature: that a document can go into a variable,
  that the variable and `-` agree, and that an indent reaches the variable too.
- What `from_json` must refuse, and — just as important — what it must NOT.
  A key merely shaped like the notation is a key: `{"o.x":1}`, `{"i.0":1}`,
  `{"e.{}":1}`, `{"0":1}`, `{"+":1}` all load and come back out unchanged,
  because the reader escapes keys itself instead of going through the tag
  parser. It can therefore load documents that `set` could not have built.

207 tests became 220.

## 2026-10-29 — "to_json" returns like everything else

`json_like.to_json` wrote to stdout and took the object id first, which made
it the one function in the library that did not follow its own convention.
Every other function that produces something takes the TARGET first: a
variable name to fill in, with "-" meaning stdout.

```bash
declare document
json_like.to_json document "$MY_OBJ" 4
echo "$document"

json_like.to_json - "$MY_OBJ"        # stdout, as before
```

`json_like.from_json` already worked this way and did not change: it takes the
name of a variable and the object is born filled, exactly as "set_obj" leaves
one empty.

## 2026-10-28 — the empty key goes, and the suite moves

### No empty key, anywhere

`{"": 1}` is valid JSON and the library used to hold it at any level except
the first, where its flattened path would be the empty string — which is how
the root itself is spelled, and which BASH will not take as an array
subscript. That split was the problem: holding a key in one position and
refusing it in another is a positional exception, and a positional exception
is how confusing errors are made. It is now refused everywhere, by `set` and
by `from_json` alike, with one message.

The cost was measured before the decision: **one file in three hundred** on
this system uses an empty key — `/usr/share/containers/policy.json`, where
`transports["docker-daemon"][""]` means "any registry". That document is now
out of reach, and wrapping does not help since the key sits deep. Small, real,
and worth the single rule.

### The suite in parts, and a util folder

`json-like-tests.bash` became `test/test.bash`, split the same way the library
was: a harness the parts rely on, then one part per theme, sourced in a fixed
order that is spelled out rather than looped over.

```
test/test.bash          run THIS
test/harness.bash       the counters and the assertions
test/basics.bash        lifecycle, objects, arrays, subtree reads
test/characters.bash    values and keys holding whatever they like
test/notation.bash      the tags, and what they free up
test/containers.bash    empty containers, value versus container
test/deleting.bash      deleting, and the caches after it
test/json_text.bash     reading JSON in and writing it back out
test/sources.bash       the source files themselves
test/performance.bash   the timings, with --perf
```

`try-catch.bash` is used by the suite, so it moved to `util/` rather than
leaving the project. The parse check now covers `test/` and `util/` too, which
caught two stray lines the split had dragged into `performance.bash`.

## 2026-10-28 — what the root cannot be

A non-object root stays refused, deliberately. RFC 8259 allows any value as a
JSON text; this model has no room for one, and the decision was taken with the
numbers in hand: of 368 real JSON files on this system, 324 have an object at
the root, 44 an array, and **none** a scalar. Refusing scalars costs nothing
because nobody writes them. Refusing an array at the root costs the 12%, and
wrapping is one line.

What changed is that the library now handles it properly instead of nearly.

### Two defects, same cause

Looking into what an array at the root would take turned up something already
broken. The root path is the empty string, and BASH refuses an empty array
subscript — so the empty key, which is valid JSON and which the library holds
at any depth, collided with the root at the first level:

- `json_like.set "$OBJ" "s.V" "o."` was refused with a message that was simply
  false: *the path "" already holds items*, about an object with nothing in it;
- `json_like.from_json OBJ '{"":"x"}'` **crashed on the subscript, returned 0,
  and left an empty object behind** — a document from a real file would have
  taken the read down in silence.

Both now say what is actually wrong, and the reader creates nothing when it
refuses. The eval of a parsed document is checked as well: if the parser and
the loader ever disagree about what is representable, the object is taken back
out rather than handed over half filled.

### Better refusals

`from_json` now names what it found at the root and what to do about it:

```
ERROR! The root of a "json-like" object is always an object, and this
document has an array at the root. Wrap it under a key to carry it.
```

13 new tests: every shape the root cannot be, that each refusal leaks no
object, and that the empty key still works below the first level and still
goes back out. 194 became 207.

## 2026-10-28 — reading JSON in, and the library in parts

### `json_like.from_json`

The other half of the pair, in AWK, with no `jq`: a recursive descent parser
over a real tokeniser. Strings with every escape the grammar allows, `\uXXXX`
including surrogate pairs, the number grammar, arbitrary nesting, and errors
that say what was wrong and where.

```bash
declare DOC
json_like.from_json DOC '{"window":{"width":563}}'
json_like.from_json DOC < settings.json
```

A number keeps the text it was written as, so `1E+10` goes back out as
`1E+10` rather than as whatever a float would print.

**Text in, text out, nothing else in the loop:** 23 real JSON documents from
this system read with `from_json`, written back with `to_json`, and compared
normalised. All 23 identical. The other 9 of the sample have an array at the
root, which the library does not hold and now refuses plainly instead of
wrapping behind the caller.

The parser runs under `LC_ALL=C` on purpose. It decodes `\uXXXX` by emitting
UTF-8 one byte at a time, and anywhere else `%c` hands back a character and
re-encodes what is already encoded — measured, not assumed: `sprintf("%c",195)`
gives one byte under C and a two byte `Ã` under a UTF-8 locale.

### The library in parts

`json-like.bash` was 1616 lines. It is now a 172 line entry point that sources
six parts in a fixed, spelled out order:

```
json-like/bootstrap.bash   where the library is, and the AWK it loads
json-like/object.bash      creating and destroying objects
json-like/caches.bash      the type and length caches
json-like/path.bash        a path in, the metadata every operation needs out
json-like/data.bash        the operations that reach AWK, and the rules
json-like/api.bash         the public functions
```

The AWK programs moved to `awk/` and were named for what they are:
`json-like-core.awk`, `json-like-to_json.awk`, `json-like-from_json.awk`.

### Documentation

All 24 functions were rewritten to the same shape: what it does, then
`ARGUMENTS` with the type of each and whether it is required, `RETURNS`, and
`SIDE EFFECTS` where there are any — which in BASH, with namerefs and global
arrays, is where most of the surprises live.

Writing them turned up its own trap: an apostrophe inside a `: '...'` docstring
closes it and swallows the rest of the file. Two tests now guard it — every
source file has to pass `bash -n` with no warning, and every function has to
carry a docstring.

### Not done

A named argument layer, in the shape of the `f_validate_n_set` scheme from
`window-like-i-want`. Measured first: it costs ~46 us a call, which is +9% on
the public API and +113% when applied to every internal call, since one `set`
makes twelve. It also does not fit — the scheme takes a fixed set of named
attributes and the path here is variadic. The docstrings carry the contract
instead, at no runtime cost.

## 2026-10-28 — writing JSON out, and a lossy escape fixed

### `json_like.to_json`

The library now emits JSON text, in AWK, with no `jq` and no other outside
help. The codec lives in its own file, [json-like-codec.awk](json-like-codec.awk),
so that `json-like.awk` — a surgical editor of flattened paths, and the most
carefully tested part of the project — is left exactly as it was.

```bash
json_like.to_json - "$OBJ"        # compact
json_like.to_json doc "$OBJ" 2    # indented, into a variable
```

Each value comes out in the shape of its type, which is what the value tags
bought: `n.563` is `563`, `s.563` is `"563"`. Strings are escaped per RFC 8259
section 7, empty containers come out as `{}` and `[]`.

Checked against `jq` as an oracle over 32 real JSON files from this system:
loaded, written back out, and compared normalised. **32 of 32 are identical**,
4964 leaves. `jq` is a test oracle here and nothing else — the library never
calls it.

### A lossy escape, found and fixed

Writing the serialiser meant splitting flattened paths back into components,
and that turned up a real defect in how they were built.

The path escaping protected `.`, `[` and `]` so a key could contain them, but
left the escape character itself alone. A key ending in a backslash, joined to
a child, produced the same stored path as a single key holding a dot:

```
{"a\\": {"b": 1}}  ->  a\.b
{"a.b": 1}        ->  a\.b
```

Two different documents, one storage key — and whichever was written second
silently replaced the first. Doubling the backslash first makes the mapping one
to one, and makes the structural characters exactly those preceded by an even
number of backslashes, which is what the splitter needs anyway. Four tests pin
it.

### Also

- **The AWK dependency is now stated plainly in the README**, along with what
  it is not: no `jq`, no Python, no compiled helper. `awk` is required by POSIX
  and ships in the base install everywhere, which is why a clone runs where it
  lands.
- **"No serialiser" left the Limitations list.** What replaced it in Possible
  future work is the other half: `json_like.from_json`, a real tokeniser and
  parser for JSON text, also in AWK. It is the larger of the two.
- 162 tests, up from 142.

## 2026-10-28 — the six JSON types

The value now carries its JSON type, the same way a path item carries its kind
and for the same reason: `8080` alone cannot say whether it is the number or
the string, and deciding from the characters is what makes a library emit
`true` where the document said `"true"`.

```bash
json_like.set "$OBJ" "s.MY SENSORS" "o.window" "o.title"
json_like.set "$OBJ" "n.563"        "o.window" "o.width"
json_like.set "$OBJ" "b.true"       "o.window" "o.visible"
json_like.set "$OBJ" "z.null"       "o.window" "o.parent"
```

`s.` string, `n.` number, `b.` boolean, `z.` null. Null needs a letter of its
own because `n.` is taken by number — `n.null` would be the number whose text
is `null`, which is not a number.

With `object` and `array` already coming from the path side, **all six types of
RFC 8259 are now representable**, and the symmetric half of the problem goes
with it: `s.8080` and `n.8080` are different things, as are `s.true` and
`b.true`.

A number is validated against the grammar in RFC 8259 section 6 and a boolean
against `true`/`false`, so a value that would not parse is refused where it is
written rather than where it is read. `n.007` is refused: JSON has no leading
zeros.

The tag is consumed on the way in. `get` returns the value itself, `8080`, not
`n.8080` — reads stay untagged, as they already were for paths.

### Where the type lives

In the existing type cache, whose vocabulary grew from `0 container | 1 array`
to include `3 string | 4 number | 5 boolean | 6 null`. A fourth cache would have
needed its own AWK pass on every delete; this one is already renumbered by the
passes that exist.

Extending it surfaced a latent bug the suite caught at once: the raw cache value
was being handed to AWK as `key_ends`, which only ever means "do the rows end
with an index". It worked while the only values were 0 and 1. Everything that
is not an array now collapses to 0 before the call.

### Also

- **21 new tests**: the four value tags, the grammars that guard them, the
  distinction between `s.8080` and `n.8080`, and that a typed value is still a
  value — it cannot hold items and is not indexable. 121 became 142.
- **The README no longer says "Everything is a string. There is no type
  system."** That was true, and is not any more. The limitation it became:
  types are remembered, not enforced — the value is still stored and returned
  as text, because that is what BASH has.

## 2026-10-28 — deleting a leaf no longer touches AWK

A `delete` used to spawn up to three AWK processes no matter what was being
deleted. For a **leaf** none of that work exists: only a value owns a row of
its own in the data array, and the library refuses to let a value also hold
items, so a path with a row is a leaf with certainty — nothing below it to
collect, no sibling to renumber. Two `unset` calls finish it.

```
150 delete by key   before ~1650 ms   after ~77 ms
one delete, object of 1000 keys   18 737 us -> 482 us   (39x)
```

The three operations that genuinely have to walk every key still go through
AWK: a subtree read, a subtree delete, and deleting an array element. Nine
tests pin the boundary — a container is not a leaf, an array element is not a
leaf even though it owns a row, the type cache entry has to go with the value,
and a missing path still fails.

### A documentation correction

The Performance section claimed the ~12 ms of a `delete` was the three
processes, and Possible future work offered to merge them for "roughly 3x".
Both were wrong, and measuring said so: on a thousand-key object a single pass
spends ~1.4 ms starting up and reading its input against ~6.1 ms walking the
rows. **The fork is 18% of a pass.** Merging three passes into one saves the
two extra forks, about 2.8 ms of a 27 ms delete — a ~10% improvement to what
still reaches AWK, not a multiple. The item is kept, with that stated.

The other two future-work items were given the same treatment: a serialiser has
to decide what it does about types first, since every value here is a string
and `{"port": 8080}` would come back as `{"port": "8080"}`; and key ordering
makes nothing *correct* under RFC 8259, where member order is not significant,
while its cost would land on `set` and `delete`, which are the fast paths.

## 2026-10-28 — tagged paths: no unreachable key

The notation settled here, after two intermediate shapes that are described
below for the record. Both marked only the *structural* items and left keys
bare, which always leaves some key spelled like the marker unreachable. The
final notation tags **every** item instead, and the tag is split off at the
**first** dot, so everything after it is literal.

```bash
json_like.set "$OBJ" "MY SENSORS" "o.window" "o.title"
json_like.set "$OBJ" "kde"        "o.window" "o.tags" "i.+"
json_like.set "$OBJ" ""           "o.window" "o.extras" "e.{}"
```

| Tag | Item is |
|---|---|
| `o.` | an object key, taken literally |
| `i.` | an array index (`i.0`, `i.-1`, `i.+`) |
| `e.` | an empty container, as the last item (`e.{}`, `e.[]`) |

Every key a JSON document can hold is now reachable: `o.0` is the key `0`,
`o.i.1` is the key `i.1`, `o./0` is the key `/0`, and `o.` is the empty key,
which JSON allows and which was refused before. **The Limitations section no
longer has a notation entry at all** — there is no escape to remember and no
key that cannot be written.

### Only `set` is tagged

`set` is the only function that creates structure, so it is the only one that
could guess wrong. `get`, `get_length` and `delete` walk what already exists,
and the type cache records what every level is, so the parent decides: under an
array the item is an index, under an object it is the key itself. Their items
carry no tag.

```bash
json_like.get value "$OBJ" "window" "tags" "0"    # index: "tags" is an array
json_like.get value "$OBJ" "map" "0"              # key:   "map" is an object
```

That asymmetry is deliberate — reads are the frequent operation and stay terse
— and it is safe because a read never has to invent a level. A tagged path
copied into a read fails loudly in all but the contrived case of a key
literally named `o.something`.

### The two shapes it replaced, and why they were not enough

Both are gone; neither was ever released.

- A **backslash** marked the index (`\0`, `\+`, `\-1`). It fixed the real
  problem — see below — but a key spelled `\0` was unreachable, and a lone
  backslash is awkward to write in BASH: `"\"` is a syntax error, and a
  computed index needed `"\\$i"`.
- A **forward slash** replaced it (`/0`, `/+`, `/-1`, `/{}`, `/[]`), which needs
  no escaping anywhere and made a computed index plainly `"/$i"`. The
  unreachable-key hole remained, just moved.

### The problem all three were solving

An index used to be any path item made only of digits, decided from the
characters alone. An object key in JSON is an arbitrary string, so `"0"`,
`"4217"`, `"+"` and `"-1"` are all legal keys — and none could be written.
`/usr/share/iso-codes/json/iso_4217.json`, whose top-level key is `"4217"`, was
100% unwritable. About 11% of the JSON files on this machine carry at least one
purely numeric object key.

Worse than the refusals was the quiet case. An object whose keys happened to be
`"0"`, `"1"`, `"2"` was silently turned into an **array**: it gained a length,
answered to negative indexes, and a `delete` renumbered it, so the surviving
values ended up under the wrong keys. No error at any point.


Two changes, decided together. The operator is written with a **forward slash**
because a slash needs no escaping anywhere in BASH, which a backslash does: a
computed index is plainly `"/$i"`.


### Empty containers

`{}` and `[]` hold no value, and a model that only stores values had nowhere to
put them. They are now asked for with a trailing `/{}` or `/[]`, which is not a
level of its own: it describes the container at the path before it.

```bash
json_like.set "$OBJ" "" "window" "tags" "/[]"
```

They live **only in the type cache**, with no row in the data array, so they can
never be confused with the literal strings `"{}"` and `"[]"` — which remain
ordinary values. That also means `get`, `get_length` and `delete` had to stop
treating "no data row matched" as a failure when the path is a known container.

This is what finally allows `[{}, {"a": 1}]`: the empty object at index 0 keeps
the array dense so index 1 can be written.

Two defects were found by probing the edges of the new feature and fixed before
it shipped:

- an empty container could be written **on top of an existing value**, leaving
  the path holding a value and a container type at once;
- deleting an element from an array whose elements were empty containers threw
  away the renumbering of the rows above it. The real cause was that the AWK
  `delete_path_array` mode demanded a match, which is redundant — the BASH side
  has already validated the index against the array length before AWK runs.

### Result


| | before | after |
|---|---|---|
| real JSON files carried | 29 of 32 | **32 of 32** |
| leaves round-tripped | 3230 | **3302**, none wrong |
| `iso_4217.json` | 0 of 534 | 534 of 534 |
| `tutor.tutor.json` | 0 of 31 | 31 of 31 |
| `vmaf_v0.6.1mfz.json` | 45 of 46 | 51 of 51 |

Every file in the sample now round-trips exactly, empty containers included.

### Also

- **The Limitations section lost its notation entry entirely.** Nothing about
  how a path is written restricts what can be stored any more.
- **38 new tests** for the tags, for the keys they free up and for empty
  containers. Among them: 19 key shapes round-tripped in one go — `0`, `+`,
  `-1`, `007`, `i.0`, `o.Name`, `e.{}`, `/0`, `{}`, `.`, `..`, `a.b`, `x[0]`,
  `""` and a lone space — and the one that pins the silent conversion shut, a
  map of numeric keys that must not answer `get_length`. 74 tests became 112.
- **Test data renamed** so the shape under test reads off the call: a path item
  says what it is (`ObjectKey`, `ArrayKey`, `NameKey`) and a value says it is a
  value (`Value`, `Value1`).
- **Docstrings** moved into the functions, using the `: '...'` idiom, for all
  23 functions in `json-like.bash` and all 6 in `try-catch.bash`.

### Verified, not assumed

Besides the suite, three adversarial probes were written to break the library
rather than confirm it, and all pass: 110 hostile values and keys (embedded
`]="`, a whole `declare -A` line, newlines, trailing backslashes, emoji, RTL,
combining marks, a 20 000 character value) repeated under four locales
including `C`; key-escaping injectivity; arrays of hostile values with
renumbering; 50 levels of nesting; a 500-key subtree; a 300-element array.

No defect was found in the AWK layer.


## 2026-10-21 — split out of `window-like-i-want`, and finished

This library was written inside
[window-like-i-want](../window-like-i-want) and lived in its
`bash-script/utils/` directory. It was never wired into that project's run
sequence — it is not sourced by its entry point, and there is not a single
`json_like.*` call outside the library and its own tests — so it was moved into
a project of its own.

Nothing in the library changed in the move. The previous history is in
[_BAK/](_BAK/), and the fixes below were made just before the split.

### `json-like` — correctness

Each of these was reproduced before being fixed, and each has a test in
[json-like-tests.bash](json-like-tests.bash)
that fails without the fix.

1. **Deleting anything printed a BASH arithmetic error.**
   `_resolve_path` never filled in the `delete_array` metadata field for a
   non-indexable path, leaving the literal `"."` it had been initialised with,
   so `(( "." == 1 ))` blew up. All numeric metadata fields now start at `0`,
   and the field is set on both branches.

2. **Deleting a whole array always failed.**
   The check that spots *"the path names an array but ends without an index"*
   was looking at the type of the **parent** path instead of the item's own. It
   therefore never fired, and the path was built as `a[arr]` rather than
   `a.arr`. The two checks that were conflated here are now separate: *is the
   parent an array* (which must stay, it is what rejects
   `set "$O" v "arr" "name"`) and *is this item an array*.

3. **Two AWK modes could never succeed.**
   `json-like.awk` ended with an unconditional `exit 1` for
   `unset_type_array`/`unset_length_array` — a debugging leftover. Those modes
   maintain the type and length caches when an array element is deleted, so the
   caches were silently never updated.

4. **The caches were not renumbered after an array element was deleted.**
   Even with (3) fixed, those modes only *removed* rows; they did not shift the
   higher indexes down the way the data was shifted. A stale length makes a
   later `+` overwrite a live element, and a stale type makes a path resolve
   against an element that no longer exists. They now run the same
   remove-and-renumber pass as the data.

5. **Every successful delete printed a bogus error to stderr.**
   The cache maintenance modes required at least one matching row, but a leaf
   has no descendants and an array element need not appear in either cache.
   "No match" is now an error only for `get`, `delete_path` and
   `delete_path_array`.

6. **`json_like.set` wrote a debug line to stdout.**
   A leftover `echo "  > json_like._set_length ..."` on every array write. Any
   caller using command substitution got it mixed into their data. Removed.

7. **`set` with a negative index silently appended** instead of replacing. It
   fell into the `+` branch. Negative indexes are now resolved properly for
   `set` too, so `set "$O" v "arr" "-1"` replaces the last element.

8. **`+` passed to `get` or `delete` crashed** with a raw
   `(( 3 + + ))` arithmetic error. `+` is now rejected for anything but `set`,
   and negative indexes for anything but `get`/`get_length`/`delete`.

9. **An empty path item produced a raw `bad array subscript`.** Now rejected
   with a message.

10. **`get_length` handled a single-item path differently.** It bypassed path
    resolution, so `.`, `[` and `]` in a key were not escaped. The internal
    fast path is now a separate function, `_get_length_by_path`, and the public
    one always resolves.

11. **A path could hold a value and items at the same time**, which is not
    representable as JSON: `set "$O" s "a"` followed by `set "$O" c "a" "b"`
    left both. Both directions are now rejected, with O(1) checks, and
    validation runs **before** any write so a rejected `set` changes nothing.

12. **`json_like.get` mishandled an indexed-array target.** `declare -a` now
    gets a clear error instead of a surprising scalar assignment.

### `json-like` — library hygiene

13. **The library installed `trap ... EXIT INT TERM HUP`.** BASH keeps one
    handler per signal, so sourcing it silently discarded the host script's
    trap — including the one of the project it then lived in. The try/catch
    code that needed it was moved to
    [try-catch.bash](try-catch.bash), which
    installs no trap and instead exposes `prog_concepts.cleanup` for the
    consumer to call. `json-like.bash` now has no dependencies at all.

14. **`SCRIPT_DIRECTORY` was defined at the top**, under a `!!!!!! REMOVE ME`
    banner, clobbering the variable of any script that sourced the library. It
    is now the private `_JSON_LIKE_DIR`.

15. **The library sourced its own test file** at the bottom, so sourcing it ran
    the tests and then `exit 0`. Removed.

16. **`prog_concepts.try` leaked a temporary file per call.** It created the
    file with `mktemp` even when the guarded command never wrote to stderr. It
    now reserves a name with `mktemp -u`; the file is created only if needed.

17. **`prog_concepts.catch` did not return 1** when a default catch handler was
    set, unlike the other branch.

18. **Dead code removed.** `_delete_path`, `_unset_type` and `_unset_length`
    were superseded by their `_new` counterparts but still called, running O(n)
    BASH loops that redid work AWK had already done. The `_new` suffixes are
    gone and `_unset_type_new`/`_unset_length_new` are now one parameterised
    `_unset_cache`.

### `json-like` — performance

19. **`get` is about 2.7x faster** (176 ms -> 66 ms per 150 reads). It has to
    know whether its target is an associative array, and was capturing
    `declare -p`, which **forks on every read**. On BASH 5.1+ it now uses
    `${!name@a}`, which costs nothing; 4.3–5.0 keep the fork.

20. **Cache passes are skipped when the cache is empty**, removing one AWK
    process per delete for objects that hold no arrays.

21. **`set_obj` no longer shells out.** It read `/proc/sys/kernel/random/uuid`
    through `uuidgen`/`tr` pipelines; it now reads it with `read` and
    transforms it in BASH, falling back to `uuidgen` only if that file is
    missing. It also guards against reusing the arrays of a live object.

### `json-like.awk`

22. `FS`/`OFS` were set to `""` — a gawk-only extension — but **no field is
    ever referenced**: every read is `$0` and the declaration is walked with
    `substr`. Removed, which is both faster and portable.
23. An unknown mode now fails with a message naming it, instead of falling
    through.
24. The magic offsets `31` and `7` in `get_key_path_from_declaration` are now
    derived with `length()` from the literal prefix and suffix they stood for.
25. The three remaining `--lint` warnings were fixed (uninitialised arguments,
    unclosed `/dev/stderr`). `--lint` is now clean apart from the deliberate
    "parameter shadows global" notices, which are the AWK idiom for locals.

### Tests

[json-like-tests.bash](json-like-tests.bash)
was rewritten. It had become a single live test followed by ~600 commented-out
lines and three `exit 0`s.

It is now **74 assertions** with pass/fail counts and a meaningful exit status,
covering the object lifecycle, objects, arrays, arrays of objects, subtree
reads, 18 special values and 6 special keys, the collision rules, every form of
delete, cache consistency after a delete, and the try/catch helper. Plus
optional timings under `--perf`.

> A trap for anyone extending it: assertions run their command through `t_run`,
> which redirects to temporary **files**. Command substitution would put the
> call in a subshell and roll back every mutation, quietly turning
> "delete, then check it is gone" into a test of nothing. Eight tests failed
> that way on the first run of this suite.

### Verified

- Test suite: **74 passed, 0 failed**.
- `bash -n` clean on all three BASH files.
- `gawk --lint` clean on `json-like.awk` apart from the deliberate
  "parameter shadows global" notices, which are the AWK idiom for locals.
- The library leaves the host shell alone: no `SCRIPT_DIRECTORY` clobbering, the
  host `EXIT` trap intact, only `_JSON_LIKE_*` globals added.
- The BASH 4.3–5.0 fallback path exercised by forcing
  `_JSON_LIKE_HAS_ATTR_EXPANSION=0`.

### Not verified

Only GNU awk was available to test against. Nothing gawk-specific is used on
purpose — `FS` is left alone and no field is ever referenced — but `mawk` and
the BWK awk have not been exercised.

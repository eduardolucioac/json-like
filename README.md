# json-like

![json-like](./images/json-like.png)

Nested objects and arrays for BASH — which BASH itself does not have — reading
and writing **JSON text**, and needing nothing but BASH and `awk`.

```bash
source "./json-like/json-like.bash"

declare CONFIG
json_like.set_obj CONFIG

json_like.set "$CONFIG" "s.MY SENSORS" "o.window" "o.title"
json_like.set "$CONFIG" "s.kde"        "o.window" "o.tags" "i.+"

declare TITLE
json_like.get TITLE "$CONFIG" "window" "title"    # -> MY SENSORS
```

**IMPORTANT:** My life, my work and my passion is free software. Corrections, tweaks and improvements are very welcome (**pull requests** 😉)! Please consider giving us a ⭐, fork, support this project or even visit our professional profile (see [About](#about)). **Thanks!** 🤗

**Support free software and my work!** ❤️🐧

## Table of Contents

- [What it looks like elsewhere](#what-it-looks-like-elsewhere)
- [Requirements](#requirements)
- [Installing](#installing)
- [First example](#first-example)
  - [Why the last step matters](#why-the-last-step-matters)
- [Quick start](#quick-start)
- [Writing](#writing)
- [Reading](#reading)
- [API](#api)
- [JSON text](#json-text)
  - [Valid JSON this will not take](#valid-json-this-will-not-take)
- [Rules](#rules)
- [Limitations](#limitations)
- [Testing](#testing)
- [About](#about)

## What it looks like elsewhere

Every language with a JSON-shaped structure lets you reach into it. BASH does
not, which is why this exists. Compare — both produce exactly
`{"window":{"geometry":{"width":563},"tags":["kde"]}}`:

```bash
# json-like
json_like.set "$CONFIG" "n.563" "o.window" "o.geometry" "o.width"
json_like.set "$CONFIG" "s.kde" "o.window" "o.tags" "i.+"
```

```javascript
// JavaScript, from scratch, doing the same thing
if (config.window === undefined) config.window = {};
if (config.window.geometry === undefined) config.window.geometry = {};
config.window.geometry.width = 563;

if (config.window.tags === undefined) config.window.tags = [];
config.window.tags[config.window.tags.length] = "kde";
```

`config.window.geometry.width = 563` on its own **throws** if `window` does not
exist yet, and `config.window = {}` wipes whatever was already under it. Each
level has to be created *only if missing* — which is what the one call above
does, along with refusing a write that would make a path hold a value and
items at the same time.

Reading is the same story:

```bash
json_like.get TITLE "$CONFIG" "window" "title"
```

```javascript
const title = config?.window?.title;
```

## Requirements

| Requirement | Why |
|---|---|
| **BASH 4.3+** | the code relies on namerefs (`local -n`) |
| **`awk`** | every operation that has to look at more than one key |

Those two, and nothing else. No `jq`, no Python, no compiled helper. `awk` is
required by POSIX and ships in the base install everywhere, so a clone runs
where it lands.

BASH 5.1 or newer is faster on reads.

## Installing

**Clone the folder into your own project**, next to the script that is going to
use it:

```
my-bash-project/
  my-script.bash
  json-like/              <- the whole folder, as it is here
```

```bash
git clone https://github.com/eduardolucioac/json-like.git
```

Then source the entry point:

```bash
source "./json-like/json-like.bash"
```

`json-like.bash` is the **only** file to source — it finds everything else
relative to itself. A script that may be run from another directory should
resolve the path rather than trust the working one:

```bash
MY_SCRIPT_DIRECTORY="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" && pwd )"
source "$MY_SCRIPT_DIRECTORY/json-like/json-like.bash" || exit 1
```

It defines nothing but `json_like.*` functions and a few `_JSON_LIKE_*`
variables, and installs no traps.

## First example

Three steps: create, use, release.

```bash
#!/bin/bash

source "./json-like/json-like.bash"

# 1. CREATE. The variable receives an opaque id, not the data.
declare CONFIG
json_like.set_obj CONFIG

# 2. USE.
json_like.set "$CONFIG" "s.MY SENSORS" "o.window" "o.title"
json_like.set "$CONFIG" "n.563"        "o.window" "o.width"

declare TITLE
json_like.get TITLE "$CONFIG" "window" "title"
echo "$TITLE"                                     # MY SENSORS

# 3. RELEASE.
json_like.unset_obj CONFIG
```

### Why the last step matters

`CONFIG` never holds your data. It holds an **id**, and the data lives in
three global arrays named after that id:

```
JL_DATA_<ID>          the values
JL_TYPE_CACHE_<ID>    what kind of node each path is
JL_LENGTH_CACHE_<ID>  how long each array is
```

That is what lets an object be passed around by value — `"$CONFIG"` is a short
string — but it also means **the object does not go away when the variable
does**. Dropping the variable only throws away the label; the three arrays stay
declared, and nothing can name them any more.

It shows up fastest inside a function, where the variable is `local`:

```bash
make_one() {
    local OBJECT
    json_like.set_obj OBJECT
    json_like.set "$OBJECT" "s.x" "o.a"
}                       # OBJECT is gone. The three arrays are not.

for I in 1 2 3 4 5 ; do make_one ; done
```

Five calls leave five objects behind — fifteen global arrays that nothing
references and nothing will collect, because BASH has no garbage collector.
Add `json_like.unset_obj OBJECT` before the function returns and the count
stays at zero.

So: **every `json_like.set_obj` wants a matching `json_like.unset_obj`.** It
removes the three arrays and clears your variable, so a stale id cannot be
used by accident either.

A script that may exit early can hang it on a trap:

```bash
declare CONFIG
json_like.set_obj CONFIG
trap 'json_like.unset_obj CONFIG' EXIT
```

## Quick start

```bash
source "./json-like/json-like.bash"

# Create an object. The variable receives an opaque id.
declare CONFIG
json_like.set_obj CONFIG

# Write. One argument per level.
json_like.set "$CONFIG" "s.MY SENSORS" "o.window" "o.title"
json_like.set "$CONFIG" "n.563"        "o.window" "o.geometry" "o.width"
json_like.set "$CONFIG" "s.kde"        "o.window" "o.tags" "i.+"      # append
json_like.set "$CONFIG" "s.plasma"     "o.window" "o.tags" "i.+"

# Read into a variable, or straight to stdout.
declare TITLE
json_like.get TITLE "$CONFIG" "window" "title"
json_like.get -     "$CONFIG" "window" "tags" "0"

# How long is an array, and walk it.
declare HOW_MANY
json_like.get_length HOW_MANY "$CONFIG" "window" "tags"
for ((I = 0; I < HOW_MANY; I++)) ; do
    json_like.get - "$CONFIG" "window" "tags" "$I" ; echo
done

# A whole subtree, as a copy.
declare -A WINDOW=()
json_like.get WINDOW "$CONFIG" "window"

# Delete. An array element shifts the ones above it down.
json_like.delete "$CONFIG" "window" "tags" "0"

# Out as JSON, and release it.
declare DOCUMENT
json_like.to_json DOCUMENT "$CONFIG" 4
json_like.unset_obj CONFIG
```

## Writing

`set` is the only function that **creates** structure, so it is the only one
that could guess wrong. Its value and every path item carry a tag.

| Value tag | Is | Example |
|---|---|---|
| `s.` | a **string** | `s.MY SENSORS`, `s.8080` |
| `n.` | a **number** | `n.8080`, `n.-1.5e3` |
| `b.` | a **boolean** | `b.true`, `b.false` |
| `z.` | **null** | `z.null` |

| Path tag | Item is | Example |
|---|---|---|
| `o.` | an **object key**, taken literally | `o.title`, `o.0`, `o.+` |
| `i.` | an **array index** | `i.0`, `i.-1`, `i.+` |
| `e.` | an **empty container**, as the LAST item | `e.{}`, `e.[]` |

```bash
json_like.set "$OBJ" "s.MY SENSORS" "o.window" "o.title"
json_like.set "$OBJ" "n.563"        "o.window" "o.width"
json_like.set "$OBJ" "b.true"       "o.window" "o.visible"
json_like.set "$OBJ" "z.null"       "o.window" "o.parent"
json_like.set "$OBJ" "s.kde"        "o.window" "o.tags" "i.+"
json_like.set "$OBJ" ""             "o.window" "o.extras" "e.{}"
```

Between them the tags cover **all six JSON types**, and the split is on the
**first** dot, so everything after a tag is literal: `o.0` is the key `0`,
`o.i.1` is the key `i.1`. `i.+` appends; an index equal to the current length
appends too, and anything beyond it is refused, because arrays stay dense.

## Reading

`get`, `get_length` and `delete` take the item **plainly**. Under an object it
is the key, under an array the index — the library knows which is which, so
nothing is guessed from the characters.

```bash
json_like.get VALUE "$OBJ" "window" "tags" "0"     # index: "tags" is an array
json_like.get VALUE "$OBJ" "map" "0"               # key:   "map" is an object
json_like.get VALUE "$OBJ" "window" "tags" "-1"    # counted from the end
```

The value comes back as text: the tag is consumed on the way in, so `n.8080`
reads back as `8080`.

## API

| Function | Does |
|---|---|
| `json_like.set_obj <var_name>` | create an object, id into the variable *named* |
| `json_like.unset_obj <var_name>` | destroy it and clear the variable |
| `json_like.set <obj_id> <tagged_value> <path_item>...` | write, creating the levels it needs |
| `json_like.get <target> <obj_id> [<path_item>...]` | read a value, or a subtree |
| `json_like.get_length <var_name> <obj_id> <path_item>...` | element count of an array |
| `json_like.delete <obj_id> <path_item>...` | remove a path |
| `json_like.to_json <target> <obj_id> [<indent>]` | write the object out as JSON |
| `json_like.from_json <var_name> [<json_text>]` | read JSON into a **new** object |

Every function returns **0** on success and **1** on failure, writing the
reason to **stderr**. Nothing reaches stdout unless you ask with `-`.

**The target comes first** wherever something is returned, and it is a variable
*name*, not a value. `-` means stdout. For `get`, the shape of the result
follows the target: a plain variable gets the single value, a name already
declared `-A` gets the whole subtree, as a copy.

```bash
json_like.get VALUE   "$OBJ" "window" "title"    # one value
json_like.get -       "$OBJ" "window" "title"    # to stdout
declare -A SUBTREE=()
json_like.get SUBTREE "$OBJ" "window"            # the subtree
```

The plain idiom for failure:

```bash
json_like.get VALUE "$OBJ" "window" "title" || {
    echo "could not read the title" >&2
    exit 1
}
```

[util/try-catch.bash](util/try-catch.bash) is an optional helper for scripts
that would rather catch the message than let it reach stderr.

## JSON text

```bash
declare DOCUMENT
json_like.from_json DOCUMENT < settings.json       # or "$json_text"

declare AS_TEXT
json_like.to_json AS_TEXT "$DOCUMENT" 4
echo "$AS_TEXT"
```

Types survive the trip: `563` comes back a number and `"563"` a string, and a
number keeps the text it was written as, so `1E+10` goes back out as `1E+10`.
The reader validates as it goes and says where it stopped:

```
{"a":}       ERROR! unexpected character "}" at position 6.
{"a":007}    ERROR! expected "," or "}" at position 7.
```

### Valid JSON this will not take

Two shapes are refused on purpose. Both are legal JSON — RFC 8259 allows any
value as a document — and both are listed under [Limitations](#limitations)
with the reason.

| Document | What happens |
|---|---|
| `[1, 2]` | `The root ... has an array at the root. Wrap it under a key to carry it.` |
| `"text"` | `... has a string at the root ...` |
| `42` | `... has a number at the root ...` |
| `true` | `... has a boolean at the root ...` |
| `null` | `... has null at the root ...` |
| `{"": 1}` | `the empty key is not accepted at position 5.` |
| `{"a": {"": 1}}` | the same, at any depth |

A root that is not an object is the one that occurs in practice — about 12% of
JSON files carry an array at the top. Wrapping it is one line:

```bash
json_like.from_json DOCUMENT "$( jq '{root: .}' list.json )"
```

Everything else the format allows is taken, including the keys that merely
*look* like the notation — `{"o.x":1}`, `{"i.0":1}`, `{"0":1}`, `{"+":1}` all
load and come back out unchanged.

## Rules

Refused, because none of them can be represented as JSON — and refused
**before** anything is written, so a rejected call leaves the object untouched:

```bash
json_like.set "$OBJ" "s.scalar" "o.a"
json_like.set "$OBJ" "s.child"  "o.a" "o.b"      # a value cannot hold items

json_like.set "$OBJ" "s.v" "o.arr" "i.0"
json_like.set "$OBJ" "s.v" "o.arr" "o.name"      # an array takes only indexes

json_like.set "$OBJ" "s.v" "o.arr" "i.9"         # arrays stay dense
```

## Limitations

- **The root is always an object**, deliberately. A scalar there has no
  structure to navigate, and an array there has nowhere to keep its own type
  and length. `from_json` says which it found and suggests wrapping it under a
  key.
- **The empty key is not accepted**, deliberately and at every level. Valid
  JSON, but it would be the one key whose path is the empty string — which is
  how the root itself is spelled.
- **A key written exactly like a tag is unreachable through `set`.** `o.0` is
  the key `0`, so the key *literally named* `o.0` cannot be addressed. Every
  other key can, `0` and `+` and `-1` included. `from_json` has no such limit:
  it escapes keys itself, so it loads documents `set` could not have built.
- **Object keys have no order.** RFC 8259 says the order of members is not
  significant. Arrays, in contrast, are ordered and dense.
- **Values are text.** A value carries which of the six JSON types it is, but
  the value itself is stored and returned as text, because that is what BASH
  has.
- **Process local.** State lives in shell variables and dies with the shell.
- **Tested against GNU awk.** Nothing gawk-specific is used on purpose, but
  other implementations have not been exercised.

## Testing

```bash
./test/test.bash          # 222 integrity tests
./test/test.bash --perf   # and the timings
```

Exits 0 only if everything passed.

A single-path read or write is O(1) and stays in BASH, at roughly half a
millisecond. Only three operations reach AWK, because only they have to look
at every key: a subtree read, a subtree delete, and deleting an array element,
which renumbers the ones above it.

## About

This is free software and will stay that way. If it saved you some time, come
and say hello.

json-like 🄯 BSD-3-Clause — see [LICENSE](LICENSE)  
Eduardo Lúcio Amorim Costa  
Brazil-ES  
https://www.linkedin.com/in/eduardo-software-livre/

![Brazil](./images/brazil.png)

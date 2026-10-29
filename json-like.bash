#!/bin/bash
#
# json-like.bash - A nested data structure library for BASH, backed by AWK.
#
# PURPOSE
#
# BASH has associative arrays but no nested ones: you cannot put an array
# inside an array. This library works around that by FLATTENING a tree into a
# single associative array whose keys are paths:
#
#     declare -A JL_DATA_<ID>=(
#         [window.title]="MY SENSORS"
#         ["window.tags[0]"]="kde"
#         ["window.tags[1]"]="plasma"
#     )
#
# Hence "json-like": the shape of the data is JSON like (nested objects and
# dense arrays of strings), but it is neither JSON text nor a JSON parser. It
# is an in memory structure for BASH scripts that need more than flat
# key/value pairs and do not want to shell out to "jq" on every access.
#
# WHY AWK
#
# Reads and writes of a single path are O(1) and stay in BASH. Everything that
# has to inspect every key (fetching a subtree, deleting a subtree, removing an
# array element and renumbering the ones above it) is O(n), and BASH loops over
# associative arrays are slow enough to dominate the runtime. Those operations
# are handed to "awk/json-like-core.awk" as a single `declare -p` dump, processed in one
# pass, and read back with `eval`. See "awk/json-like-core.awk" for the protocol.
#
# USAGE
#
#     source "/path/to/json-like.bash"
#
#     declare MY_OBJ
#     json_like.set_obj MY_OBJ
#
#     json_like.set "$MY_OBJ" "s.MY SENSORS" "o.window" "o.title"
#     json_like.set "$MY_OBJ" "n.563"         "o.window" "o.width"
#
#     declare value
#     json_like.get value "$MY_OBJ" "window" "title"
#
#     json_like.unset_obj MY_OBJ
#
# Every public function writes its diagnostics to stderr and returns 0 on
# success or 1 on failure. Nothing is written to stdout unless you ask for it
# (see the "-" mode of "json_like.get").
#
# PUBLIC API
#
#     json_like.set_obj <var_name>
#     json_like.unset_obj <var_name>
#     json_like.set <obj_id> <value> <path_item>...
#     json_like.get <var_name>|- <obj_id> [<path_item>...]
#     json_like.get_length <var_name> <obj_id> <path_item>...
#     json_like.delete <obj_id> <path_item>...
#
# VALUES AND PATHS
#
# "set" tags EVERYTHING; the reading functions tag nothing. "set" is the only
# function that CREATES, so it is the only one that could guess wrong. The
# reading functions walk what is already there, and the caches record what every
# level is, so the parent decides.
#
#     THE VALUE, "<tag>.<value>"
#
#     "s.<string>"  .. a string
#     "n.<number>"  .. a number, checked against RFC 8259 section 6
#     "b.true" / "b.false" .. a boolean
#     "z.null"      .. null
#
#     EACH PATH ITEM, "<tag>.<item>"
#
#     "o.<key>"   .. an object key, taken literally
#     "i.<index>" .. an array index: "i.0", "i.-1", "i.+"
#     "e.{}"      .. an empty object, as the LAST path item
#     "e.[]"      .. an empty array, as the LAST path item
#
#     READING
#
#     the value .. returned as text; the tag was consumed on the way in
#     an item   .. the key under an object, the index under an array
#
# Between them the tags cover all six JSON types: object and array come from the
# path side, string, number, boolean and null from the value side.
#
# Every split is on the FIRST dot, so everything after a tag is literal. Every
# key a JSON document can hold is therefore reachable, including the ones shaped
# like the notation: "o.0" is the key "0", "o.i.1" is the key "i.1", and "o." is
# the empty key, which JSON allows. There is no escape and no unreachable key.
#
# An empty container is NOT a level of its own: it describes the container at
# the path before it, takes no value, and lives only in the type cache. It can
# never be confused with the literal strings "{}" and "[]", which are values.
#
# Keys may contain "." , "[" and "]"; they are escaped internally so they
# cannot be mistaken for path syntax. Values are opaque strings and may contain
# anything, newlines and quotes included. An empty path item is rejected.
#
# INTERNAL STATE
#
# "json_like.set_obj" creates three global associative arrays per object:
#
#     JL_DATA_<ID> ......... path -> value
#     JL_TYPE_CACHE_<ID> ... path -> 0 container | 1 array | 3 string |
#                                  4 number | 5 boolean | 6 null
#                                  (2 is "absent", never stored)
#     JL_LENGTH_CACHE_<ID> . array path -> element count
#
# The caches exist so that resolving a path, appending to an array and
# validating an index never have to scan the data. They are maintained by every
# mutating operation and must stay consistent with the data; that is why
# "delete" also renumbers the cache entries of the elements above the one it
# removed.
#
# LIMITATIONS
#
#  . The root is always an object: there is no top level array.
#  . A path cannot hold a value and items at the same time, exactly as in JSON.
#    "set" rejects such a request instead of corrupting the structure.
#  . An array holds either values or objects, never named keys: an array is
#    only addressable through an index.
#  . There is no serialiser. This is a structure, not a JSON codec.
#
# json-like - Nested data structures for BASH "inverted (c)" BSD-3-Clause
# Eduardo Lucio Amorim Costa
# Brazil-DF
# https://www.linkedin.com/in/eduardo-software-livre/
#

# Namerefs are only available from BASH 4.3 onwards and this library is built
# around them.
if ((BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 3))); then
    echo "ERROR! \"json-like.bash\" requires BASH version 4.3 or higher." >&2
    return 1 2>/dev/null || exit 1
fi

# LIBRARY BOOTSTRAP >>>>>>

# <<<<<< DOCUMENTATION

# The library is split into parts under "json-like/". This file is the entry
# point and the only one to source; the parts rely on each other and on the
# order they are loaded in, so none of them stands on its own.
#
# The order is fixed and spelled out below rather than looped over: there are
# six of them, they are known, and a list in a variable would only hide which
# one failed.

declare _JSON_LIKE_ROOT
_JSON_LIKE_ROOT="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" > /dev/null 2>&1 && pwd )"

# shellcheck source=json-like/bootstrap.bash
source "$_JSON_LIKE_ROOT/json-like/bootstrap.bash" || return 1 2> /dev/null || exit 1

# shellcheck source=json-like/object.bash
source "$_JSON_LIKE_ROOT/json-like/object.bash" || return 1 2> /dev/null || exit 1

# shellcheck source=json-like/caches.bash
source "$_JSON_LIKE_ROOT/json-like/caches.bash" || return 1 2> /dev/null || exit 1

# shellcheck source=json-like/path.bash
source "$_JSON_LIKE_ROOT/json-like/path.bash" || return 1 2> /dev/null || exit 1

# shellcheck source=json-like/data.bash
source "$_JSON_LIKE_ROOT/json-like/data.bash" || return 1 2> /dev/null || exit 1

# shellcheck source=json-like/api.bash
source "$_JSON_LIKE_ROOT/json-like/api.bash" || return 1 2> /dev/null || exit 1

# <<<<<< LIBRARY LOADING

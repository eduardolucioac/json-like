#!/bin/bash
#
# json-like/caches.bash - the type and length caches
#
# Part of "json-like". Sourced by "json-like.bash", never on its own: it
# relies on what the parts before it defined.
#
# json-like - Nested data structures for BASH "inverted (c)" BSD-3-Clause
# Eduardo Lucio Amorim Costa
#

# TYPE AND LENGTH CACHES >>>>>>

function json_like._set_type() {
    : 'Record what kind of node lives at a path.

    ARGUMENTS
        $1 - string, required. Object id.
        $2 - string, required. Full, already escaped path.
        $3 - integer, required. 0 container, 1 array, 3 string, 4 number,
             5 boolean, 6 null. (2 means "absent" and is never stored.)

    RETURNS
        0 always.

    The caches are what keep path resolution, appending and index validation
    O(1) instead of scans of the data.
    '
    local json_like_obj="$1"
    local -n jl_type_cache_ref_4738="JL_TYPE_CACHE_$json_like_obj"
    local path="$2"
    local type="$3"
    jl_type_cache_ref_4738["$path"]="$type"
}

function json_like._get_type() {
    : 'Read what kind of node lives at a path.

    ARGUMENTS
        $1 - string, required. NAME of the variable to receive the type.
        $2 - string, required. Object id.
        $3 - string, required. Full, already escaped path.

    RETURNS
        0 always. The variable receives 0 container, 1 array, 3 string,
        4 number, 5 boolean, 6 null, or 2 when the path is not known.

    A path absent from the cache yields 2, which is how callers tell "not
    there" from "there and empty".
    '

    # NOTE: Suffixes are used to prevent circular references with namerefs.

    local -n type_rtn_8c71="$1"

    local json_like_obj="$2"
    local -n jl_type_cache_ref_42fd="JL_TYPE_CACHE_$json_like_obj"

    local path="$3"

    # The root is always an object: there cannot be arrays at the first level.
    if [ -z "$path" ] ; then
        type_rtn_8c71=0
        return 0
    fi

    # If the "key" item is "not set" (returns empty in reality), it expands to
    # the default "2".
    type_rtn_8c71="${jl_type_cache_ref_42fd["$path"]:-2}"

}

function json_like._set_length() {
    : 'Record the element count of an array.

    ARGUMENTS
        $1 - string, required. Object id.
        $2 - string, required. Full, already escaped path of the ARRAY.
        $3 - integer, required. The new count.

    RETURNS
        0 always.

    Kept so that appending and validating an index never have to count the
    elements. A stale entry here makes a later "i.+" overwrite a live element,
    which is why "delete" renumbers this cache too.
    '
    local json_like_obj="$1"
    local -n jl_length_cache_ref_be68="JL_LENGTH_CACHE_$json_like_obj"
    local path="$2"
    local length="$3"
    jl_length_cache_ref_be68["$path"]="$length"
}

function json_like._get_length_by_path() {
    : 'Read the element count of an array, from a full path.

    ARGUMENTS
        $1 - string, required. NAME of the variable to receive the count.
        $2 - string, required. Object id.
        $3 - string, required. Full, already escaped path of the ARRAY.

    RETURNS
        0 on success, 1 when the path is not an array, with a message on
        stderr.

    This is the internal fast path: it takes a path that is already resolved.
    The public "json_like.get_length" takes a path split into items and
    resolves it first.
    '

    # NOTE: Suffixes are used to prevent circular references with namerefs.

    local -n length_rtn_bffd="$1"

    local json_like_obj="$2"
    local -n jl_length_cache_ref_4c8f="JL_LENGTH_CACHE_$json_like_obj"

    local path="$3"

    if [[ -v jl_length_cache_ref_4c8f["$path"] ]] ; then
        length_rtn_bffd="${jl_length_cache_ref_4c8f["$path"]}"
    else
        echo "ERROR! Not indexable item." >&2
        return 1
    fi

}

function json_like._unset_cache() {
    : 'Drops from one of the caches everything that a "delete" invalidated.

        $1 - object id
        $2 - cache array prefix ("JL_TYPE_CACHE" or "JL_LENGTH_CACHE")
        $3 - AWK mode ("unset_type", "unset_length", "unset_type_array" or
              "unset_length_array")
        $4 - native declaration of the target path (see "awk/json-like-core.awk")
        $5 - target path          (object modes only)
        $6 - key_ends 0/1         (object modes only)
        $7 - removed index        (array modes only)
        $8 - length before removal (array modes only)

    The object modes remove the path and its descendants. The array modes remove
    one element and shift the higher indexes down, mirroring what was done to the
    data, so a later "get" or "set" cannot address a stale entry.
    '

    # NOTE: Suffixes are used to prevent circular references with namerefs.

    local json_like_obj="$1"
    local cache_prefix="$2"
    local -n jl_cache_ref_b7bc="${cache_prefix}_$json_like_obj"

    local mode="$3"
    local native_declaration="$4"
    local path="$5"
    local key_ends="$6"
    local index="$7"
    local length="$8"

    if [[ "$mode" == "unset_type" ]] || [[ "$mode" == "unset_length" ]] ; then
        # Remove the item itself to optimize the performance of the operation
        # below: the AWK pass then only has to look for descendants.

        unset "jl_cache_ref_b7bc[$path]"
    fi

    if ((${#jl_cache_ref_b7bc[@]} == 0)) ; then
        # Nothing left to scan, so skip the AWK pass and its process spawn
        # altogether. This is the common case for the length cache of an object
        # that holds no arrays at all.

        return 0
    fi

    local array_declaration
    array_declaration=$(declare -p "${cache_prefix}_$json_like_obj")

    # We handle the associative array with awk because performance is critical here.
    local stdout_stderr=""

    if [[ "$mode" == "unset_type_array" ]] || [[ "$mode" == "unset_length_array" ]] ; then
        stdout_stderr=$(echo -n "$mode
$native_declaration
$index
$length
$array_declaration" | awk "$_JSON_LIKE_AWK" 2>&1) || {
            echo "$stdout_stderr" >&2
            return 1
        }
    else
        stdout_stderr=$(echo -n "$mode
$native_declaration
$key_ends
$array_declaration" | awk "$_JSON_LIKE_AWK" 2>&1) || {
            echo "$stdout_stderr" >&2
            return 1
        }
    fi

    eval "jl_cache_ref_b7bc=($stdout_stderr)"
}

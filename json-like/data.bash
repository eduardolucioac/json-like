#!/bin/bash
#
# json-like/data.bash - the operations that reach AWK, and the rules they enforce
#
# Part of "json-like". Sourced by "json-like.bash", never on its own: it
# relies on what the parts before it defined.
#
# json-like - Nested data structures for BASH "inverted (c)" BSD-3-Clause
# Eduardo Lucio Amorim Costa
#

# DATA OPERATIONS >>>>>>

function json_like._delete_path() {
    : 'Remove a path and every descendant of it, data and caches alike.

    ARGUMENTS
        $1 - string, required. Object id.
        $2 - string, required. NAME of the path metadata array built by
             "json_like._resolve_path" in "delete" mode.

    RETURNS
        0 on success, 1 when the path does not exist.

    SIDE EFFECTS
        Rewrites the data array and both caches.

    Runs one AWK pass per array it has to touch. A path that is a known
    container with no data row of its own is an EMPTY container: matching
    nothing is the right answer for it, not a failure.
    '

    # NOTE: Suffixes are used to prevent circular references with namerefs.

    local json_like_obj="$1"
    local -n jl_data_ref_c17f="JL_DATA_$json_like_obj"

    local -n path_metadata_4788="$2"

    local delete_array="${path_metadata_4788[1]}"
    local path="${path_metadata_4788[2]}"

    # 0 - Ends without index.
    # 1 - Ends with index (the path names an array, so its elements have to be
    #     matched as "path[" instead of "path." ).
    local key_ends=0
    if ((delete_array == 1)) ; then
        key_ends=1
    fi

    local native_declaration
    json_like._get_native_declaration native_declaration "$path"

    local array_declaration
    array_declaration=$(declare -p "JL_DATA_$json_like_obj")

    # An empty container owns no data row, so AWK will match nothing for it.
    # That is indistinguishable from a path that does not exist, EXCEPT that an
    # empty container is recorded in the type cache. Read it now to tell the two
    # apart: a path that is not there must still be refused.
    local empty_container_type_c17f=2
    json_like._get_type empty_container_type_c17f "$json_like_obj" "$path"

    # We handle the associative array with awk because performance is critical here.
    local stdout_stderr=""

    stdout_stderr=$(echo -n "delete_path
$native_declaration
$key_ends
$array_declaration" | awk "$_JSON_LIKE_AWK" 2>&1) || {
        if [[ "$stdout_stderr" == *"Invalid object path or index(es)."* ]] \
                && ((empty_container_type_c17f != 2)) ; then
            # An empty container: there is no data to rewrite, only caches to
            # clear, which is what the rest of this function does.

            stdout_stderr=""
        else
            echo "$stdout_stderr" >&2
            return 1
        fi
    }

    if [ -n "$stdout_stderr" ] ; then
        eval "jl_data_ref_c17f=($stdout_stderr)"
    fi

    # Keep the caches in step with the data. "_unset_cache" removes the path
    # itself and then lets AWK remove its descendants in one pass.
    json_like._unset_cache "$json_like_obj" "JL_TYPE_CACHE" "unset_type" \
        "$native_declaration" "$path" "$key_ends" || {
        return 1
    }

    json_like._unset_cache "$json_like_obj" "JL_LENGTH_CACHE" "unset_length" \
        "$native_declaration" "$path" "$key_ends" || {
        return 1
    }

}

function json_like._delete_path_array() {
    : 'Remove ONE array element and renumber the ones above it.

    ARGUMENTS
        $1 - string, required. Object id.
        $2 - string, required. NAME of the path metadata array built by
             "json_like._resolve_path" in "delete" mode, ending at an index.

    RETURNS
        0 on success, 1 on an AWK failure.

    SIDE EFFECTS
        Rewrites the data array and both caches, shifting every index above
        the removed one down by one so the array stays dense.

    The index was validated against the length before this is reached, so AWK
    is not asked to prove the element exists.
    '

    # NOTE: Suffixes are used to prevent circular references with namerefs.

    local json_like_obj="$1"

    local -n jl_data_ref_ebf7="JL_DATA_$json_like_obj"
    local -n path_metadata_b425="$2"

    local path_no_index="${path_metadata_b425[3]}"
    local index="${path_metadata_b425[4]}"
    local length="${path_metadata_b425[5]}"

    local native_declaration
    json_like._get_native_declaration native_declaration "$path_no_index"

    local array_declaration
    array_declaration=$(declare -p "JL_DATA_$json_like_obj")

    # We handle the associative array with awk because performance is critical here.
    local stdout_stderr=""

    stdout_stderr=$(echo -n "delete_path_array
$native_declaration
$index
$length
$array_declaration" | awk "$_JSON_LIKE_AWK" 2>&1) || {
        echo "$stdout_stderr" >&2
        return 1
    }

    eval "jl_data_ref_ebf7=($stdout_stderr)"

    # The caches have to be renumbered the same way, otherwise a later "get" or
    # "set" would resolve against indexes that no longer exist.
    json_like._unset_cache "$json_like_obj" "JL_TYPE_CACHE" "unset_type_array" \
        "$native_declaration" "" "" "$index" "$length" || {
        return 1
    }

    json_like._unset_cache "$json_like_obj" "JL_LENGTH_CACHE" "unset_length_array" \
        "$native_declaration" "" "" "$index" "$length" || {
        return 1
    }

    json_like._set_length "$json_like_obj" "$path_no_index" "$(( length - 1 ))"

}

function json_like._get_full_assoc_array() {
    : 'Copy the whole internal data array into an associative array.

    ARGUMENTS
        $1 - string, required. NAME of an associative array to fill in. It
             must already be declared with "declare -A".
        $2 - string, required. Object id.

    RETURNS
        0 always.

    SIDE EFFECTS
        Replaces the contents of the target.

    The result is a COPY keyed by full, escaped paths. Changing it does not
    touch the object.
    '

    # NOTE: Suffixes are used to prevent circular references with namerefs.

    local -n jl_data_rtn_973b="$1"

    local json_like_obj="$2"

    # Copy the array using its built-in declaration ("declare -p") in BASH.
    local jl_data
    jl_data=$(declare -p "JL_DATA_$json_like_obj")
    eval "jl_data_rtn_973b=${jl_data#*=}"

}

function json_like._get_in_assoc_array() {
    : 'Copy the subtree under a path into an associative array.

    ARGUMENTS
        $1 - string, required. NAME of an associative array to fill in. It
             must already be declared with "declare -A".
        $2 - string, required. Object id.
        $3 - string, required. NAME of the path metadata array built by
             "json_like._resolve_path".

    RETURNS
        0 on success, 1 when the path does not exist.

    SIDE EFFECTS
        Replaces the contents of the target.

    The keys of the result are relative to the PARENT of the requested path,
    so they always start with the last item of that path: asking for
    "window.tags" yields "tags[0]", "tags[1]", and asking for "window" yields
    "window.title", "window.tags[0]". An empty container yields no keys at
    all, which is a result and not an error.
    '

    # NOTE: Suffixes are used to prevent circular references with namerefs.

    local -n value_rtn_a6a1="$1"

    local json_like_obj="$2"
    local -n path_metadata_407a="$3"

    local path_type="${path_metadata_407a[0]}"
    local path="${path_metadata_407a[2]}"

    # 0 - Ends without index.
    # 1 - Ends with index.
    local key_ends

    if ((path_type == 0)) ; then
        # 0 - Object key.

        json_like._get_type key_ends "$json_like_obj" "$path"
    else
        # "path_type" is "1".
        # 1 - Array index.

        # The value in "path_no_index" ("${path_metadata_407a[3]}") is non-empty
        # only if "path_type" is "1", that is, the path ends with an index.
        json_like._get_type key_ends "$json_like_obj" "${path_metadata_407a[3]}"
    fi

    if ((key_ends == 2)) ; then
        echo "ERROR! Invalid path or index(es)." >&2
        return 1
    elif ((path_type == 1)) ; then
        # Although the item is indexable, the iteration is not over indexes (an array)
        # since the index was provided.

        key_ends=0
    elif ((key_ends != 1)) ; then
        # AWK only wants to know whether the rows to match end with an index.
        # The type cache answers more than that -- a leaf carries which of the
        # JSON types it holds -- so everything that is not an array collapses
        # to 0 here. Passing the raw type through would be read as a mode.

        key_ends=0
    fi

    local native_declaration
    json_like._get_native_declaration native_declaration "$path"

    local array_declaration
    array_declaration=$(declare -p "JL_DATA_$json_like_obj")

    # We handle the associative array with awk because performance is critical here.
    local stdout_stderr=""
    stdout_stderr=$(echo -n "get
$native_declaration
$key_ends
$array_declaration" | awk "$_JSON_LIKE_AWK" 2>&1) || {
        if [[ "$stdout_stderr" == *"Invalid object path or index(es)."* ]] ; then
            # The path exists -- its type was read just above -- so matching no
            # row means the container is empty. An empty container lives only in
            # the caches, and an empty result is the right answer for it.

            value_rtn_a6a1=()
            return 0
        fi

        echo "$stdout_stderr" >&2
        return 1
    }

    eval "value_rtn_a6a1=($stdout_stderr)"
}

function json_like._validate_set_path() {
    : 'Reject a "set" that would make a path hold a value AND items.

    ARGUMENTS
        $1 - string, required. Object id.
        $2 - string, required. NAME of the path metadata array built by
             "json_like._resolve_path" in "set" mode.

    RETURNS
        0 when the write is allowed, 1 otherwise, with a message on stderr.

    Two shapes are refused, because neither can be represented as JSON:

      . writing under a path that already holds a value ("a" is a string and
        "a.b" is being created);
      . writing a value onto a path that already holds items ("a.b" exists
        and "a" is being given a value).

    Both checks are O(1): a path holds a VALUE when it is a key of the data
    array, and it holds ITEMS when it is known to the type cache but is not a
    key of the data array. Called BEFORE anything is written, so a refused
    "set" leaves the object exactly as it was.
    '

    # NOTE: Suffixes are used to prevent circular references with namerefs.

    local json_like_obj="$1"
    local -n jl_data_ref_2c5e="JL_DATA_$json_like_obj"
    local -n path_metadata_2c5e="$2"

    # Get the length of the array.
    local l="${#path_metadata_2c5e[@]}"

    # Chunk size.
    local c=6

    local i=0
    local is_last=0
    local node_path=""
    local leaf_path=""
    local node_type=0

    for ((i = 0; i < l; i += c)); do

        is_last=0
        if (( (i + c) >= l )); then
            is_last=1
        fi

        leaf_path="${path_metadata_2c5e[i+2]}"

        if ((${path_metadata_2c5e[i]} == 1)) ; then
            # The array itself is a container no matter where the path ends.

            node_path="${path_metadata_2c5e[i+3]}"
            if [[ -v jl_data_ref_2c5e["$node_path"] ]] ; then
                echo "ERROR! A value is already set at \"$node_path\". It cannot also hold items." >&2
                return 1
            fi
        fi

        if ((is_last == 0)) ; then
            # An intermediate level must not already hold a value.

            if [[ -v jl_data_ref_2c5e["$leaf_path"] ]] ; then
                echo "ERROR! A value is already set at \"$leaf_path\". It cannot also hold items." >&2
                return 1
            fi
        else
            # The last level must not already hold items.

            json_like._get_type node_type "$json_like_obj" "$leaf_path"
            if ((node_type != 2)) && [[ ! -v jl_data_ref_2c5e["$leaf_path"] ]] ; then
                echo "ERROR! The path \"$leaf_path\" already holds items. It cannot also hold a value." >&2
                return 1
            fi
        fi

    done

}

#!/bin/bash
#
# json-like/object.bash - creating and destroying objects
#
# Part of "json-like". Sourced by "json-like.bash", never on its own: it
# relies on what the parts before it defined.
#
# json-like - Nested data structures for BASH "inverted (c)" BSD-3-Clause
# Eduardo Lucio Amorim Costa
#

# OBJECT LIFECYCLE >>>>>>

function json_like.set_obj() {
    : 'Create a "json-like" object.

    ARGUMENTS
        $1 - string, required. The NAME of a variable to receive the new id,
             not its value. It is written through a nameref.

    RETURNS
        0 on success, 1 when no UUID source is available or the id comes out
        empty. The error goes to stderr.

    SIDE EFFECTS
        Declares three global associative arrays named after the new id:
        "JL_DATA_<ID>", "JL_TYPE_CACHE_<ID>" and "JL_LENGTH_CACHE_<ID>".

    The id is a random hexadecimal string. Callers only ever pass the id
    around; the three arrays are an implementation detail, and "unset_obj" is
    what removes them.
    '

    # NOTE: Suffixes are used to prevent circular references with namerefs.

    local -n json_like_obj_rtn_b284="$1"

    local new_obj_id=""
    local uuid=""
    while : ; do

        if [[ -r /proc/sys/kernel/random/uuid ]] ; then
            # Pure BASH, no sub process. This matters because scripts tend to
            # create objects in loops.

            read -r uuid < /proc/sys/kernel/random/uuid
        elif command -v uuidgen > /dev/null 2>&1 ; then
            uuid=$(uuidgen)
        else
            echo "ERROR! No UUID source available (\"/proc/sys/kernel/random/uuid\" or \"uuidgen\")." >&2
            return 1
        fi

        uuid="${uuid//-/}"
        new_obj_id="${uuid^^}"

        if [ -z "$new_obj_id" ] ; then
            echo "ERROR! Unable to generate a \"json-like\" object id." >&2
            return 1
        fi

        # Guard against reusing the arrays of a live object.
        if ! declare -p "JL_DATA_$new_obj_id" > /dev/null 2>&1 ; then
            break
        fi
    done

    declare -Ag "JL_DATA_$new_obj_id"
    declare -Ag "JL_TYPE_CACHE_$new_obj_id"
    declare -Ag "JL_LENGTH_CACHE_$new_obj_id"

    json_like_obj_rtn_b284="$new_obj_id"
}

function json_like.unset_obj() {
    : 'Destroy a "json-like" object.

    ARGUMENTS
        $1 - string, required. The NAME of the variable holding the id, not
             the id itself, because the variable is cleared as well.

    RETURNS
        0 on success, 1 when the variable does not name a live object.

    SIDE EFFECTS
        Unsets the objects three global arrays and empties the callers
        variable, so a stale id cannot be used by accident.
    '

    # NOTE: Suffixes are used to prevent circular references with namerefs.
    local -n json_like_obj_ref_4d46="$1"

    if [ -z "$json_like_obj_ref_4d46" ] ; then
        echo "ERROR! JSON Like object not set." >&2
        return 1
    fi

    unset "JL_DATA_$json_like_obj_ref_4d46"
    unset "JL_TYPE_CACHE_$json_like_obj_ref_4d46"
    unset "JL_LENGTH_CACHE_$json_like_obj_ref_4d46"
    unset "$1"
}

function json_like._assert_obj() {
    : 'Check that an object id names a live object.

    ARGUMENTS
        $1 - string, required. The object id.

    RETURNS
        0 when the object exists, 1 otherwise, with a message on stderr.

    Every public function calls this first, so that a stale or empty id fails
    with one clear message instead of a BASH error from deep inside.
    '
    declare -p "JL_DATA_$1" > /dev/null 2>&1 && return 0
    echo "ERROR! JSON Like object not set." >&2
    return 1
}

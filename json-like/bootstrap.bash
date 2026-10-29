#!/bin/bash
#
# json-like/bootstrap.bash - where the library finds itself, and what it loads.
#
# Part of "json-like". Sourced by "json-like.bash" FIRST, because everything
# after it relies on what this defines.
#
# json-like - Nested data structures for BASH "inverted (c)" BSD-3-Clause
# Eduardo Lucio Amorim Costa
#

# Where the library lives, so that the AWK programs are found no matter what
# the current working directory is.
#
# This part is sourced from one directory down, so the root cannot be taken
# from "${BASH_SOURCE[0]}" here: it comes from the entry point, which is the
# file that knows where the project starts.
#
# NOTE: A library private name is used on purpose. A generic one such as
# "SCRIPT_DIRECTORY" would collide with the variable of the script that sources
# this file.
declare _JSON_LIKE_DIR
_JSON_LIKE_DIR="$_JSON_LIKE_ROOT"
if [ -z "$_JSON_LIKE_DIR" ] ; then
    echo "ERROR! Unable to resolve the \"json-like.bash\" directory." >&2
    return 1 2>/dev/null || exit 1
fi

if ! command -v awk > /dev/null 2>&1 ; then
    echo "ERROR! \"json-like.bash\" requires \"awk\"." >&2
    return 1 2>/dev/null || exit 1
fi

# The AWK back end, read once at source time and kept in memory. Passing the
# program as a string avoids both a file read and a process spawn per call.
declare _JSON_LIKE_AWK
if [[ ! -r "$_JSON_LIKE_DIR/awk/json-like-core.awk" ]] ; then
    echo "ERROR! Unable to read \"$_JSON_LIKE_DIR/awk/json-like-core.awk\"." >&2
    return 1 2>/dev/null || exit 1
fi
_JSON_LIKE_AWK=$(< "$_JSON_LIKE_DIR/awk/json-like-core.awk")

declare _JSON_LIKE_CODEC_AWK
if [[ ! -r "$_JSON_LIKE_DIR/awk/json-like-to_json.awk" ]] ; then
    echo "ERROR! Unable to read \"$_JSON_LIKE_DIR/awk/json-like-to_json.awk\"." >&2
    return 1 2> /dev/null || exit 1
fi
_JSON_LIKE_CODEC_AWK=$(< "$_JSON_LIKE_DIR/awk/json-like-to_json.awk")

declare _JSON_LIKE_FROM_JSON_AWK
if [[ ! -r "$_JSON_LIKE_DIR/awk/json-like-from_json.awk" ]] ; then
    echo "ERROR! Unable to read \"$_JSON_LIKE_DIR/awk/json-like-from_json.awk\"." >&2
    return 1 2> /dev/null || exit 1
fi
_JSON_LIKE_FROM_JSON_AWK=$(< "$_JSON_LIKE_DIR/awk/json-like-from_json.awk")

# Whether "${!name@a}" is available (BASH 5.1 and up).
#
# "json_like.get" has to know whether the variable it was handed is an
# associative array. The portable way of asking is to capture "declare -p",
# which costs a FORK on every single read; "${!name@a}" answers the same
# question for free. The fallback below keeps BASH 4.3 working.
declare -i _JSON_LIKE_HAS_ATTR_EXPANSION=0
if ((BASH_VERSINFO[0] > 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] >= 1))); then
    _JSON_LIKE_HAS_ATTR_EXPANSION=1
fi

#!/bin/bash
#
# test/performance.bash - the timings, run only with --perf
#
# Part of the "json-like" test suite. Sourced by "test/test.bash", never run on
# its own: it uses the counters and assertions the harness defines.
#
# json-like - Nested data structures for BASH "inverted (c)" BSD-3-Clause
# Eduardo Lucio Amorim Costa
#

echo
echo "============================================================"
echo " JSON-LIKE PERFORMANCE TESTS"
echo "============================================================"
echo

declare PERF_OBJ
json_like.set_obj PERF_OBJ

# Number of operations per measurement. The O(n) operations go through AWK and
# scale with the size of the object, so keep this modest.
PERF_OPS=150

# Times a loop of operations and prints the result.
function perf_measure() {
    local label="$1"
    shift
    local start_time
    local end_time
    start_time=$(date +%s%N)
    "$@"
    end_time=$(date +%s%N)
    printf ' %-44s %6s ms\n' "$label" "$(( (end_time - start_time) / 1000000 ))"
}

function perf_set_by_index() {
    local i
    for ((i = 0; i < PERF_OPS; i++)) ; do
        json_like.set "$PERF_OBJ" "s.A_$i" "o.ObjectKey" "o.ArrayKey" "i.$i"
    done
}

function perf_set_by_append() {
    local i
    for ((i = 0; i < PERF_OPS; i++)) ; do
        json_like.set "$PERF_OBJ" "s.B_$i" "o.ObjectKey" "o.ArrayKey" "i.+"
    done
}

function perf_get_by_index() {
    local i
    for ((i = 0; i < PERF_OPS; i++)) ; do
        json_like.get GET_RTN "$PERF_OBJ" "ObjectKey" "ArrayKey" "$i"
    done
}

function perf_get_last() {
    local i
    for ((i = 0; i < PERF_OPS; i++)) ; do
        json_like.get GET_RTN "$PERF_OBJ" "ObjectKey" "ArrayKey" "-1"
    done
}

function perf_set_keys() {
    local i
    for ((i = 0; i < PERF_OPS; i++)) ; do
        json_like.set "$PERF_OBJ" "s.V_$i" "o.ObjectKey" "o.MapKey" "o.key_$i"
    done
}

function perf_get_keys() {
    local i
    for ((i = 0; i < PERF_OPS; i++)) ; do
        json_like.get GET_RTN "$PERF_OBJ" "ObjectKey" "MapKey" "key_$i"
    done
}

function perf_delete_last() {
    local i
    for ((i = 0; i < PERF_OPS; i++)) ; do
        json_like.delete "$PERF_OBJ" "ObjectKey" "ArrayKey" "-1"
    done
}

function perf_delete_keys() {
    local i
    for ((i = 0; i < PERF_OPS; i++)) ; do
        json_like.delete "$PERF_OBJ" "ObjectKey" "MapKey" "key_$i"
    done
}

echo " O(1) operations (pure BASH, no AWK)"
perf_measure "$PERF_OPS set by index" perf_set_by_index
perf_measure "$PERF_OPS set by append" perf_set_by_append
perf_measure "$PERF_OPS get by index" perf_get_by_index
perf_measure "$PERF_OPS get by negative index" perf_get_last
perf_measure "$PERF_OPS set by key" perf_set_keys
perf_measure "$PERF_OPS get by key" perf_get_keys
echo
# Deleting a leaf is O(1) too: it owns a row of its own, so there is nothing to
# collect and nothing to renumber, and it never reaches AWK. Deleting an array
# element does reach it, because the elements above have to move down.
perf_measure "$PERF_OPS delete by key (a leaf)" perf_delete_keys

echo
echo " O(n) operations (AWK passes)"
perf_measure "$PERF_OPS delete by negative index" perf_delete_last
echo

json_like.unset_obj PERF_OBJ

((TESTS_FAILED == 0)) && exit 0

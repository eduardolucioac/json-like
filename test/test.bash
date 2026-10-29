#!/bin/bash
#
# test/test.bash - Test suite for the "json-like" BASH library.
#
# Run it directly:
#
#     ./test/test.bash           # integrity tests
#     ./test/test.bash --perf    # integrity tests + performance tests
#
# Exits 0 when every test passed, 1 otherwise, so it can be wired into a
# pre-commit hook or a CI job.
#
# The suite is split into parts under "test/". This file is the entry point
# and the only one to run; the parts use the counters and assertions the
# harness defines, so none of them stands on its own.
#
# The order is fixed and spelled out below rather than looped over: they are
# known, and a list in a variable would only hide which one failed.
#
# json-like - Nested data structures for BASH "inverted (c)" BSD-3-Clause
# Eduardo Lucio Amorim Costa
#

TESTS_DIRECTORY="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" && pwd )"
TESTS_ROOT="$( cd -- "$TESTS_DIRECTORY/.." && pwd )"

# shellcheck source=../json-like.bash
source "$TESTS_ROOT/json-like.bash" || exit 1

# shellcheck source=../util/try-catch.bash
source "$TESTS_ROOT/util/try-catch.bash" || exit 1

# The library does not install traps. Scripts that use "try-catch.bash" are the
# ones responsible for clearing the temporary files it may leave behind.
trap 'prog_concepts.cleanup' EXIT

RUN_PERFORMANCE_TESTS=0
if [[ "$1" == "--perf" ]] ; then
    RUN_PERFORMANCE_TESTS=1
fi

# shellcheck source=harness.bash
source "$TESTS_DIRECTORY/harness.bash" || exit 1

# shellcheck source=basics.bash
source "$TESTS_DIRECTORY/basics.bash" || exit 1

# shellcheck source=characters.bash
source "$TESTS_DIRECTORY/characters.bash" || exit 1

# shellcheck source=notation.bash
source "$TESTS_DIRECTORY/notation.bash" || exit 1

# shellcheck source=containers.bash
source "$TESTS_DIRECTORY/containers.bash" || exit 1

# shellcheck source=deleting.bash
source "$TESTS_DIRECTORY/deleting.bash" || exit 1

# shellcheck source=json_text.bash
source "$TESTS_DIRECTORY/json_text.bash" || exit 1

# shellcheck source=sources.bash
source "$TESTS_DIRECTORY/sources.bash" || exit 1

echo
echo "============================================================"
printf ' TOTAL %s | PASSED %s | FAILED %s\n' "$TESTS_TOTAL" "$TESTS_PASSED" "$TESTS_FAILED"
if ((TESTS_FAILED > 0)) ; then
    echo " FAILED TESTS:"
    for FAILED_NAME in "${TESTS_FAILED_NAMES[@]}" ; do
        printf '   . %s\n' "$FAILED_NAME"
    done
fi
echo "============================================================"

if ((RUN_PERFORMANCE_TESTS == 0)) ; then
    echo
    echo ' Run with "--perf" to also time the operations.'
    echo
    ((TESTS_FAILED == 0)) && exit 0
    exit 1
fi

# shellcheck source=performance.bash
source "$TESTS_DIRECTORY/performance.bash" || exit 1

echo
((TESTS_FAILED == 0)) && exit 0
exit 1

#!/bin/bash
#
# test/harness.bash - the counters and the assertions every part uses.
#
# Part of the "json-like" test suite. Sourced by "test/test.bash" FIRST,
# because every other part relies on what this defines.
#
# json-like - Nested data structures for BASH "inverted (c)" BSD-3-Clause
# Eduardo Lucio Amorim Costa
#

TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0
declare -a TESTS_FAILED_NAMES=()

# Reports the outcome of one test.
#
#     $1 .. 0 for pass, anything else for fail
#     $2 .. test name
#     $3 .. optional detail printed on failure
function t_report() {
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    if (($1 == 0)) ; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        printf ' [ PASS ] %s\n' "$2"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        TESTS_FAILED_NAMES+=("$2")
        printf ' [ FAIL ] %s\n' "$2"
        if [ -n "$3" ] ; then
            printf '          %s\n' "$3"
        fi
    fi
}

# Asserts that two strings are equal.
function t_equals() {
    local test_name="$1"
    local expected="$2"
    local obtained="$3"
    if [[ "$expected" == "$obtained" ]] ; then
        t_report 0 "$test_name"
    else
        t_report 1 "$test_name" "expected [$expected] but got [$obtained]"
    fi
}

# Runs a command IN THE CURRENT SHELL, capturing its streams to files.
#
# NOTE: Command substitution would be shorter, but it runs the command in a
# subshell, so every mutation it performs would be rolled back the moment it
# returned. That silently turns "delete then check it is gone" into a test of
# nothing at all.
#
# Fills in "T_RUN_STDOUT", "T_RUN_STDERR" and "T_RUN_RTN_CODE".
T_RUN_STDOUT=""
T_RUN_STDERR=""
T_RUN_RTN_CODE=0
function t_run() {
    local stdout_file
    local stderr_file
    stdout_file=$(mktemp "${TMPDIR:-/tmp}/json-like-test-out.XXXXXX")
    stderr_file=$(mktemp "${TMPDIR:-/tmp}/json-like-test-err.XXXXXX")

    "$@" > "$stdout_file" 2> "$stderr_file"
    T_RUN_RTN_CODE="$?"

    T_RUN_STDOUT=$(< "$stdout_file")
    T_RUN_STDERR=$(< "$stderr_file")
    rm -f "$stdout_file" "$stderr_file"
}

# Asserts that a command succeeds, keeping its stderr out of the way.
function t_succeeds() {
    local test_name="$1"
    shift
    t_run "$@"
    if ((T_RUN_RTN_CODE == 0)) && [ -z "$T_RUN_STDERR" ] ; then
        t_report 0 "$test_name"
    elif ((T_RUN_RTN_CODE == 0)) ; then
        t_report 1 "$test_name" "succeeded but wrote to stderr: $T_RUN_STDERR"
    else
        t_report 1 "$test_name" "returned $T_RUN_RTN_CODE: $T_RUN_STDERR"
    fi
}

# Asserts that a command fails without crashing BASH itself.
function t_fails() {
    local test_name="$1"
    shift
    t_run "$@"
    local stderr_op="$T_RUN_STDERR"
    local rtn_code="$T_RUN_RTN_CODE"
    if ((rtn_code == 0)) ; then
        t_report 1 "$test_name" "expected a non-zero return code"
    elif [[ "$stderr_op" == *"arithmetic syntax error"* ]] \
            || [[ "$stderr_op" == *"bad array subscript"* ]] \
            || [[ "$stderr_op" == *"unbound variable"* ]] ; then
        t_report 1 "$test_name" "failed through a raw BASH error: $stderr_op"
    elif [[ "$stderr_op" != ERROR!* ]] ; then
        t_report 1 "$test_name" "failed without a proper message: $stderr_op"
    else
        t_report 0 "$test_name"
    fi
}

# Asserts that a command produces nothing at all on stdout. Any library
# function that leaks output breaks every caller that uses command
# substitution.
function t_silent_on_stdout() {
    local test_name="$1"
    shift
    t_run "$@"
    if [ -z "$T_RUN_STDOUT" ] ; then
        t_report 0 "$test_name"
    else
        t_report 1 "$test_name" "wrote to stdout: $T_RUN_STDOUT"
    fi
}

echo
echo "============================================================"
echo " JSON-LIKE INTEGRITY TESTS"
echo "============================================================"
echo

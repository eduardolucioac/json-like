#!/bin/bash
#
# test/sources.bash - the source files themselves, and the try/catch helper
#
# Part of the "json-like" test suite. Sourced by "test/test.bash", never run on
# its own: it uses the counters and assertions the harness defines.
#
# json-like - Nested data structures for BASH "inverted (c)" BSD-3-Clause
# Eduardo Lucio Amorim Costa
#

echo " --- Source files ---"

# A docstring is a quoted string, so an apostrophe inside one closes it early
# and swallows whatever follows. "bash -n" catches it; nothing else does, and
# the damage shows up far from the cause.
PARSE_FAILURES=0
PARSE_DETAIL=""
for PARSE_FILE in "$TESTS_ROOT"/json-like.bash \
                  "$TESTS_ROOT"/json-like/*.bash \
                  "$TESTS_ROOT"/util/*.bash \
                  "$TESTS_ROOT"/test/*.bash ; do
    PARSE_OUTPUT=$(bash -n "$PARSE_FILE" 2>&1)
    if ((  $? != 0 )) || [ -n "$PARSE_OUTPUT" ] ; then
        PARSE_FAILURES=$((PARSE_FAILURES + 1))
        PARSE_DETAIL="$(basename "$PARSE_FILE"): $PARSE_OUTPUT"
    fi
done
t_report "$PARSE_FAILURES" "every source file parses with no warning" "$PARSE_DETAIL"

# One case convention, everywhere: a variable declared "local" inside a
# function is lower_case, and anything at script or global scope is
# UPPER_CASE. The library follows it without exception; this keeps it that
# way, because the two scopes meeting is exactly how a nameref ends up
# pointing at itself.
CASE_FAILURES=0
CASE_DETAIL=""
for LOOP_FILE in "$TESTS_ROOT"/json-like.bash \
                 "$TESTS_ROOT"/json-like/*.bash \
                 "$TESTS_ROOT"/util/*.bash \
                 "$TESTS_ROOT"/test/*.bash \
                 "$TESTS_ROOT"/prov.bash ; do

    # A "local" must not be UPPER_CASE.
    while IFS= read -r LOOP_LINE ; do
        CASE_FAILURES=$((CASE_FAILURES + 1))
        CASE_DETAIL="$(basename "$LOOP_FILE"): upper-case local -> $(printf '%.60s' "$LOOP_LINE")"
    done < <(grep -E '^[[:space:]]+local( -[a-zA-Z]+)* [A-Z][A-Z0-9_]*[=[:space:]]' "$LOOP_FILE")

    # A script-scope "declare" must not be lower_case.
    while IFS= read -r LOOP_LINE ; do
        CASE_FAILURES=$((CASE_FAILURES + 1))
        CASE_DETAIL="$(basename "$LOOP_FILE"): lower-case global -> $(printf '%.60s' "$LOOP_LINE")"
    done < <(grep -E '^declare( -[a-zA-Z]+)* [a-z]' "$LOOP_FILE")
done
t_report "$CASE_FAILURES" "one case convention across every file" "$CASE_DETAIL"

# Every function carries a docstring, and the ones taking arguments say what
# they are.
DOC_FAILURES=0
DOC_DETAIL=""
for PARSE_FILE in "$TESTS_ROOT"/json-like/*.bash ; do
    while IFS= read -r FN_LINE ; do
        FN_NAME="${FN_LINE#function }"
        FN_NAME="${FN_NAME%%(*}"
        if ! grep -A1 "^function ${FN_NAME}()" "$PARSE_FILE" | grep -q "^    : '" ; then
            DOC_FAILURES=$((DOC_FAILURES + 1))
            DOC_DETAIL="$FN_NAME has no docstring"
        fi
    done < <(grep '^function ' "$PARSE_FILE")
done
t_report "$DOC_FAILURES" "every function carries a docstring" "$DOC_DETAIL"

echo
echo " --- try/catch helper ---"

TMP_BEFORE=$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'bash-try-catch.*' 2>/dev/null | wc -l)
for _ in 1 2 3 4 5 ; do
    prog_concepts.try handler
    json_like.set "$JSON_LIKE_OBJ" "s.ok" "o.ObjectKey" "o.TryOkKey" 2> >($handler)
    prog_concepts.catch "$handler" 0 "$?"
done
wait
TMP_AFTER=$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'bash-try-catch.*' 2>/dev/null | wc -l)
t_equals "a successful try/catch leaves no temporary file behind" \
    "$TMP_BEFORE" "$TMP_AFTER"

prog_concepts.try handler
json_like.get GET_RTN "$JSON_LIKE_OBJ" "ObjectKey" "DefinitelyMissingKey" 2> >($handler)
RTN_CODE="$?"
CAUGHT=$(prog_concepts.catch "$handler" 0 "$RTN_CODE" 2>&1)
if [[ "$CAUGHT" == *"Invalid path or index(es)"* ]] ; then
    t_report 0 "try/catch captures the library error message"
else
    t_report 1 "try/catch captures the library error message" "got [$CAUGHT]"
fi

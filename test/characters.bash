#!/bin/bash
#
# test/characters.bash - values and keys holding whatever they like
#
# Part of the "json-like" test suite. Sourced by "test/test.bash", never run on
# its own: it uses the counters and assertions the harness defines.
#
# json-like - Nested data structures for BASH "inverted (c)" BSD-3-Clause
# Eduardo Lucio Amorim Costa
#

echo " --- Values with special characters ---"

declare SPECIAL_OBJ
json_like.set_obj SPECIAL_OBJ
declare -a SPECIAL_VALUES=(
    'plain'
    ''
    'with space'
    "single'quote"
    'double"quote'
    'back\slash'
    'dollar$var'
    'close)paren'
    'open(paren'
    'bracket]'
    '[bracket'
    'equals=sign'
    'semi;colon'
    'back`tick'
    $'tab\there'
    $'new\nline'
    'mixed "a" '"'"'b'"'"' \c'
    'declare -A injected=([evil]="1" )'
)
SPECIAL_FAILURES=0
SPECIAL_DETAIL=""
for ((LOOP_INDEX = 0; LOOP_INDEX < ${#SPECIAL_VALUES[@]}; LOOP_INDEX++)) ; do
    json_like.set "$SPECIAL_OBJ" "s.${SPECIAL_VALUES[LOOP_INDEX]}" "o.SpecialKey" "o.k$LOOP_INDEX" || {
        SPECIAL_FAILURES=$((SPECIAL_FAILURES + 1))
        SPECIAL_DETAIL="set failed at index $LOOP_INDEX"
        continue
    }
    json_like.get GET_RTN "$SPECIAL_OBJ" "SpecialKey" "k$LOOP_INDEX" || {
        SPECIAL_FAILURES=$((SPECIAL_FAILURES + 1))
        SPECIAL_DETAIL="get failed at index $LOOP_INDEX"
        continue
    }
    if [[ "$GET_RTN" != "${SPECIAL_VALUES[LOOP_INDEX]}" ]] ; then
        SPECIAL_FAILURES=$((SPECIAL_FAILURES + 1))
        SPECIAL_DETAIL="index $LOOP_INDEX: expected [${SPECIAL_VALUES[LOOP_INDEX]}] got [$GET_RTN]"
    fi
done
t_report "$SPECIAL_FAILURES" \
    "every special value round-trips through set/get (${#SPECIAL_VALUES[@]} values)" \
    "$SPECIAL_DETAIL"

# The subtree read goes through AWK, so it has to survive the same values.
declare -A SPECIAL_SUBTREE=()
json_like.get SPECIAL_SUBTREE "$SPECIAL_OBJ" "SpecialKey"
SPECIAL_FAILURES=0
SPECIAL_DETAIL=""
for ((LOOP_INDEX = 0; LOOP_INDEX < ${#SPECIAL_VALUES[@]}; LOOP_INDEX++)) ; do
    if [[ "${SPECIAL_SUBTREE["SpecialKey.k$LOOP_INDEX"]}" != "${SPECIAL_VALUES[LOOP_INDEX]}" ]] ; then
        SPECIAL_FAILURES=$((SPECIAL_FAILURES + 1))
        SPECIAL_DETAIL="index $LOOP_INDEX: expected [${SPECIAL_VALUES[LOOP_INDEX]}] got [${SPECIAL_SUBTREE["SpecialKey.k$LOOP_INDEX"]}]"
    fi
done
if ((${#SPECIAL_SUBTREE[@]} != ${#SPECIAL_VALUES[@]})) ; then
    SPECIAL_FAILURES=$((SPECIAL_FAILURES + 1))
    SPECIAL_DETAIL="got ${#SPECIAL_SUBTREE[@]} keys, expected ${#SPECIAL_VALUES[@]}"
fi
t_report "$SPECIAL_FAILURES" \
    "every special value round-trips through a subtree read" "$SPECIAL_DETAIL"

if declare -p "evil" > /dev/null 2>&1 ; then
    t_report 1 "a declaration-looking value does not escape into the shell"
else
    t_report 0 "a declaration-looking value does not escape into the shell"
fi

echo
echo " --- Keys with special characters ---"

declare KEY_OBJ
json_like.set_obj KEY_OBJ
declare -a SPECIAL_KEYS=( 'a.b' 'a[0]' 'a]b' 'with space' 'a"b' 'a$b' )
KEY_FAILURES=0
KEY_DETAIL=""
for ((LOOP_INDEX = 0; LOOP_INDEX < ${#SPECIAL_KEYS[@]}; LOOP_INDEX++)) ; do
    json_like.set "$KEY_OBJ" "s.V$LOOP_INDEX" "o.WeirdKey" "o.${SPECIAL_KEYS[LOOP_INDEX]}" || {
        KEY_FAILURES=$((KEY_FAILURES + 1))
        KEY_DETAIL="set failed for key [${SPECIAL_KEYS[LOOP_INDEX]}]"
        continue
    }
    json_like.get GET_RTN "$KEY_OBJ" "WeirdKey" "${SPECIAL_KEYS[LOOP_INDEX]}" || {
        KEY_FAILURES=$((KEY_FAILURES + 1))
        KEY_DETAIL="get failed for key [${SPECIAL_KEYS[LOOP_INDEX]}]"
        continue
    }
    if [[ "$GET_RTN" != "V$LOOP_INDEX" ]] ; then
        KEY_FAILURES=$((KEY_FAILURES + 1))
        KEY_DETAIL="key [${SPECIAL_KEYS[LOOP_INDEX]}]: expected [V$LOOP_INDEX] got [$GET_RTN]"
    fi
done
t_report "$KEY_FAILURES" \
    "keys holding path syntax round-trip (${#SPECIAL_KEYS[@]} keys)" "$KEY_DETAIL"

json_like.set "$KEY_OBJ" "s.DottedValue" "o.WeirdKey" "o.x.y" "o.ChildKey"
json_like.get GET_RTN "$KEY_OBJ" "WeirdKey" "x.y" "ChildKey"
t_equals "a dotted key is not mistaken for two levels" "DottedValue" "$GET_RTN"
t_fails "the two levels a dotted key looks like do not exist" \
    json_like.get GET_RTN "$KEY_OBJ" "WeirdKey" "x" "y" "ChildKey"

echo

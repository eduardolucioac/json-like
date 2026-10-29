#!/bin/bash
#
# test/notation.bash - the path tags, the value tags, and what they free up
#
# Part of the "json-like" test suite. Sourced by "test/test.bash", never run on
# its own: it uses the counters and assertions the harness defines.
#
# json-like - Nested data structures for BASH "inverted (c)" BSD-3-Clause
# Eduardo Lucio Amorim Costa
#

echo " --- The index operator ---"

# An index is written with a backslash in front of it. Without that prefix a
# path item is an object key, taken literally, whatever it looks like. These
# are the keys that had no representation at all before the operator existed.
declare INDEX_OBJ
json_like.set_obj INDEX_OBJ

json_like.set "$INDEX_OBJ" "s.Value0" "o.ObjectKey" "o.ArrayKey" "i.0"
json_like.set "$INDEX_OBJ" "s.Value1" "o.ObjectKey" "o.ArrayKey" "i.+"
json_like.get GET_RTN "$INDEX_OBJ" "ObjectKey" "ArrayKey" "1"
t_equals "a backslash marks an index" "Value1" "$GET_RTN"

json_like.get GET_RTN "$INDEX_OBJ" "ObjectKey" "ArrayKey" "-1"
t_equals "a backslash marks a negative index" "Value1" "$GET_RTN"

json_like.get_length ARRAY_LENGTH "$INDEX_OBJ" "ObjectKey" "ArrayKey"
t_equals "the marked indexes built a real array" "2" "$ARRAY_LENGTH"

# Without the prefix the very same characters are ordinary keys.
json_like.set "$INDEX_OBJ" "s.ZeroKey"  "o.ObjectKey" "o.MapKey" "o.0"
json_like.set "$INDEX_OBJ" "s.PlusKey"  "o.ObjectKey" "o.MapKey" "o.+"
json_like.set "$INDEX_OBJ" "s.MinusKey" "o.ObjectKey" "o.MapKey" "o.-1"
json_like.set "$INDEX_OBJ" "s.CodeKey"  "o.ObjectKey" "o.MapKey" "o.4217"
json_like.set "$INDEX_OBJ" "s.PaddedKey" "o.ObjectKey" "o.MapKey" "o.007"

json_like.get GET_RTN "$INDEX_OBJ" "ObjectKey" "MapKey" "0"
t_equals 'an unmarked "0" is an object key' "ZeroKey" "$GET_RTN"
json_like.get GET_RTN "$INDEX_OBJ" "ObjectKey" "MapKey" "+"
t_equals 'an unmarked "+" is an object key' "PlusKey" "$GET_RTN"
json_like.get GET_RTN "$INDEX_OBJ" "ObjectKey" "MapKey" "-1"
t_equals 'an unmarked "-1" is an object key' "MinusKey" "$GET_RTN"
json_like.get GET_RTN "$INDEX_OBJ" "ObjectKey" "MapKey" "4217"
t_equals "a numeric key keeps its digits" "CodeKey" "$GET_RTN"
json_like.get GET_RTN "$INDEX_OBJ" "ObjectKey" "MapKey" "007"
t_equals "a zero-padded key is not the index it resembles" "PaddedKey" "$GET_RTN"

# The container holding those keys must be an object, not an array: this is
# the silent conversion the operator was introduced to prevent.
t_fails "a map of numeric keys is not an array" \
    json_like.get_length ARRAY_LENGTH "$INDEX_OBJ" "ObjectKey" "MapKey"

# Deleting one numeric key must not renumber its siblings the way an array
# element delete does.
json_like.delete "$INDEX_OBJ" "ObjectKey" "MapKey" "0"
json_like.get GET_RTN "$INDEX_OBJ" "ObjectKey" "MapKey" "4217"
t_equals "deleting a numeric key leaves the others in place" "CodeKey" "$GET_RTN"
t_fails "the deleted numeric key is gone" \
    json_like.get GET_RTN "$INDEX_OBJ" "ObjectKey" "MapKey" "0"

# Documented limitation: a key that IS the operator cannot be addressed.
t_fails "a key written like the operator is read as an index" \
    json_like.set "$INDEX_OBJ" "s.Impossible" "o.ObjectKey" "o.MapKey" "i.0"

json_like.unset_obj INDEX_OBJ

echo
echo " --- Backslashes in keys ---"

# The flattened path escapes ".", "[" and "]" so a key can contain them. The
# escape character itself has to be escaped too, or the mapping is lossy: a key
# ending in a backslash, joined to a child, produced the same stored path as a
# single key holding a dot, and whichever was written second silently replaced
# the first.
declare SLASH_OBJ
json_like.set_obj SLASH_OBJ

json_like.set "$SLASH_OBJ" "s.NestedValue" 'o.a\' "o.b"
json_like.set "$SLASH_OBJ" "s.DottedValue" 'o.a.b'

json_like.get GET_RTN "$SLASH_OBJ" 'a\' "b"
t_equals 'a key ending in a backslash keeps its child' "NestedValue" "$GET_RTN"
json_like.get GET_RTN "$SLASH_OBJ" 'a.b'
t_equals 'and the key "a.b" is a different place' "DottedValue" "$GET_RTN"

declare -A SLASH_SUBTREE=()
json_like.get SLASH_SUBTREE "$SLASH_OBJ"
t_equals "both survive in the same object" "2" "${#SLASH_SUBTREE[@]}"

# Deleting one must not take the other with it.
json_like.delete "$SLASH_OBJ" 'a.b'
json_like.get GET_RTN "$SLASH_OBJ" 'a\' "b"
t_equals "deleting one leaves the other alone" "NestedValue" "$GET_RTN"

json_like.unset_obj SLASH_OBJ

echo
echo " --- The six JSON types ---"

# A value carries its JSON type the same way a path item carries its kind.
# Without that, "8080" cannot say whether it is the number or the string, and a
# serialiser would have to guess from the characters.
declare TYPE_OBJ
json_like.set_obj TYPE_OBJ

t_succeeds "a string value"  json_like.set "$TYPE_OBJ" "s.texto"  "o.RootKey" "o.StringKey"
t_succeeds "a number value"  json_like.set "$TYPE_OBJ" "n.8080"   "o.RootKey" "o.NumberKey"
t_succeeds "a boolean value" json_like.set "$TYPE_OBJ" "b.true"   "o.RootKey" "o.BooleanKey"
t_succeeds "a null value"    json_like.set "$TYPE_OBJ" "z.null"   "o.RootKey" "o.NullKey"
t_succeeds "an empty object" json_like.set "$TYPE_OBJ" ""         "o.RootKey" "o.ObjectKey" "e.{}"
t_succeeds "an empty array"  json_like.set "$TYPE_OBJ" ""         "o.RootKey" "o.ArrayKey" "e.[]"

# "get" hands back the value itself: the tag is consumed on the way in.
json_like.get GET_RTN "$TYPE_OBJ" "RootKey" "NumberKey"
t_equals "a read gives the value, not the tag" "8080" "$GET_RTN"

# The distinction the tags exist for: same characters, different type.
json_like.set "$TYPE_OBJ" "s.8080"  "o.RootKey" "o.StringNumberKey"
json_like.set "$TYPE_OBJ" "s.true"  "o.RootKey" "o.StringBooleanKey"
json_like.set "$TYPE_OBJ" "s.null"  "o.RootKey" "o.StringNullKey"

declare NUMBER_TYPE=0 STRING_NUMBER_TYPE=0
json_like._get_type NUMBER_TYPE        "$TYPE_OBJ" "RootKey.NumberKey"
json_like._get_type STRING_NUMBER_TYPE "$TYPE_OBJ" "RootKey.StringNumberKey"
t_equals "the number and the string holding it differ" \
    "different" "$( ((NUMBER_TYPE != string_number_type)) && echo different || echo same )"

json_like.get GET_RTN "$TYPE_OBJ" "RootKey" "StringNumberKey"
t_equals 'the string "8080" still reads back whole' "8080" "$GET_RTN"

# The grammar is RFC 8259's, so a serialiser cannot be handed something that
# will not parse.
t_succeeds "a negative number"   json_like.set "$TYPE_OBJ" "n.-1"      "o.NumbersKey" "o.A"
t_succeeds "a fractional number" json_like.set "$TYPE_OBJ" "n.3.14"    "o.NumbersKey" "o.B"
t_succeeds "an exponent"         json_like.set "$TYPE_OBJ" "n.-1.5e3"  "o.NumbersKey" "o.C"
t_succeeds "a capital exponent"  json_like.set "$TYPE_OBJ" "n.1E+10"   "o.NumbersKey" "o.D"
t_fails "letters are not a number"        json_like.set "$TYPE_OBJ" "n.abc" "o.BadKey"
t_fails "a leading zero is not a number"  json_like.set "$TYPE_OBJ" "n.007" "o.BadKey"
t_fails "only true and false are boolean" json_like.set "$TYPE_OBJ" "b.yes" "o.BadKey"
t_fails "the only null is null"           json_like.set "$TYPE_OBJ" "z.nil" "o.BadKey"
t_fails "an unknown value tag is refused" json_like.set "$TYPE_OBJ" "q.x"   "o.BadKey"
t_fails "an untagged value is refused"    json_like.set "$TYPE_OBJ" "plain" "o.BadKey"

# A typed value is still a value: it cannot also hold items.
t_fails "a number cannot hold items" \
    json_like.set "$TYPE_OBJ" "s.x" "o.RootKey" "o.NumberKey" "o.Child"
t_fails "a boolean is not indexable" \
    json_like.get_length ARRAY_LENGTH "$TYPE_OBJ" "RootKey" "BooleanKey"

json_like.unset_obj TYPE_OBJ

echo
echo " --- No unreachable key ---"

# The tag splits on the FIRST dot, so everything after it is literal. That is
# what makes every key a JSON document can hold reachable, including the ones
# that look exactly like the notation itself.
declare REACH_OBJ
json_like.set_obj REACH_OBJ

declare -a REACHABLE_KEYS=(
    "0" "42" "007" "-1" "+"
    "i.0" "o.Name" "e.{}" "e.[]"
    "/0" "/+" "{}" "[]"
    "." ".." "a.b" "x[0]" " "
)

REACH_FAILURES=0
REACH_DETAIL=""
for ((LOOP_INDEX = 0; LOOP_INDEX < ${#REACHABLE_KEYS[@]}; LOOP_INDEX++)) ; do
    if ! json_like.set "$REACH_OBJ" "s.Value$LOOP_INDEX" "o.MapKey" "o.${REACHABLE_KEYS[LOOP_INDEX]}" 2> /dev/null ; then
        REACH_FAILURES=$((REACH_FAILURES + 1))
        REACH_DETAIL="could not write key [${REACHABLE_KEYS[LOOP_INDEX]}]"
        continue
    fi
    GET_RTN=""
    if ! json_like.get GET_RTN "$REACH_OBJ" "MapKey" "${REACHABLE_KEYS[LOOP_INDEX]}" 2> /dev/null \
            || [[ "$GET_RTN" != "Value$LOOP_INDEX" ]] ; then
        REACH_FAILURES=$((REACH_FAILURES + 1))
        REACH_DETAIL="key [${REACHABLE_KEYS[LOOP_INDEX]}] read back as [$GET_RTN]"
    fi
done
t_report "$REACH_FAILURES" \
    "every key shape round-trips (${#REACHABLE_KEYS[@]} of them)" "$REACH_DETAIL"

# None of them turned the container into an array along the way.
t_fails "a map of notation-shaped keys is still an object" \
    json_like.get_length ARRAY_LENGTH "$REACH_OBJ" "MapKey"

declare -A REACH_SUBTREE=()
json_like.get REACH_SUBTREE "$REACH_OBJ" "MapKey"
t_equals "all of them are present at once" "${#REACHABLE_KEYS[@]}" "${#REACH_SUBTREE[@]}"

json_like.unset_obj REACH_OBJ

echo

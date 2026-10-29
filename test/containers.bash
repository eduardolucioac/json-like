#!/bin/bash
#
# test/containers.bash - empty containers, and value versus container
#
# Part of the "json-like" test suite. Sourced by "test/test.bash", never run on
# its own: it uses the counters and assertions the harness defines.
#
# json-like - Nested data structures for BASH "inverted (c)" BSD-3-Clause
# Eduardo Lucio Amorim Costa
#

echo " --- Empty containers ---"

# "/{}" and "/[]" are not a level of their own: they describe the container at
# the path before them. Nothing is written to the data array for them, which is
# what keeps them apart from the literal strings "{}" and "[]".
declare EMPTY_OBJ
json_like.set_obj EMPTY_OBJ

t_succeeds "an empty object can be created" \
    json_like.set "$EMPTY_OBJ" "" "o.RootKey" "o.EmptyObjectKey" "e.{}"
t_succeeds "an empty array can be created" \
    json_like.set "$EMPTY_OBJ" "" "o.RootKey" "o.EmptyArrayKey" "e.[]"

declare -A EMPTY_SUBTREE=()
t_succeeds "a subtree read of an empty object succeeds" \
    json_like.get EMPTY_SUBTREE "$EMPTY_OBJ" "RootKey" "EmptyObjectKey"
t_equals "a subtree read of an empty object is empty" "0" "${#EMPTY_SUBTREE[@]}"

ARRAY_LENGTH=""
json_like.get_length ARRAY_LENGTH "$EMPTY_OBJ" "RootKey" "EmptyArrayKey"
t_equals "an empty array has length zero" "0" "$ARRAY_LENGTH"

# The literal strings must stay plain values, never containers.
json_like.set "$EMPTY_OBJ" "s.{}" "o.RootKey" "o.LiteralObjectKey"
json_like.get GET_RTN "$EMPTY_OBJ" "RootKey" "LiteralObjectKey"
t_equals 'the string "{}" is a value, not an empty object' "{}" "$GET_RTN"
t_fails 'the string "{}" did not become a container' \
    json_like.get_length ARRAY_LENGTH "$EMPTY_OBJ" "RootKey" "LiteralObjectKey"

t_fails "an empty container takes no value" \
    json_like.set "$EMPTY_OBJ" "NotEmpty" "o.RootKey" "o.BadKey" "e.{}"
t_fails "an empty container cannot land on a value" \
    json_like.set "$EMPTY_OBJ" "" "o.RootKey" "o.LiteralObjectKey" "e.{}"
t_fails "a value cannot land on an empty container" \
    json_like.set "$EMPTY_OBJ" "s.Value" "o.RootKey" "o.EmptyObjectKey"

# An empty container is a normal container that happens to hold nothing: the
# first write into it works, and the first element of an empty array is 0.
t_succeeds "an empty object accepts a key" \
    json_like.set "$EMPTY_OBJ" "s.Value" "o.RootKey" "o.EmptyObjectKey" "o.FirstKey"
json_like.get GET_RTN "$EMPTY_OBJ" "RootKey" "EmptyObjectKey" "FirstKey"
t_equals "what was written into the empty object reads back" "Value" "$GET_RTN"

json_like.set "$EMPTY_OBJ" "s.First" "o.RootKey" "o.EmptyArrayKey" "i.+"
json_like.get GET_RTN "$EMPTY_OBJ" "RootKey" "EmptyArrayKey" "0"
t_equals "the first append to an empty array lands at index 0" "First" "$GET_RTN"

t_succeeds "an empty container can be deleted" \
    json_like.set "$EMPTY_OBJ" "" "o.RootKey" "o.GoneKey" "e.[]"
json_like.delete "$EMPTY_OBJ" "RootKey" "GoneKey"
t_fails "the deleted empty container left no cache entry behind" \
    json_like.get_length ARRAY_LENGTH "$EMPTY_OBJ" "RootKey" "GoneKey"

# This is the shape that could not be written at all before: an empty object
# sitting at index 0 is what keeps the array dense for index 1.
declare DENSE_OBJ
json_like.set_obj DENSE_OBJ
t_succeeds "an empty object can be an array element" \
    json_like.set "$DENSE_OBJ" "" "o.ListKey" "i.0" "e.{}"
t_succeeds "the element after an empty one keeps the array dense" \
    json_like.set "$DENSE_OBJ" "s.Value" "o.ListKey" "i.1" "o.NameKey"
ARRAY_LENGTH=""
json_like.get_length ARRAY_LENGTH "$DENSE_OBJ" "ListKey"
t_equals "both elements count towards the length" "2" "$ARRAY_LENGTH"

json_like.delete "$DENSE_OBJ" "ListKey" "0"
json_like.get GET_RTN "$DENSE_OBJ" "ListKey" "0" "NameKey"
t_equals "deleting the empty element renumbers the one above it" "Value" "$GET_RTN"

json_like.unset_obj DENSE_OBJ
json_like.unset_obj EMPTY_OBJ

echo
echo " --- Value / container collisions ---"

declare MIX_OBJ
json_like.set_obj MIX_OBJ
json_like.set "$MIX_OBJ" "s.ScalarValue" "o.x"
t_fails "a value cannot be given items" \
    json_like.set "$MIX_OBJ" "s.ChildValue" "o.x" "o.y"

json_like.set "$MIX_OBJ" "s.ChildValue" "o.y" "o.ChildKey"
t_fails "a container cannot be given a value" \
    json_like.set "$MIX_OBJ" "s.ScalarValue" "o.y"

json_like.set "$MIX_OBJ" "s.Element0" "o.ArrayKey" "i.0" "o.NameKey"
t_fails "an array element holding an object cannot be given a value" \
    json_like.set "$MIX_OBJ" "s.ScalarValue" "o.ArrayKey" "i.0"

json_like.set "$MIX_OBJ" "s.Scalar0" "o.ScalarArrayKey" "i.0"
t_fails "an array element holding a value cannot be given items" \
    json_like.set "$MIX_OBJ" "s.ChildValue" "o.ScalarArrayKey" "i.0" "o.NameKey"

json_like.set "$MIX_OBJ" "s.PlainValue" "o.PlainArrayKey" "i.0"
t_fails "an array cannot be given a value of its own" \
    json_like.set "$MIX_OBJ" "s.ScalarValue" "o.PlainArrayKey"

json_like.get GET_RTN "$MIX_OBJ" "x"
t_equals "a rejected set leaves the previous value untouched" "ScalarValue" "$GET_RTN"

declare -A MIX_STATE=()
json_like.get MIX_STATE "$MIX_OBJ"
if ((${#MIX_STATE[@]} == 5)) ; then
    t_report 0 "a rejected set adds nothing to the object"
else
    t_report 1 "a rejected set adds nothing to the object" \
        "got ${#MIX_STATE[@]} keys: ${!MIX_STATE[*]}"
fi

echo

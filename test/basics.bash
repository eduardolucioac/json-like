#!/bin/bash
#
# test/basics.bash - object lifecycle, objects, arrays, subtree reads
#
# Part of the "json-like" test suite. Sourced by "test/test.bash", never run on
# its own: it uses the counters and assertions the harness defines.
#
# json-like - Nested data structures for BASH "inverted (c)" BSD-3-Clause
# Eduardo Lucio Amorim Costa
#

echo " --- Object lifecycle ---"

declare JSON_LIKE_OBJ
json_like.set_obj JSON_LIKE_OBJ
if [ -n "$JSON_LIKE_OBJ" ] ; then
    t_report 0 "set_obj stores an object id"
else
    t_report 1 "set_obj stores an object id"
fi

if declare -p "JL_DATA_$JSON_LIKE_OBJ" > /dev/null 2>&1 \
        && declare -p "JL_TYPE_CACHE_$JSON_LIKE_OBJ" > /dev/null 2>&1 \
        && declare -p "JL_LENGTH_CACHE_$JSON_LIKE_OBJ" > /dev/null 2>&1 ; then
    t_report 0 "set_obj creates the data array and both caches"
else
    t_report 1 "set_obj creates the data array and both caches"
fi

declare THROWAWAY_OBJ
json_like.set_obj THROWAWAY_OBJ
THROWAWAY_ID="$THROWAWAY_OBJ"
json_like.unset_obj THROWAWAY_OBJ
if declare -p "JL_DATA_$THROWAWAY_ID" > /dev/null 2>&1 ; then
    t_report 1 "unset_obj destroys the object arrays"
else
    t_report 0 "unset_obj destroys the object arrays"
fi

t_fails "operating on an unknown object id fails" \
    json_like.get G "NO_SUCH_OBJECT" "any"
t_fails "set on an unknown object id fails" \
    json_like.set "NO_SUCH_OBJECT" "s.v" "o.any"
t_fails "delete on an unknown object id fails" \
    json_like.delete "NO_SUCH_OBJECT" "any"
t_fails "get_length on an unknown object id fails" \
    json_like.get_length L "NO_SUCH_OBJECT" "any"

echo
echo " --- Objects ---"

t_silent_on_stdout "set writes nothing to stdout" \
    json_like.set "$JSON_LIKE_OBJ" "s.Value" "o.ObjectKey" "o.NestedObjectKey" "o.Key1"

json_like.set "$JSON_LIKE_OBJ" "s.Value" "o.ObjectKey" "o.NestedObjectKey" "o.Key1"
json_like.get GET_RTN "$JSON_LIKE_OBJ" "ObjectKey" "NestedObjectKey" "Key1"
t_equals "set then get a nested object value" "Value" "$GET_RTN"

GET_RTN=$(json_like.get "-" "$JSON_LIKE_OBJ" "ObjectKey" "NestedObjectKey" "Key1")
t_equals 'get in "-" mode prints the value' "Value" "$GET_RTN"

json_like.set "$JSON_LIKE_OBJ" "s.Value" "o.Object1Key" "o.Object2Key" "o.Object3Key" "o.Object4Key" "o.Key"
json_like.get GET_RTN "$JSON_LIKE_OBJ" "Object1Key" "Object2Key" "Object3Key" "Object4Key" "Key"
t_equals "set then get a deep path" "Value" "$GET_RTN"

json_like.set "$JSON_LIKE_OBJ" "s.Value" "o.ObjectKey" "o.OverwriteKey"
json_like.set "$JSON_LIKE_OBJ" "s.NewValue" "o.ObjectKey" "o.OverwriteKey"
json_like.get GET_RTN "$JSON_LIKE_OBJ" "ObjectKey" "OverwriteKey"
t_equals "overwriting an existing key keeps the last value" "NewValue" "$GET_RTN"

t_fails "get on a non-existing key fails" \
    json_like.get GET_RTN "$JSON_LIKE_OBJ" "ObjectKey" "NonExistingKey"

# JSON allows {"": 1}, but the library does not: see the limitations. The
# refusal is the same at every level, which is the point of it.
t_fails "the empty key is refused at the first level" \
    json_like.set "$JSON_LIKE_OBJ" "s.V" "o."
t_fails "the empty key is refused deeper down too" \
    json_like.set "$JSON_LIKE_OBJ" "s.V" "o.ObjectKey" "o."

t_fails "an untagged path item is rejected on set" \
    json_like.set "$JSON_LIKE_OBJ" "s.v" "ObjectKey" "Key"
t_fails "an unknown tag is rejected on set" \
    json_like.set "$JSON_LIKE_OBJ" "s.v" "o.ObjectKey" "x.Key"
t_fails "an empty container is rejected anywhere but last" \
    json_like.set "$JSON_LIKE_OBJ" "s.v" "o.ObjectKey" "e.{}" "o.Key"
t_fails "a malformed index is rejected" \
    json_like.set "$JSON_LIKE_OBJ" "s.v" "o.ObjectKey" "i.abc"

t_fails "set with no path at all is rejected" \
    json_like.set "$JSON_LIKE_OBJ" "s.v"

echo
echo " --- Arrays ---"

json_like.set "$JSON_LIKE_OBJ" "s.Value1" "o.ObjectKey" "o.ArrayKey" "i.0"
json_like.get GET_RTN "$JSON_LIKE_OBJ" "ObjectKey" "ArrayKey" "0"
t_equals "set then get an array element by index" "Value1" "$GET_RTN"

json_like.set "$JSON_LIKE_OBJ" "s.Value2" "o.ObjectKey" "o.ArrayKey" "i.+"
json_like.get GET_RTN "$JSON_LIKE_OBJ" "ObjectKey" "ArrayKey" "-1"
t_equals 'appending with "+" lands on the last index' "Value2" "$GET_RTN"

json_like.get_length ARRAY_LENGTH "$JSON_LIKE_OBJ" "ObjectKey" "ArrayKey"
t_equals "get_length reports the element count" "2" "$ARRAY_LENGTH"

json_like.get GET_RTN "$JSON_LIKE_OBJ" "ObjectKey" "ArrayKey" "-2"
t_equals 'a negative index counts from the end' "Value1" "$GET_RTN"

t_fails "an out of range negative index fails" \
    json_like.get GET_RTN "$JSON_LIKE_OBJ" "ObjectKey" "ArrayKey" "-99"

t_fails 'the "+" wildcard is rejected by get' \
    json_like.get GET_RTN "$JSON_LIKE_OBJ" "ObjectKey" "ArrayKey" "+"

t_fails 'the "+" wildcard is rejected by delete' \
    json_like.delete "$JSON_LIKE_OBJ" "ObjectKey" "ArrayKey" "+"

t_fails "set beyond the end of an array fails" \
    json_like.set "$JSON_LIKE_OBJ" "s.HoleValue" "o.ObjectKey" "o.ArrayKey" "i.9"

json_like.set "$JSON_LIKE_OBJ" "s.ReplacedValue" "o.ObjectKey" "o.ArrayKey" "i.-1"
json_like.get GET_RTN "$JSON_LIKE_OBJ" "ObjectKey" "ArrayKey" "1"
json_like.get_length ARRAY_LENGTH "$JSON_LIKE_OBJ" "ObjectKey" "ArrayKey"
if [[ "$GET_RTN" == "ReplacedValue" ]] && [[ "$ARRAY_LENGTH" == "2" ]] ; then
    t_report 0 "set with a negative index replaces instead of appending"
else
    t_report 1 "set with a negative index replaces instead of appending" \
        "value [$GET_RTN] length [$ARRAY_LENGTH]"
fi

t_fails "an array cannot be addressed through a named key" \
    json_like.set "$JSON_LIKE_OBJ" "s.v" "o.ObjectKey" "o.ArrayKey" "o.SomeKey"

t_fails "get_length on something that is not an array fails" \
    json_like.get_length L "$JSON_LIKE_OBJ" "ObjectKey" "OverwriteKey"

declare ORDER_OBJ
json_like.set_obj ORDER_OBJ
for LOOP_VALUE in "First" "Second" "Third" ; do
    json_like.set "$ORDER_OBJ" "s.$LOOP_VALUE" "o.ObjectKey" "o.DynamicArrayKey" "i.+"
done
json_like.get_length ARRAY_LENGTH "$ORDER_OBJ" "ObjectKey" "DynamicArrayKey"
ORDER_OBTAINED=""
for ((LOOP_INDEX = 0; LOOP_INDEX < ARRAY_LENGTH; LOOP_INDEX++)) ; do
    json_like.get GET_RTN "$ORDER_OBJ" "ObjectKey" "DynamicArrayKey" "$LOOP_INDEX"
    ORDER_OBTAINED="${ORDER_OBTAINED}${ORDER_OBTAINED:+,}$GET_RTN"
done
t_equals "repeated appends keep their order" "First,Second,Third" "$ORDER_OBTAINED"

echo
echo " --- Arrays of objects ---"

declare AOA_OBJ
json_like.set_obj AOA_OBJ
json_like.set "$AOA_OBJ" "s.Name0" "o.RootKey" "o.ObjectArrayKey" "i.0" "o.NameKey"
json_like.set "$AOA_OBJ" "s.Age0" "o.RootKey" "o.ObjectArrayKey" "i.0" "o.AgeKey"
json_like.set "$AOA_OBJ" "s.Name1" "o.RootKey" "o.ObjectArrayKey" "i.1" "o.NameKey"
json_like.set "$AOA_OBJ" "s.Age1" "o.RootKey" "o.ObjectArrayKey" "i.1" "o.AgeKey"
json_like.set "$AOA_OBJ" "s.Name2" "o.RootKey" "o.ObjectArrayKey" "i.2" "o.NameKey"
json_like.set "$AOA_OBJ" "s.DeepValue" "o.RootKey" "o.ObjectArrayKey" "i.0" "o.SubKey" "o.x"

json_like.get GET_RTN "$AOA_OBJ" "RootKey" "ObjectArrayKey" "0" "SubKey" "x"
t_equals "an object nested inside an array element round-trips" "DeepValue" "$GET_RTN"

json_like.get_length ARRAY_LENGTH "$AOA_OBJ" "RootKey" "ObjectArrayKey"
t_equals "an array of objects reports its length" "3" "$ARRAY_LENGTH"

json_like.set "$AOA_OBJ" "s.Tag0" "o.RootKey" "o.ObjectArrayKey" "i.-1" "o.TagsKey" "i.+"
json_like.get_length ARRAY_LENGTH "$AOA_OBJ" "RootKey" "ObjectArrayKey" "-1" "TagsKey"
t_equals "a negative index resolves mid-path" "1" "$ARRAY_LENGTH"

echo
echo " --- Subtree reads ---"

declare -A SUBTREE=()
json_like.get SUBTREE "$AOA_OBJ" "RootKey" "ObjectArrayKey" "0"
if [[ "${SUBTREE['ObjectArrayKey[0].NameKey']}" == "Name0" ]] \
        && [[ "${SUBTREE['ObjectArrayKey[0].SubKey.x']}" == "DeepValue" ]] \
        && ((${#SUBTREE[@]} == 3)) ; then
    t_report 0 "a subtree read returns the element and its descendants"
else
    t_report 1 "a subtree read returns the element and its descendants" \
        "got ${#SUBTREE[@]} keys: ${!SUBTREE[*]}"
fi

declare -A SUBTREE_ALL=()
json_like.get SUBTREE_ALL "$AOA_OBJ"
if ((${#SUBTREE_ALL[@]} == 7)) ; then
    t_report 0 "a path-less subtree read copies the whole object"
else
    t_report 1 "a path-less subtree read copies the whole object" \
        "got ${#SUBTREE_ALL[@]} keys, expected 7"
fi

SUBTREE_ALL["Injected"]="should not reach the object"
json_like.get GET_RTN "$AOA_OBJ" "InjectedKey" 2>/dev/null
t_report "$((1 - $?))" "a subtree read returns a copy, not a reference"

declare COLLIDE_OBJ
json_like.set_obj COLLIDE_OBJ
json_like.set "$COLLIDE_OBJ" "s.ShortValue" "o.CollideKey" "o.a"
json_like.set "$COLLIDE_OBJ" "s.LongValue" "o.CollideKey" "o.ab"
declare -A COLLIDE=()
json_like.get COLLIDE "$COLLIDE_OBJ" "CollideKey" "a"
if ((${#COLLIDE[@]} == 1)) && [[ "${COLLIDE[a]}" == "ShortValue" ]] ; then
    t_report 0 "a subtree read does not leak a sibling with a longer name"
else
    t_report 1 "a subtree read does not leak a sibling with a longer name" \
        "got ${#COLLIDE[@]} keys: ${!COLLIDE[*]}"
fi

declare -a INDEXED_TARGET=()
t_fails "an indexed array is rejected as a get target" \
    json_like.get INDEXED_TARGET "$AOA_OBJ" "RootKey"

echo

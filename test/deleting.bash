#!/bin/bash
#
# test/deleting.bash - deleting in all its forms, and the caches after it
#
# Part of the "json-like" test suite. Sourced by "test/test.bash", never run on
# its own: it uses the counters and assertions the harness defines.
#
# json-like - Nested data structures for BASH "inverted (c)" BSD-3-Clause
# Eduardo Lucio Amorim Costa
#

echo " --- Deleting ---"

declare DEL_OBJ
json_like.set_obj DEL_OBJ
json_like.set "$DEL_OBJ" "s.LeafValue" "o.ObjectKey" "o.LeafKey"
json_like.set "$DEL_OBJ" "s.KeptValue" "o.ObjectKey" "o.KeptKey"

t_silent_on_stdout "delete writes nothing to stdout" \
    json_like.delete "$DEL_OBJ" "ObjectKey" "LeafKey"

json_like.set "$DEL_OBJ" "s.LeafValue" "o.ObjectKey" "o.LeafKey"
t_succeeds "deleting a leaf succeeds without any stderr noise" \
    json_like.delete "$DEL_OBJ" "ObjectKey" "LeafKey"
t_fails "a deleted leaf can no longer be read" \
    json_like.get GET_RTN "$DEL_OBJ" "ObjectKey" "LeafKey"
json_like.get GET_RTN "$DEL_OBJ" "ObjectKey" "KeptKey"
t_equals "deleting a leaf leaves its sibling alone" "KeptValue" "$GET_RTN"

t_fails "deleting a non-existing key fails" \
    json_like.delete "$DEL_OBJ" "ObjectKey" "NonExistingKey"

declare SUB_OBJ
json_like.set_obj SUB_OBJ
json_like.set "$SUB_OBJ" "s.A" "o.RootKey" "o.BranchKey" "o.a"
json_like.set "$SUB_OBJ" "s.B" "o.RootKey" "o.BranchKey" "o.b" "o.DeepKey"
json_like.set "$SUB_OBJ" "s.C" "o.RootKey" "o.OtherKey"
t_succeeds "deleting a subtree succeeds without any stderr noise" \
    json_like.delete "$SUB_OBJ" "RootKey" "BranchKey"
t_fails "a deleted subtree is gone" \
    json_like.get GET_RTN "$SUB_OBJ" "RootKey" "BranchKey" "b" "DeepKey"
json_like.get GET_RTN "$SUB_OBJ" "RootKey" "OtherKey"
t_equals "deleting a subtree leaves the rest alone" "C" "$GET_RTN"

declare DELARR_OBJ
json_like.set_obj DELARR_OBJ
json_like.set "$DELARR_OBJ" "s.Value0" "o.ObjectKey" "o.ArrayKey" "i.0"
json_like.set "$DELARR_OBJ" "s.Value1" "o.ObjectKey" "o.ArrayKey" "i.1"
json_like.set "$DELARR_OBJ" "s.Value2" "o.ObjectKey" "o.ArrayKey" "i.2"
json_like.set "$DELARR_OBJ" "s.KeptValue" "o.ObjectKey" "o.KeptKey"

t_succeeds "deleting one array element succeeds without any stderr noise" \
    json_like.delete "$DELARR_OBJ" "ObjectKey" "ArrayKey" "1"

json_like.get_length ARRAY_LENGTH "$DELARR_OBJ" "ObjectKey" "ArrayKey"
t_equals "deleting an array element decrements the length" "2" "$ARRAY_LENGTH"

json_like.get GET_RTN "$DELARR_OBJ" "ObjectKey" "ArrayKey" "1"
t_equals "deleting an array element renumbers the ones above it" "Value2" "$GET_RTN"

t_fails "the index freed by a delete is out of range again" \
    json_like.get GET_RTN "$DELARR_OBJ" "ObjectKey" "ArrayKey" "2"

t_fails "deleting an out of range index fails" \
    json_like.delete "$DELARR_OBJ" "ObjectKey" "ArrayKey" "7"

json_like.delete "$DELARR_OBJ" "ObjectKey" "ArrayKey" "-1"
json_like.get_length ARRAY_LENGTH "$DELARR_OBJ" "ObjectKey" "ArrayKey"
json_like.get GET_RTN "$DELARR_OBJ" "ObjectKey" "ArrayKey" "0"
if [[ "$ARRAY_LENGTH" == "1" ]] && [[ "$GET_RTN" == "Value0" ]] ; then
    t_report 0 "deleting with a negative index removes the last element"
else
    t_report 1 "deleting with a negative index removes the last element" \
        "length [$ARRAY_LENGTH] first [$GET_RTN]"
fi

t_succeeds "deleting a whole array succeeds" \
    json_like.delete "$DELARR_OBJ" "ObjectKey" "ArrayKey"
t_fails "a deleted array is gone from the data" \
    json_like.get GET_RTN "$DELARR_OBJ" "ObjectKey" "ArrayKey" "0"
t_fails "a deleted array is gone from the length cache" \
    json_like.get_length ARRAY_LENGTH "$DELARR_OBJ" "ObjectKey" "ArrayKey"
json_like.get GET_RTN "$DELARR_OBJ" "ObjectKey" "KeptKey"
t_equals "deleting a whole array leaves its sibling alone" "KeptValue" "$GET_RTN"

echo
echo " --- Deleting a leaf without AWK ---"

# A value is the only thing with a row of its own in the data array, so a path
# that has one is a leaf with certainty and is deleted in BASH. These pin the
# cases the fast path must NOT claim, and that it leaves nothing behind.
declare LEAF_OBJ
json_like.set_obj LEAF_OBJ

json_like.set "$LEAF_OBJ" "s.LeafValue"  "o.RootKey" "o.LeafKey"
json_like.set "$LEAF_OBJ" "s.KeptValue"  "o.RootKey" "o.KeptKey"
json_like.set "$LEAF_OBJ" "s.DeepValue"  "o.RootKey" "o.BranchKey" "o.DeepKey"
json_like.set "$LEAF_OBJ" "s.Element0"   "o.RootKey" "o.ArrayKey" "i.0"
json_like.set "$LEAF_OBJ" "s.Element1"   "o.RootKey" "o.ArrayKey" "i.+"

t_succeeds "a leaf is deleted" \
    json_like.delete "$LEAF_OBJ" "RootKey" "LeafKey"
t_fails "the deleted leaf is gone" \
    json_like.get GET_RTN "$LEAF_OBJ" "RootKey" "LeafKey"
json_like.get GET_RTN "$LEAF_OBJ" "RootKey" "KeptKey"
t_equals "its sibling is untouched" "KeptValue" "$GET_RTN"

# The type cache has to go with it, or a later "set" sees a node that is not
# there any more.
t_succeeds "the path can be written again afterwards" \
    json_like.set "$LEAF_OBJ" "s.Rewritten" "o.RootKey" "o.LeafKey"
json_like.get GET_RTN "$LEAF_OBJ" "RootKey" "LeafKey"
t_equals "and reads back as the new value" "Rewritten" "$GET_RTN"

# A container is NOT a leaf: it owns no row, so the full pass must still run.
json_like.delete "$LEAF_OBJ" "RootKey" "BranchKey"
t_fails "deleting a container still removes its descendants" \
    json_like.get GET_RTN "$LEAF_OBJ" "RootKey" "BranchKey" "DeepKey"

# An array element is not a leaf either, even though it owns a row: the ones
# above it have to be renumbered.
json_like.delete "$LEAF_OBJ" "RootKey" "ArrayKey" "0"
json_like.get GET_RTN "$LEAF_OBJ" "RootKey" "ArrayKey" "0"
t_equals "deleting an array element still renumbers" "Element1" "$GET_RTN"
json_like.get_length ARRAY_LENGTH "$LEAF_OBJ" "RootKey" "ArrayKey"
t_equals "and still shortens the array" "1" "$ARRAY_LENGTH"

t_fails "deleting a path that is not there still fails" \
    json_like.delete "$LEAF_OBJ" "RootKey" "NeverExisted"

json_like.unset_obj LEAF_OBJ

echo
echo " --- Cache consistency after a delete ---"

# This is the subtle one. Removing an array element has to renumber the TYPE
# and LENGTH caches too, otherwise a later "set" or "get" resolves against
# entries that describe elements which no longer exist.
declare CACHE_OBJ
json_like.set_obj CACHE_OBJ
json_like.set "$CACHE_OBJ" "s.Name0" "o.RootKey" "o.ObjectArrayKey" "i.0" "o.NameKey"
json_like.set "$CACHE_OBJ" "s.Tag00" "o.RootKey" "o.ObjectArrayKey" "i.0" "o.TagsKey" "i.+"
json_like.set "$CACHE_OBJ" "s.Name1" "o.RootKey" "o.ObjectArrayKey" "i.1" "o.NameKey"
json_like.set "$CACHE_OBJ" "s.Tag10" "o.RootKey" "o.ObjectArrayKey" "i.1" "o.TagsKey" "i.+"
json_like.set "$CACHE_OBJ" "s.Tag11" "o.RootKey" "o.ObjectArrayKey" "i.1" "o.TagsKey" "i.+"

json_like.delete "$CACHE_OBJ" "RootKey" "ObjectArrayKey" "0"

json_like.get GET_RTN "$CACHE_OBJ" "RootKey" "ObjectArrayKey" "0" "NameKey"
t_equals "the surviving element moved down to index 0" "Name1" "$GET_RTN"

json_like.get_length ARRAY_LENGTH "$CACHE_OBJ" "RootKey" "ObjectArrayKey" "0" "TagsKey"
t_equals "the length cache followed the renumbering" "2" "$ARRAY_LENGTH"

json_like.set "$CACHE_OBJ" "s.Tag12" "o.RootKey" "o.ObjectArrayKey" "i.0" "o.TagsKey" "i.+"
json_like.get GET_RTN "$CACHE_OBJ" "RootKey" "ObjectArrayKey" "0" "TagsKey" "2"
t_equals "appending after a renumbering lands on the right index" "Tag12" "$GET_RTN"

t_fails "the stale index is not readable from the length cache" \
    json_like.get_length ARRAY_LENGTH "$CACHE_OBJ" "RootKey" "ObjectArrayKey" "1" "TagsKey"

declare -A CACHE_STATE=()
json_like.get CACHE_STATE "$CACHE_OBJ"
if ((${#CACHE_STATE[@]} == 4)) ; then
    t_report 0 "no orphan data rows are left behind by the delete"
else
    t_report 1 "no orphan data rows are left behind by the delete" \
        "got ${#CACHE_STATE[@]} keys: ${!CACHE_STATE[*]}"
fi

declare -n CACHE_TYPES="JL_TYPE_CACHE_$CACHE_OBJ"
CACHE_ORPHANS=0
for CACHE_KEY in "${!CACHE_TYPES[@]}" ; do
    if [[ "$CACHE_KEY" == *"aoa[1]"* ]] ; then
        CACHE_ORPHANS=$((CACHE_ORPHANS + 1))
    fi
done
t_report "$CACHE_ORPHANS" "no orphan type-cache rows are left behind by the delete" \
    "found $CACHE_ORPHANS rows still under aoa[1]"
unset -n CACHE_TYPES

echo

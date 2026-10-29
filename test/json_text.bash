#!/bin/bash
#
# test/json_text.bash - reading JSON in and writing it back out
#
# Part of the "json-like" test suite. Sourced by "test/test.bash", never run on
# its own: it uses the counters and assertions the harness defines.
#
# json-like - Nested data structures for BASH "inverted (c)" BSD-3-Clause
# Eduardo Lucio Amorim Costa
#

echo " --- Writing JSON out ---"

declare TJ_OBJ
json_like.set_obj TJ_OBJ

json_like.set "$TJ_OBJ" "s.MY SENSORS" "o.window" "o.title"
json_like.set "$TJ_OBJ" "n.563"        "o.window" "o.width"
json_like.set "$TJ_OBJ" "b.true"       "o.window" "o.visible"
json_like.set "$TJ_OBJ" "z.null"       "o.window" "o.parent"
json_like.set "$TJ_OBJ" "s.kde"        "o.window" "o.tags" "i.+"
json_like.set "$TJ_OBJ" "s.plasma"     "o.window" "o.tags" "i.+"
json_like.set "$TJ_OBJ" ""             "o.window" "o.extras" "e.{}"
json_like.set "$TJ_OBJ" ""             "o.window" "o.empty" "e.[]"

t_run json_like.to_json - "$TJ_OBJ"
TJ_OUT="$T_RUN_STDOUT"
t_report "$T_RUN_RTN_CODE" "an object is written out as JSON" "$T_RUN_STDERR"

# Each type has to come out in its own shape, quoted or bare.
t_equals "a string is quoted"       "1" "$( [[ "$TJ_OUT" == *'"title":"MY SENSORS"'* ]] && echo 1 || echo 0 )"
t_equals "a number is bare"         "1" "$( [[ "$TJ_OUT" == *'"width":563'*          ]] && echo 1 || echo 0 )"
t_equals "a boolean is bare"        "1" "$( [[ "$TJ_OUT" == *'"visible":true'*       ]] && echo 1 || echo 0 )"
t_equals "null is bare"             "1" "$( [[ "$TJ_OUT" == *'"parent":null'*        ]] && echo 1 || echo 0 )"
t_equals "an array keeps its order" "1" "$( [[ "$TJ_OUT" == *'"tags":["kde","plasma"]'* ]] && echo 1 || echo 0 )"
t_equals "an empty object is {}"    "1" "$( [[ "$TJ_OUT" == *'"extras":{}'*          ]] && echo 1 || echo 0 )"
t_equals "an empty array is []"     "1" "$( [[ "$TJ_OUT" == *'"empty":[]'*           ]] && echo 1 || echo 0 )"

# The string holding the characters of a number must NOT come out as one.
json_like.set "$TJ_OBJ" "s.563" "o.window" "o.widthText"
t_run json_like.to_json - "$TJ_OBJ"
t_equals "a string of digits stays a string" "1" \
    "$( [[ "$T_RUN_STDOUT" == *'"widthText":"563"'* ]] && echo 1 || echo 0 )"

# Values that would break the document if they were not escaped.
declare TJ_ESC
json_like.set_obj TJ_ESC
json_like.set "$TJ_ESC" 's.with "quotes"'  "o.a"
json_like.set "$TJ_ESC" 's.with \back'     "o.b"
json_like.set "$TJ_ESC" "s.$(printf 'line1\nline2')" "o.c"
json_like.set "$TJ_ESC" "s.$(printf 'a\tb')"         "o.d"
t_run json_like.to_json - "$TJ_ESC"
t_equals "a quote is escaped"   "1" "$( [[ "$T_RUN_STDOUT" == *'"a":"with \"quotes\""'* ]] && echo 1 || echo 0 )"
# A backslash cannot be written into a "[[ == ]]" pattern literally, so the
# needle is built first and quoted into the pattern, which makes it literal.
TJ_NEEDLE='"b":"with \\back"'
t_equals "a backslash is escaped" "1" "$( [[ "$T_RUN_STDOUT" == *"$TJ_NEEDLE"* ]] && echo 1 || echo 0 )"
t_equals "a newline is escaped" "1" "$( [[ "$T_RUN_STDOUT" == *'"c":"line1\nline2"'*    ]] && echo 1 || echo 0 )"
t_equals "a tab is escaped"     "1" "$( [[ "$T_RUN_STDOUT" == *'"d":"a\tb"'*            ]] && echo 1 || echo 0 )"

# Indentation is a presentation choice, not a different document.
t_run json_like.to_json - "$TJ_ESC" 2
t_equals "an indented document is still produced" "0" "$T_RUN_RTN_CODE"
t_fails "the indent has to be a number" json_like.to_json - "$TJ_ESC" "two"

# The target comes first, like every other function that returns something:
# a variable NAME to fill in, or "-" for stdout. Both have to agree.
declare TJ_INTO_VAR=""
t_succeeds "the document can go into a variable" \
    json_like.to_json TJ_INTO_VAR "$TJ_ESC"
t_run json_like.to_json - "$TJ_ESC"
t_equals "the variable and stdout agree" "$T_RUN_STDOUT" "$TJ_INTO_VAR"

declare TJ_INDENTED=""
json_like.to_json TJ_INDENTED "$TJ_ESC" 4
t_equals "an indent reaches the variable too" "1" \
    "$( [[ "$TJ_INDENTED" == *$'\n    "a":'* ]] && echo 1 || echo 0 )"

# An empty object is a document too.
declare TJ_EMPTY
json_like.set_obj TJ_EMPTY
t_run json_like.to_json - "$TJ_EMPTY"
t_equals "an object with nothing in it is {}" "{}" "$T_RUN_STDOUT"
json_like.unset_obj TJ_EMPTY

json_like.unset_obj TJ_ESC
json_like.unset_obj TJ_OBJ

echo
echo " --- Reading JSON in ---"

declare FJ_OBJ
t_succeeds "a document is read in" \
    json_like.from_json FJ_OBJ '{"w":{"t":"MY SENSORS","n":563,"b":true,"z":null,"a":["kde","plasma"],"eo":{},"ea":[]}}'

json_like.get GET_RTN "$FJ_OBJ" "w" "t"
t_equals "a string survives"            "MY SENSORS" "$GET_RTN"
json_like.get GET_RTN "$FJ_OBJ" "w" "n"
t_equals "a number survives"            "563"        "$GET_RTN"
json_like.get GET_RTN "$FJ_OBJ" "w" "a" "1"
t_equals "an array element survives"    "plasma"     "$GET_RTN"
json_like.get_length ARRAY_LENGTH "$FJ_OBJ" "w" "a"
t_equals "the array knows its length"   "2"          "$ARRAY_LENGTH"
json_like.get_length ARRAY_LENGTH "$FJ_OBJ" "w" "ea"
t_equals "an empty array came in empty" "0"          "$ARRAY_LENGTH"

# The type has to come in with the value, or the document cannot go back out.
declare FJ_TYPE=0
json_like._get_type FJ_TYPE "$FJ_OBJ" "w.n"
t_equals "a number is typed as one"  "4" "$FJ_TYPE"
json_like._get_type FJ_TYPE "$FJ_OBJ" "w.b"
t_equals "a boolean is typed as one" "5" "$FJ_TYPE"
json_like._get_type FJ_TYPE "$FJ_OBJ" "w.z"
t_equals "null is typed as null"     "6" "$FJ_TYPE"
json_like._get_type FJ_TYPE "$FJ_OBJ" "w.t"
t_equals "a string is typed as one"  "3" "$FJ_TYPE"

# In and straight back out, which is the whole point of the pair.
t_run json_like.to_json - "$FJ_OBJ"
FJ_BACK="$T_RUN_STDOUT"
t_equals "it goes back out as a number"  "1" "$( [[ "$FJ_BACK" == *'"n":563'*  ]] && echo 1 || echo 0 )"
t_equals "it goes back out as a string"  "1" "$( [[ "$FJ_BACK" == *'"t":"MY SENSORS"'* ]] && echo 1 || echo 0 )"
t_equals "the empty object comes back"   "1" "$( [[ "$FJ_BACK" == *'"eo":{}'* ]] && echo 1 || echo 0 )"
json_like.unset_obj FJ_OBJ

# A number keeps the text it was written as.
declare FJ_NUM
json_like.from_json FJ_NUM '{"a":1E+10,"b":-0.5,"c":0}'
t_run json_like.to_json - "$FJ_NUM"
t_equals "a number keeps its exact spelling" '{"a":1E+10,"b":-0.5,"c":0}' "$T_RUN_STDOUT"
json_like.unset_obj FJ_NUM

# Escapes, including the ones that need a surrogate pair.
declare FJ_ESC
# NOTE: inside single quotes BASH passes the backslashes through untouched, so
# the document below really does carry "\\", which is ONE escaped backslash.
json_like.from_json FJ_ESC '{"q":"say \"hi\"","s":"back\\slash","n":"l1\nl2","u":"ç","p":"🚀"}'
json_like.get GET_RTN "$FJ_ESC" "q"
t_equals "an escaped quote decodes"   'say "hi"'    "$GET_RTN"
json_like.get GET_RTN "$FJ_ESC" "s"
t_equals "an escaped backslash decodes" 'back\slash' "$GET_RTN"
json_like.get GET_RTN "$FJ_ESC" "u"
t_equals "a \\u escape decodes"        "$(printf '\303\247')" "$GET_RTN"
json_like.get GET_RTN "$FJ_ESC" "p"
t_equals "a surrogate pair decodes"   "$(printf '\360\237\232\200')" "$GET_RTN"
json_like.unset_obj FJ_ESC

# What must be refused, and with a position.
declare FJ_BAD
t_fails "a missing value is refused"      json_like.from_json FJ_BAD '{"a":}'
t_fails "a single quoted key is refused"  json_like.from_json FJ_BAD "{'a':1}"
t_fails "a leading zero is refused"       json_like.from_json FJ_BAD '{"a":007}'
t_fails "a trailing comma is refused"     json_like.from_json FJ_BAD '{"a":1,}'
t_fails "trailing content is refused"     json_like.from_json FJ_BAD '{"a":1} junk'
t_fails "an unterminated string is refused" json_like.from_json FJ_BAD '{"a":"no end}'
t_fails "a truncated literal is refused"  json_like.from_json FJ_BAD '{"a":tru}'
t_fails "an unknown escape is refused"    json_like.from_json FJ_BAD '{"a":"\q"}'
t_fails "a lone surrogate is refused"     json_like.from_json FJ_BAD '{"a":"\ud800"}'
t_fails "an array root is refused"        json_like.from_json FJ_BAD '[1,2]'

t_run json_like.from_json FJ_BAD '{"a":}'
t_equals "the refusal says where" "1" \
    "$( [[ "$T_RUN_STDERR" == *"position"* ]] && echo 1 || echo 0 )"

# What the reader must refuse is exactly what the model does not hold, and
# nothing more. A key that merely LOOKS like the notation is a key: the reader
# escapes it itself instead of going through the tag parser, so it can load
# documents that "set" could not have built.
declare FJ_SHAPED
for FJ_DOC in '{"o.x":1}' '{"i.0":1}' '{"e.{}":1}' '{"s.1":1}' \
              '{"0":1}' '{"+":1}' '{"-1":1}' '{"a.b":1}' '{"x[0]":1}' ; do
    json_like.from_json FJ_SHAPED "$FJ_DOC" 2> /dev/null
    T_RUN_STDOUT=""
    json_like.to_json T_RUN_STDOUT "$FJ_SHAPED" 2> /dev/null
    t_equals "a key shaped like the notation is just a key: $FJ_DOC" \
        "$FJ_DOC" "$T_RUN_STDOUT"
    json_like.unset_obj FJ_SHAPED
done

# The document can also come from stdin, which is how a file is read.
declare FJ_PIPE
FJ_TMP=$(mktemp "${TMPDIR:-/tmp}/json-like-test-doc.XXXXXX")
printf '%s' '{"from":"a file"}' > "$FJ_TMP"
json_like.from_json FJ_PIPE < "$FJ_TMP"
json_like.get GET_RTN "$FJ_PIPE" "from"
t_equals "a document can be read from stdin" "a file" "$GET_RTN"
rm -f "$FJ_TMP"
json_like.unset_obj FJ_PIPE

echo
echo " --- What the root cannot be ---"

# RFC 8259 allows any value as a JSON text. This model has no room for one:
# the root is where keys hang from, and its flattened path is the empty
# string, which BASH will not even accept as an array subscript. Every shape
# that cannot be carried has to be refused with a reason, and refused WITHOUT
# leaving anything behind.
declare ROOT_BAD

for ROOT_DOC in '[1,2]' '"text"' '42' 'true' 'null' ; do
    t_fails "a document with $(printf '%.6s' "$ROOT_DOC") at the root is refused" \
        json_like.from_json ROOT_BAD "$ROOT_DOC"
done

t_run json_like.from_json ROOT_BAD '[1,2]'
t_equals "the refusal names what it found" "1" \
    "$( [[ "$T_RUN_STDERR" == *"an array at the root"* ]] && echo 1 || echo 0 )"
t_equals "and says how to carry it" "1" \
    "$( [[ "$T_RUN_STDERR" == *"Wrap it under a key"* ]] && echo 1 || echo 0 )"

# A refused document must leave no object behind. It used to create one,
# report success, and hand back something empty.
ROOT_OBJECTS_BEFORE=$(compgen -A variable | grep -c '^JL_DATA_')
json_like.from_json ROOT_BAD '[1,2]' 2> /dev/null
ROOT_OBJECTS_AFTER=$(compgen -A variable | grep -c '^JL_DATA_')
t_equals "a refused document creates no object" \
    "$ROOT_OBJECTS_BEFORE" "$ROOT_OBJECTS_AFTER"

# The empty key is refused everywhere, by both halves.
declare ROOT_EMPTY
t_fails "the reader refuses the empty key at the top" \
    json_like.from_json ROOT_EMPTY '{"":"x"}'
t_fails "and refuses it deeper down as well" \
    json_like.from_json ROOT_EMPTY '{"a":{"":"x"}}'

ROOT_OBJECTS_BEFORE=$(compgen -A variable | grep -c '^JL_DATA_')
json_like.from_json ROOT_EMPTY '{"":"x"}' 2> /dev/null
ROOT_OBJECTS_AFTER=$(compgen -A variable | grep -c '^JL_DATA_')
t_equals "that refusal leaks nothing either" \
    "$ROOT_OBJECTS_BEFORE" "$ROOT_OBJECTS_AFTER"

# The refusal has to name itself, so the reason is not guesswork.
t_run json_like.from_json ROOT_EMPTY '{"a":{"":"x"}}'
t_equals "the refusal says what it refused" "1" \
    "$( [[ "$T_RUN_STDERR" == *"empty key"* ]] && echo 1 || echo 0 )"

echo

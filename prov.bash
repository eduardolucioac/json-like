#!/bin/bash
#
# prov.bash - Demonstration: read a JSON file with "json_like.from_json".
#
#     ./prov.bash                  # uses the sample document below
#     ./prov.bash some-file.json   # or any object-rooted JSON file
#
# json-like - Nested data structures for BASH "inverted (c)" BSD-3-Clause
# Eduardo Lucio Amorim Costa
#

PROV_DIRECTORY="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" && pwd )"

# shellcheck source=./json-like.bash
source "$PROV_DIRECTORY/json-like.bash" || exit 1

# The file to read. Without an argument, a sample is written to a temporary
# one so that the demonstration really does go through a FILE.
JSON_FILE="$1"
SAMPLE_FILE=""
if [ -z "$JSON_FILE" ] ; then
    SAMPLE_FILE=$(mktemp "${TMPDIR:-/tmp}/json-like-prov.XXXXXX.json")
    cat > "$SAMPLE_FILE" << 'SAMPLE'
{
    "window": {
        "title": "MY SENSORS",
        "width": 563,
        "height": 440,
        "visible": true,
        "parent": null,
        "tags": ["kde", "plasma", "wayland"],
        "geometry": { "x": 1920, "y": 0 },
        "extras": {},
        "history": []
    },
    "version": "1.0"
}
SAMPLE
    JSON_FILE="$SAMPLE_FILE"
fi

trap '[ -n "$SAMPLE_FILE" ] && rm -f "$SAMPLE_FILE"' EXIT

if [ ! -r "$JSON_FILE" ] ; then
    echo "ERROR! Unable to read \"$JSON_FILE\"." >&2
    exit 1
fi

echo "=============================================================="
echo " 1. THE FILE ON DISK"
echo "=============================================================="
echo
cat "$JSON_FILE"
echo

echo "=============================================================="
echo " 2. READING IT"
echo "=============================================================="
echo
echo "    declare DOCUMENT"
echo "    json_like.from_json DOCUMENT < \"$JSON_FILE\""
echo

declare DOCUMENT
if ! json_like.from_json DOCUMENT < "$JSON_FILE" ; then
    echo
    echo " The document was refused, and nothing was created."
    exit 1
fi

echo "    -> it returned $? and left the object id in DOCUMENT:"
echo
echo "       $DOCUMENT"
echo

echo "=============================================================="
echo " 3. WHAT CAME IN, WRITTEN BACK OUT"
echo "=============================================================="
echo
echo "    declare DOCUMENT_AS_TEXT"
echo "    json_like.to_json DOCUMENT_AS_TEXT \"\$DOCUMENT\" 4"
echo "    echo \"\$DOCUMENT_AS_TEXT\""
echo

declare DOCUMENT_AS_TEXT
json_like.to_json DOCUMENT_AS_TEXT "$DOCUMENT" 4
echo "$DOCUMENT_AS_TEXT"
echo

echo "    json_like.to_json DOCUMENT_AS_TEXT \"\$DOCUMENT\"        (compact)"
echo

json_like.to_json DOCUMENT_AS_TEXT "$DOCUMENT"
echo "$DOCUMENT_AS_TEXT"
echo

echo "=============================================================="
echo " 4. THE TYPES SURVIVED THE TRIP"
echo "=============================================================="
echo
printf '   %-34s %s\n' "EXPRESSION" "RESULT"
printf '   %-34s %s\n' "----------------------------------" "------"

declare VALUE
json_like.get VALUE "$DOCUMENT" window title
printf '   %-34s %s\n' 'get ... window title' "$VALUE"

json_like.get VALUE "$DOCUMENT" window width
printf '   %-34s %s\n' 'get ... window width' "$VALUE"

json_like.get VALUE "$DOCUMENT" window tags 1
printf '   %-34s %s\n' 'get ... window tags 1' "$VALUE"

json_like.get VALUE "$DOCUMENT" window geometry x
printf '   %-34s %s\n' 'get ... window geometry x' "$VALUE"

declare HOW_MANY
json_like.get_length HOW_MANY "$DOCUMENT" window tags
printf '   %-34s %s\n' 'get_length ... window tags' "$HOW_MANY"

json_like.get_length HOW_MANY "$DOCUMENT" window history
printf '   %-34s %s\n' 'get_length ... window history' "$HOW_MANY"
echo

# The type a value was written with is kept, which is what lets the document
# go back out as JSON rather than as quoted text throughout.
declare KIND
printf '   %-34s %s\n' "PATH" "JSON TYPE"
printf '   %-34s %s\n' "----------------------------------" "---------"
for LOOP_PATH in window.title window.width window.visible window.parent \
            window.tags window.extras window.history ; do
    json_like._get_type KIND "$DOCUMENT" "$LOOP_PATH"
    case "$KIND" in
        0) KIND="object"  ;;
        1) KIND="array"   ;;
        3) KIND="string"  ;;
        4) KIND="number"  ;;
        5) KIND="boolean" ;;
        6) KIND="null"    ;;
        *) KIND="?"       ;;
    esac
    printf '   %-34s %s\n' "$LOOP_PATH" "$KIND"
done
echo

echo "=============================================================="
echo " 5. DONE"
echo "=============================================================="
echo
json_like.unset_obj DOCUMENT
echo " json_like.unset_obj DOCUMENT   -> DOCUMENT is now [$DOCUMENT]"
echo

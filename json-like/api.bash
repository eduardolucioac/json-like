#!/bin/bash
#
# json-like/api.bash - the public functions
#
# Part of "json-like". Sourced by "json-like.bash", never on its own: it
# relies on what the parts before it defined.
#
# json-like - Nested data structures for BASH "inverted (c)" BSD-3-Clause
# Eduardo Lucio Amorim Costa
#

# PUBLIC API >>>>>>

function json_like.set() {
    : 'Write a value at a path, creating the levels it needs.

    ARGUMENTS
        $1  - string, required. Object id.
        $2  - string, required. The value, TAGGED with its JSON type:
              "s.<string>", "n.<number>", "b.true"/"b.false" or "z.null".
              Pass "" when the path ends with an empty container.
        $3+ - string, at least one, required. The path, one item per level,
              each TAGGED with its kind: "o.<key>", "i.<index>" or, as the
              last item only, "e.{}" / "e.[]".

    RETURNS
        0 on success, 1 on any refusal, with a message on stderr. A refused
        "set" changes nothing: everything is validated first.

    SIDE EFFECTS
        Writes one row to the data array and records the type of every level
        it touched. An empty container writes no data row at all.

    An index equal to the current length of the array appends, and so does "i.+".
    Writing beyond that is refused, because arrays are kept dense.
    '

    # NOTE: Suffixes are used to prevent circular references with namerefs.

    local json_like_obj="$1"
    json_like._assert_obj "$json_like_obj" || return 1
    local -n jl_data_ref_86fc="JL_DATA_$json_like_obj"

    local like_json_value="$2"

    shift 2

    # An empty container is asked for with a trailing "e.{}" or "e.[]". It is not
    # a level of its own: it describes the container sitting at the path formed
    # by the items before it. Nothing goes into the data array for it, which is
    # what keeps it distinct from the literal strings "{}" and "[]".
    local empty_container_type=-1
    if (($# > 1)) ; then
        case "${!#}" in
            "e.{}") empty_container_type=0 ;;
            "e.[]") empty_container_type=1 ;;
        esac
    fi
    if ((empty_container_type != -1)) ; then
        if [ -n "$like_json_value" ] ; then
            echo "ERROR! An empty container takes no value. Pass \"\" as the value." >&2
            return 1
        fi
        set -- "${@:1:$#-1}"
    fi

    # The value carries its JSON type the same way a path item carries its kind,
    # and for the same reason: "8080" alone cannot say whether it is the number
    # 8080 or the string "8080", and guessing from the characters is what makes
    # a library emit `true` where the document said "true". The split is on the
    # FIRST dot, so everything after the tag is the value, literally.
    local value_tag=""
    local value_type=3
    if ((empty_container_type == -1)) ; then
        if [[ "$like_json_value" != *.* ]] ; then
            echo "ERROR! Untagged value \"$like_json_value\". A value must be \"s.<string>\", \"n.<number>\", \"b.<true|false>\" or \"z.null\"." >&2
            return 1
        fi

        value_tag="${like_json_value%%.*}"
        like_json_value="${like_json_value#*.}"

        case "$value_tag" in
            s)
                value_type=3
                ;;
            n)
                # The JSON number grammar, RFC 8259 section 6. Refusing here is
                # what keeps a serialiser from emitting a document that will not
                # parse.
                if [[ ! "$like_json_value" =~ ^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$ ]] ; then
                    echo "ERROR! \"$like_json_value\" is not a valid JSON number." >&2
                    return 1
                fi
                value_type=4
                ;;
            b)
                if [[ "$like_json_value" != "true" ]] && [[ "$like_json_value" != "false" ]] ; then
                    echo "ERROR! \"$like_json_value\" is not a boolean. Use \"b.true\" or \"b.false\"." >&2
                    return 1
                fi
                value_type=5
                ;;
            z)
                if [[ "$like_json_value" != "null" ]] ; then
                    echo "ERROR! The only null is \"z.null\"." >&2
                    return 1
                fi
                value_type=6
                ;;
            *)
                echo "ERROR! Unknown value tag \"$value_tag.\". Use \"s.\", \"n.\", \"b.\" or \"z.\"." >&2
                return 1
                ;;
        esac
    fi

    # See "json_like._resolve_path" for the layout of this array.
    local -a path_metadata_rtn=()

    json_like._resolve_path path_metadata_rtn "$json_like_obj" "set" "$@" || {
        return 1
    }

    # Validate BEFORE touching anything, so a rejected "set" leaves the object
    # exactly as it was.
    json_like._validate_set_path "$json_like_obj" path_metadata_rtn || {
        return 1
    }

    # Get the length of the array.
    local l="${#path_metadata_rtn[@]}"

    if ((empty_container_type != -1)) \
            && [[ -v jl_data_ref_86fc["${path_metadata_rtn[l-4]}"] ]] ; then
        # "_validate_set_path" cannot catch this one: it guards the levels that
        # lead to the value, and here the final level is the container itself.
        # Without this check the path would end up holding a value AND a type,
        # which is the very contradiction the rules exist to prevent.

        echo "ERROR! The path \"${path_metadata_rtn[l-4]}\" already holds a value. It cannot also be a container." >&2
        return 1
    fi

    # Chunk size.
    local c=6

    # Loop control variable.
    local i=0

    # Each chunk end index.
    local e=0

    # Loop through the array in chunks of 6.
    for ((i = 0; i < l; i += c)); do

        # Determine the end index for the current chunk.
        e=$((i + c - 1))

        # The data is only in the last chunk, and an empty container has none.
        if ((e == (l - 1))) && ((empty_container_type == -1)); then
            jl_data_ref_86fc["${path_metadata_rtn[i+2]}"]="$like_json_value"
        fi

        # Set type and/or length for each path level.
        if ((${path_metadata_rtn[i]} == 1)) ; then
            # "1" is indexable path item.

            json_like._set_type "$json_like_obj" "${path_metadata_rtn[i+3]}" 1
            if ((${path_metadata_rtn[i+4]} == ${path_metadata_rtn[i+5]})) ; then
                json_like._set_length "$json_like_obj" "${path_metadata_rtn[i+3]}" "$(( path_metadata_rtn[i+5] + 1 ))"
            fi

            if ((e != (l - 1))); then
                # The element holds an object, so record it as a container. This
                # is what lets a later "set" notice that the element cannot be
                # turned into a plain value.

                json_like._set_type "$json_like_obj" "${path_metadata_rtn[i+2]}" 0
            fi
        else
            # "${path_metadata_rtn[i]}" is "0" (not indexable path item).

            json_like._set_type "$json_like_obj" "${path_metadata_rtn[i+2]}" 0
        fi

    done

    if ((empty_container_type != -1)) ; then
        # The container exists only in the caches: a type entry, and a length of
        # zero when it is an array. A later "set" into it finds an empty array
        # rather than a missing one, so the first element lands at index 0.

        json_like._set_type "$json_like_obj" "${path_metadata_rtn[l-4]}" "$empty_container_type"
        if ((empty_container_type == 1)) ; then
            json_like._set_length "$json_like_obj" "${path_metadata_rtn[l-4]}" 0
        fi
    else
        # The leaf records which of the six JSON types it holds. The loop above
        # has already marked it, but only as "not an array"; this is what tells
        # the string "8080" apart from the number 8080 later on.

        json_like._set_type "$json_like_obj" "${path_metadata_rtn[l-4]}" "$value_type"
    fi

}

function json_like.get() {
    : 'Read from the object. The shape of the result follows the target.

    ARGUMENTS
        $1  - string, required. Where the result goes:
                a plain variable NAME .... the single value at the path
                "-" ...................... the value, printed to stdout with
                                           no trailing newline
                a NAME declared "-A" ..... the whole subtree under the path
        $2  - string, required. Object id.
        $3+ - string, optional. The path, one item per level, UNTAGGED: the
              key under an object, the index under an array. Omit it with an
              associative target to copy the entire object.

    RETURNS
        0 on success, 1 when the path does not exist or the target is an
        indexed array, with a message on stderr.

    The value comes back as text: the type tag it was written with is
    consumed on the way in, so "n.8080" reads back as "8080".

    The keys of a subtree read are relative to the PARENT of the requested
    path, and they stay escaped. Treat them as display material and come back
    through "json_like.get" when you need a value by path.
    '

    # NOTE: Suffixes are used to prevent circular references with namerefs.

    # 0 - Single value into a scalar variable.
    # 1 - Single value printed to stdout.
    # 2 - Subtree into an associative array.
    local get_mode=0
    if [[ "$1" == "-" ]] ; then
        get_mode=1
    else
        local target_name="$1"
        local target_attrs=""
        if ((_JSON_LIKE_HAS_ATTR_EXPANSION == 1)) ; then
            target_attrs="${!target_name@a}"
        else
            # BASH 4.3/4.4/5.0: no attribute expansion, so pay for the fork.
            target_attrs="$(declare -p "$target_name" 2>/dev/null)"
            target_attrs="${target_attrs#declare -}"
            target_attrs="${target_attrs%% *}"
        fi

        if [[ "$target_attrs" == *A* ]]; then
            # "$1" is an associative array, so a whole subtree is wanted.

            get_mode=2
        elif [[ "$target_attrs" == *a* ]]; then
            echo "ERROR! \"$target_name\" is an indexed array. Use a scalar variable for a single value, or an associative array (\"declare -A\") for a subtree." >&2
            return 1
        fi
        local -n value_rtn_b21f="$1"
    fi

    local json_like_obj="$2"
    json_like._assert_obj "$json_like_obj" || return 1
    local -n jl_data_ref_4b0c="JL_DATA_$json_like_obj"

    shift 2

    if (( "$#" == 0 )); then
        if (( get_mode == 2 )) ; then
            json_like._get_full_assoc_array value_rtn_b21f "$json_like_obj"
            return 0
        else
            echo "ERROR! An associative array is expected to be returned." >&2
            return 1
        fi
    fi

    # See "json_like._resolve_path" for the layout of this array.
    local -a path_metadata_rtn=()

    json_like._resolve_path path_metadata_rtn "$json_like_obj" "get" "$@" || {
        return 1
    }

    if (( get_mode == 2 )) ; then
        json_like._get_in_assoc_array value_rtn_b21f "$json_like_obj" path_metadata_rtn || {
            return 1
        }
    else
        # For "get_mode" 0 and 1.

        if [[ -v jl_data_ref_4b0c["${path_metadata_rtn[2]}"] ]]; then
            if (( get_mode == 0 )) ; then
                value_rtn_b21f="${jl_data_ref_4b0c["${path_metadata_rtn[2]}"]}"
            elif (( get_mode == 1 )) ; then
                echo -n "${jl_data_ref_4b0c["${path_metadata_rtn[2]}"]}"
            fi
        else
            echo "ERROR! Invalid path or index(es)." >&2
            return 1
        fi
    fi
}

function json_like.get_length() {
    : 'Read the element count of the array at a path.

    ARGUMENTS
        $1  - string, required. NAME of the variable to receive the count.
        $2  - string, required. Object id.
        $3+ - string, at least one, required. The path, UNTAGGED.

    RETURNS
        0 on success, 1 when the path is not an array, with a message on
        stderr. An EMPTY array is an array: it answers 0.
    '

    # NOTE: Suffixes are used to prevent circular references with namerefs.

    local length_var_name="$1"

    local json_like_obj="$2"
    json_like._assert_obj "$json_like_obj" || return 1

    shift 2

    # See "json_like._resolve_path" for the layout of this array.
    local -a path_metadata_rtn=()

    json_like._resolve_path path_metadata_rtn "$json_like_obj" "length" "$@" || {
        return 1
    }

    local path="${path_metadata_rtn[2]}"
    if [ -z "$path" ] ; then
        echo "ERROR! Invalid object path or index(es)." >&2
        return 1
    fi

    json_like._get_length_by_path "$length_var_name" "$json_like_obj" "$path"
}

function json_like.to_json() {
    : 'Write the object out as a JSON document.

    ARGUMENTS
        $1 - string, required. Where the result goes: the NAME of a variable
             to receive the document, or "-" to print it to stdout.
        $2 - string, required. Object id.
        $3 - integer, optional, default 0. Indentation width; 0 is compact,
             and a compact document carries no trailing newline.

    RETURNS
        0 on success, 1 when the indent is not a number or AWK fails, with a
        message on stderr.

    Each value comes out in the shape of the type it was written with, which
    is what the value tags are for: "n.563" is 563 and "s.563" is "563".
    Strings are escaped per RFC 8259 section 7, and empty containers come out
    as {} and [].

    Object keys come out in whatever order BASH holds them. RFC 8259 says the
    order of object members is not significant; sort downstream if a stable
    document matters.
    '

    # NOTE: Suffixes are used to prevent circular references with namerefs.

    local to_json_target_4e17="$1"

    local json_like_obj="$2"
    json_like._assert_obj "$json_like_obj" || return 1

    local indent="${3:-0}"
    if [[ ! "$indent" =~ ^[0-9]+$ ]] ; then
        echo "ERROR! The indent must be a non-negative integer." >&2
        return 1
    fi

    local data_declaration
    data_declaration=$(declare -p "JL_DATA_$json_like_obj")

    local type_declaration
    type_declaration=$(declare -p "JL_TYPE_CACHE_$json_like_obj")

    local stdout_stderr=""
    stdout_stderr=$(echo -n "to_json
$indent
$data_declaration
$type_declaration" | awk "$_JSON_LIKE_CODEC_AWK" 2>&1) || {
        echo "$stdout_stderr" >&2
        return 1
    }

    if [[ "$to_json_target_4e17" == "-" ]] ; then
        printf '%s' "$stdout_stderr"
        return 0
    fi

    local -n to_json_rtn_4e17="$to_json_target_4e17"
    to_json_rtn_4e17="$stdout_stderr"
}

function json_like.from_json() {
    : 'Read a JSON document into a new object.

    ARGUMENTS
        $1 - string, required. The NAME of a variable to receive the id of the
             new object, not its value.
        $2 - string, optional. The JSON text. When it is left out the document
             is read from stdin, so a file can be piped or redirected in.

    RETURNS
        0 on success, 1 when the document does not parse or its root is not an
        object, with the reason and the position on stderr. Nothing is created
        when it fails.

    SIDE EFFECTS
        On success, creates an object exactly as "json_like.set_obj" would and
        fills it in.

    Every value keeps the JSON type it was written with, and a number keeps the
    text it was written as, so "1E+10" goes back out as "1E+10".
    '

    local from_json_var_name_c93a="$1"
    local json_text_c93a=""

    if (($# >= 2)) ; then
        json_text_c93a="$2"
    else
        json_text_c93a=$(cat)
    fi

    # The parser runs under the C locale on purpose: it decodes "\uXXXX" by
    # emitting UTF-8 one BYTE at a time, and anywhere else "%c" would hand back
    # a character and encode what is already encoded.
    local parsed_c93a=""
    parsed_c93a=$(printf '%s\n%s' "from_json" "$json_text_c93a" \
        | LC_ALL=C awk "$_JSON_LIKE_FROM_JSON_AWK" 2>&1) || {
        echo "$parsed_c93a" >&2
        return 1
    }

    local new_obj_c93a=""
    json_like.set_obj new_obj_c93a || return 1

    {
        read -r data_block_c93a
        read -r type_block_c93a
        read -r length_block_c93a
    } <<< "$parsed_c93a"

    # The parser is what guards the document, so a failure here means the two
    # of them disagree about what is representable. Take the object back out
    # rather than hand back a half filled one with a success code.
    if ! eval "JL_DATA_$new_obj_c93a=$data_block_c93a" 2> /dev/null \
            || ! eval "JL_TYPE_CACHE_$new_obj_c93a=$type_block_c93a" 2> /dev/null \
            || ! eval "JL_LENGTH_CACHE_$new_obj_c93a=$length_block_c93a" 2> /dev/null ; then
        json_like.unset_obj new_obj_c93a
        echo "ERROR! The document parsed but could not be loaded." >&2
        return 1
    fi

    local -n from_json_rtn_c93a="$from_json_var_name_c93a"
    from_json_rtn_c93a="$new_obj_c93a"
}

function json_like.delete() {
    : 'Remove a path.

    ARGUMENTS
        $1  - string, required. Object id.
        $2+ - string, at least one, required. The path, UNTAGGED. Ending it
              with an index removes that one element; ending it with the name
              of an array removes the whole array.

    RETURNS
        0 on success, 1 when the path does not exist, with a message on
        stderr.

    SIDE EFFECTS
        Removes the data row and the cache entries. Removing an array element
        shifts the ones above it down, so the array stays dense.

    Deleting a LEAF never reaches AWK: only a value owns a row of its own, and
    a value cannot also hold items, so there is nothing to collect and nothing
    to renumber.
    '

    # NOTE: Suffixes are used to prevent circular references with namerefs.

    local json_like_obj="$1"
    json_like._assert_obj "$json_like_obj" || return 1

    shift 1

    # See "json_like._resolve_path" for the layout of this array.
    local -a path_metadata_rtn=()

    json_like._resolve_path path_metadata_rtn "$json_like_obj" "delete" "$@" || {
        return 1
    }

    local -n jl_data_ref_2f10="JL_DATA_$json_like_obj"

    if ((${path_metadata_rtn[0]} != 1)) && ((${path_metadata_rtn[1]} == 0)) \
            && [[ -v jl_data_ref_2f10["${path_metadata_rtn[2]}"] ]] ; then
        # A LEAF, and a leaf needs no AWK.
        #
        # Only a value has a row of its own in the data array: a container is
        # recorded in the caches and its children carry the rows. The library
        # refuses to let a value also hold items, so a path with a row is a leaf
        # with certainty -- nothing below it to collect, no sibling to renumber.
        #
        # The AWK passes exist to walk every key, which here would be three
        # processes rebuilding three arrays to drop two entries. Measured on an
        # object of a thousand keys, this path is about 39x faster.

        local -n jl_type_cache_ref_2f10="JL_TYPE_CACHE_$json_like_obj"

        unset "jl_data_ref_2f10[${path_metadata_rtn[2]}]"
        unset "jl_type_cache_ref_2f10[${path_metadata_rtn[2]}]"

        return 0
    fi

    if ((${path_metadata_rtn[0]} == 1)) && ((${path_metadata_rtn[1]} == 0)) ; then
        # Condition applicable to indexable item where index was passed.

        json_like._delete_path_array "$json_like_obj" path_metadata_rtn || {
            return 1
        }
    else
        # Condition applicable to an indexable item where the index was not provided
        # or to a non-indexable item. If the item is indexable then it will be removed
        # with all its items.

        json_like._delete_path "$json_like_obj" path_metadata_rtn || {
            return 1
        }
    fi
}

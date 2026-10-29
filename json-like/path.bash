#!/bin/bash
#
# json-like/path.bash - turning a path into the metadata every operation works from
#
# Part of "json-like". Sourced by "json-like.bash", never on its own: it
# relies on what the parts before it defined.
#
# json-like - Nested data structures for BASH "inverted (c)" BSD-3-Clause
# Eduardo Lucio Amorim Costa
#

# PATH RESOLUTION >>>>>>

function json_like._resolve_path_append_index() {
    : 'Resolve the "i.+" operator, the first free index of an array.

    ARGUMENTS
        $1 - string, required. NAME of an associative array to receive
             [index] and [length].
        $2 - string, required. Object id.
        $3 - string, required. Mode: only "set" may use "i.+".
        $4 - string, required. The path built from the items before this one,
             that is, the array itself.

    RETURNS
        0 on success, 1 when the mode is not "set" or the path is not an
        array, with a message on stderr.

    On an array that does not exist yet it resolves to 0, which is what makes
    a lone "i.+" create the array.
    '

    # NOTE: Suffixes are used to prevent circular references with namerefs.
    local -n length_index_rtn_8d9f="$1"

    local json_like_obj="$2"
    local mode="$3"
    local current_path="$4"

    if [[ "$mode" != "set" ]] ; then
        echo "ERROR! The \"+\" index is only valid for \"set\" operations." >&2
        return 1
    fi

    local type=0
    json_like._get_type type "$json_like_obj" "$current_path"
    if [[ ! " 1 2 " =~ " $type " ]] ; then
        echo "ERROR! Not indexable item." >&2
        return 1
    fi

    if ((type == 2)) ; then
        # The array does not exist yet, so "i.+" is its first index.

        length_index_rtn_8d9f[length]=0
        length_index_rtn_8d9f[index]=0
        return 0
    fi

    local current_length=0
    json_like._get_length_by_path current_length "$json_like_obj" "$current_path" || {
        return 1
    }
    length_index_rtn_8d9f[length]="$current_length"
    length_index_rtn_8d9f[index]="$current_length"
}

function json_like._resolve_path_negative_index() {
    : 'Resolve a negative index into a real one.

    ARGUMENTS
        $1 - string, required. NAME of an associative array to receive
             [index] and [length].
        $2 - string, required. Object id.
        $3 - string, required. The path of the array.
        $4 - integer, required. The negative index, "-1" being the last
             element.

    RETURNS
        0 on success, 1 when the path is not an array or the index falls
        before its first element, with a message on stderr.
    '

    # NOTE: Suffixes are used to prevent circular references with namerefs.
    local -n length_index_rtn_3f1c="$1"

    local json_like_obj="$2"
    local current_path="$3"
    local sign_negative_index="$4"

    local type=0
    json_like._get_type type "$json_like_obj" "$current_path"
    if ((type != 1)) ; then
        echo "ERROR! Not indexable item." >&2
        return 1
    fi

    local current_length=0
    json_like._get_length_by_path current_length "$json_like_obj" "$current_path" || {
        return 1
    }

    local resolved_index=$((current_length + sign_negative_index))
    if ((resolved_index < 0)) ; then
        echo "ERROR! Array index out of range." >&2
        return 1
    fi

    length_index_rtn_3f1c[length]="$current_length"
    length_index_rtn_3f1c[index]="$resolved_index"
}

function json_like._resolve_path_indexes() {
    : 'Validate a plain, non negative index against the array.

    ARGUMENTS
        $1 - string, required. NAME of an associative array to receive
             [length].
        $2 - string, required. Object id.
        $3 - string, required. Mode: "set", "get" or "delete".
        $4 - integer, required. The index.
        $5 - string, required. The path of the array.

    RETURNS
        0 on success, 1 when the path is not an array or the index would
        leave a hole, with a message on stderr.

    An index equal to the current length appends; anything beyond it is
    refused, because arrays are kept dense. "get" is not validated here on
    purpose: a wrong index simply finds nothing, and checking would cost a
    lookup on the hot path.
    '

    # NOTE: Suffixes are used to prevent circular references with namerefs.
    local -n numbers_rtn_4b77="$1"

    local json_like_obj="$2"
    local mode="$3"
    local path_item="$4"
    local current_path="$5"

    local type=0
    local current_length=0

    json_like._get_type type "$json_like_obj" "$current_path"
    if [[ ! " 1 2 " =~ " $type " ]] ; then
        echo "ERROR! Not indexable item." >&2
        return 1
    fi

    if [[ "$mode" == "set" ]] ; then
        if ((type == 2)) ; then
            # The array does not exist yet, so only index 0 can be written.

            if ((path_item > 0)) ; then
                echo "ERROR! Array index out of range." >&2
                return 1
            fi
            numbers_rtn_4b77[length]=0
        else
            # Condition applicable to "1".

            json_like._get_length_by_path current_length "$json_like_obj" "$current_path" || {
                return 1
            }

            # Writing exactly at "current_length" appends; anything beyond it
            # would leave a hole in the array.
            if ((path_item > current_length)) ; then
                echo "ERROR! Array index out of range." >&2
                return 1
            fi
            numbers_rtn_4b77[length]="$current_length"
        fi
    elif [[ "$mode" == "delete" ]] ; then
        if ((type != 1)) ; then
            echo "ERROR! Not indexable item." >&2
            return 1
        else
            # Condition applicable to "1".

            json_like._get_length_by_path current_length "$json_like_obj" "$current_path" || {
                return 1
            }
            if ((path_item >= current_length)) ; then
                echo "ERROR! Array index out of range." >&2
                return 1
            fi
            numbers_rtn_4b77[length]="$current_length"
        fi
    fi

    # NOTE: We do not apply validations to "get" because we prioritize performance.
    # The "validation" is done when retrieving the item itself, that is, if the
    # item is not found the path or index(es) are wrong.

}

function json_like._resolve_path_set_get_delete() {
    : 'Classifies ONE path item and resolves whatever wildcard it may carry.

        $1 - associative array to fill in (path_type, delete_array, path_item,
              current_length)
        $2 - object id
        $3 - mode ("set", "get" or "delete")
        $4 - the path item being classified
        $5 - the path built from the items before it
        $6 - how many path items are still pending
    '

    # NOTE: Suffixes are used to prevent circular references with namerefs.
    local -n resolve_path_sgd_rtn_b54f="$1"

    local json_like_obj="$2"

    local mode="$3"
    local path_item="$4"
    local current_path="$5"
    local remaining_path_items="$6"

    # Set/reset associative array.
    resolve_path_sgd_rtn_b54f[path_type]=0
    resolve_path_sgd_rtn_b54f[delete_array]=0
    resolve_path_sgd_rtn_b54f[path_item]=""
    resolve_path_sgd_rtn_b54f[current_length]=0

    local -A signs_rtn=( [index]=0 [length]=0 )
    local -A numbers_rtn=( [length]=0 )

    local parent_type=0
    local item_type=0
    local candidate_path=""

    # How an item is classified depends on the mode.
    #
    # "set" is the only mode that CREATES structure, so it is the only one that
    # could guess wrong about what a level should be. Its items are therefore
    # tagged "<type>.<item>": "i." an array index, "o." an object key taken
    # literally, "e." an empty container. The split is on the FIRST dot, so
    # everything after the tag is literal and every key a JSON document can
    # hold is reachable -- "o.0", "o.+", "o.i.x" and "o." are all just keys.
    #
    # The reading modes never create anything. They walk what is already there,
    # and the type cache records what every level is, so the parent decides:
    # under an array the item is an index, under an object it is the key
    # itself. Their items carry no tag.

    local item_kind=""
    local item_tag=""

    if [[ "$mode" == "set" ]] ; then
        if [[ "$path_item" != *.* ]] ; then
            echo "ERROR! Untagged path item \"$path_item\". A \"set\" path item must be \"i.<index>\", \"o.<key>\", \"e.{}\" or \"e.[]\"." >&2
            return 1
        fi

        item_tag="${path_item%%.*}"
        path_item="${path_item#*.}"

        case "$item_tag" in
            i) item_kind="index" ;;
            o) item_kind="key" ;;
            e)
                # "json_like.set" strips a trailing empty container before the
                # path is resolved, so reaching here means it was not last.
                echo "ERROR! \"e.$path_item\" is only valid as the LAST path item." >&2
                return 1
                ;;
            *)
                echo "ERROR! Unknown path item tag \"$item_tag.\". Use \"i.\", \"o.\" or \"e.\"." >&2
                return 1
                ;;
        esac
    else
        json_like._get_type parent_type "$json_like_obj" "$current_path"
        if ((parent_type == 1)) ; then
            item_kind="index"
        else
            item_kind="key"
        fi
    fi

    if [[ "$item_kind" == "index" ]] && [[ "$path_item" == "+" ]] ; then
        # The first free index of an array. Applicable to "set" only.

        json_like._resolve_path_append_index signs_rtn "$json_like_obj" "$mode" "$current_path" || {
            return 1
        }

        resolve_path_sgd_rtn_b54f[path_item]="${signs_rtn[index]}"
        resolve_path_sgd_rtn_b54f[current_length]="${signs_rtn[length]}"
        resolve_path_sgd_rtn_b54f[path_type]=1
    elif [[ "$item_kind" == "index" ]] && [[ "$path_item" =~ ^-[1-9][0-9]*$ ]] ; then
        # An inverted (negative) index, counted from the end of the array.

        json_like._resolve_path_negative_index signs_rtn "$json_like_obj" "$current_path" "$path_item" || {
            return 1
        }

        resolve_path_sgd_rtn_b54f[path_item]="${signs_rtn[index]}"
        resolve_path_sgd_rtn_b54f[current_length]="${signs_rtn[length]}"
        resolve_path_sgd_rtn_b54f[path_type]=1
    elif [[ "$item_kind" == "index" ]] && [[ "$path_item" =~ ^[0-9]+$ ]] ; then
        # The "path_item" is an index (natural number, that is, non-negative integer).
        # Condition applicable to "set", "get" or "delete" operations.

        json_like._resolve_path_indexes numbers_rtn "$json_like_obj" "$mode" "$path_item" "$current_path" || {
            return 1
        }

        resolve_path_sgd_rtn_b54f[path_item]="$path_item"
        resolve_path_sgd_rtn_b54f[current_length]="${numbers_rtn[length]}"
        resolve_path_sgd_rtn_b54f[path_type]=1
    elif [[ "$item_kind" == "index" ]] ; then
        # Tagged or resolved as an index, but not shaped like one.

        echo "ERROR! \"$path_item\" is not a valid array index." >&2
        return 1
    else
        # The "path_item" is an object key.

        # An array holds either values or objects, never named keys, so it can
        # only ever be addressed through an index. On the reading modes
        # "item_kind" already came from the parent type, so this only ever
        # fires for a "set" that tagged the item "o." under an array.
        json_like._get_type parent_type "$json_like_obj" "$current_path"
        if ((parent_type == 1)) ; then
            echo "ERROR! \"$current_path\" is an array and can only be addressed through an index." >&2
            return 1
        fi

        if [ -z "$path_item" ] ; then
            # The empty key is refused, deliberately and everywhere.
            #
            # JSON allows it, but it buys nothing here and costs clarity: at
            # the first level its flattened path would be the empty string,
            # which is how the root itself is spelled and which BASH will not
            # take as an array subscript. Allowing it deeper down and refusing
            # it at the top would be a positional exception, and a positional
            # exception is how confusing errors are made. One rule instead.

            echo "ERROR! The empty key is not accepted. See the limitations." >&2
            return 1
        fi

        # Escape the characters that carry structure in a flattened path, so a
        # key can hold any of them without being mistaken for one.
        #
        # The BACKSLASH goes first, and it has to: it is the escape character,
        # so leaving it alone makes the escaping lossy. A key ending in a
        # backslash, joined to a child, produced the same stored path as a
        # single key holding a dot -- {"a\\": {"b": 1}} and {"a.b": 1} both
        # became "a\\.b", and whichever was written second silently replaced
        # the first. Doubling it keeps the mapping one to one, and makes the
        # structural characters the ones preceded by an EVEN number of
        # backslashes.
        path_item="${path_item//\\/\\\\}"
        path_item="${path_item//./\\.}"
        path_item="${path_item//\[/\\[}"
        path_item="${path_item//\]/\\]}"

        resolve_path_sgd_rtn_b54f[path_item]="$path_item"

        if [[ "$mode" == "delete" ]] && ((remaining_path_items == 0)) ; then
            # This condition identifies the situation where a user wants to remove
            # an array completely and not just one item from it. In practical terms,
            # this means that the last item is indexable but the path provided
            # does not end with an index.
            #
            # NOTE: The type of THIS item has to be looked at, not the type of
            # its parent. The path keeps its dotted form ("a.arr", never
            # "a[arr]"); only "delete_array" is raised, so that the AWK pass
            # knows it has to match "a.arr[" as well.

            candidate_path="${current_path}${current_path:+.}$path_item"
            json_like._get_type item_type "$json_like_obj" "$candidate_path"
            if ((item_type == 1)) ; then
                resolve_path_sgd_rtn_b54f[delete_array]=1
            fi
        fi
    fi
}

function json_like._resolve_path() {
    : 'Walks a path item by item and builds the metadata the operations work from.

        $1 - indexed array to fill in, in chunks of 6 (see below)
        $2 - object id
        $3 - mode ("set", "get", "length" or "delete")
        $4+ . the path items

    Each chunk of 6 describes one level of the path:

        0 - path_type (0 object key | 1 array index)
        1 - delete_array (0/1)
        2 - path (full, escaped)
        3 - path_no_index (the array, when path_type is 1)
        4 - index (when path_type is 1)
        5 - length before the operation (when path_type is 1)

    NOTE: Only "set" needs metadata for every level, because it has to create
    each one. The other modes only get a chunk for the LAST level, which is all
    they act on.
    '

    # NOTE: Suffixes are used to prevent circular references with namerefs.
    local -n path_metadata_rtn_490c="$1"

    local json_like_obj="$2"
    local mode="$3"

    shift 3

    if (( $# < 1 )); then
        echo "ERROR! Invalid path." >&2
        return 1
    fi

    # "length" resolves a path exactly like "get" does; only the lookup at the
    # end differs.
    local resolve_mode="$mode"
    case "$mode" in
        set|get|delete)
            ;;
        length)
            resolve_mode="get"
            ;;
        *)
            echo "ERROR! Invalid mode." >&2
            return 1
            ;;
    esac

    local -a path_metadata_now=()

    local current_path=""

    # 0 - Object key (not indexable).
    # 1 - Array index (indexable).
    local path_type=0

    local delete_array=0
    local path_item=""
    local current_length=0
    local -A resolve_path_sgd_rtn
    while (( $# )); do
        path_item="$1"
        shift 1

        if [ -z "$path_item" ] && [[ "$mode" == "set" ]] ; then
            # On "set" the empty key is spelled "o."; a bare "" carries no tag
            # and would be rejected below anyway, but this says why. The reading
            # modes take their items literally, so there "" IS the empty key,
            # which JSON allows.
            echo "ERROR! Empty path item. On \"set\" the empty key is written \"o.\"." >&2
            return 1
        fi

        # INDEX - DESCRIPTION (TYPE)
        path_metadata_now=(
            0   # 0 - path_type (0/1)
            0   # 1 - delete_array (0/1)
            ""  # 2 - path (string)
            ""  # 3 - path_no_index (string)
            0   # 4 - index (natural number)
            0   # 5 - length (natural number)
        )

        resolve_path_sgd_rtn=(
            [path_type]=0
            [delete_array]=0
            [path_item]=""
            [current_length]=0
        )

        json_like._resolve_path_set_get_delete resolve_path_sgd_rtn "$json_like_obj" \
            "$resolve_mode" "$path_item" "$current_path" "$#" || {
            return 1
        }
        path_type="${resolve_path_sgd_rtn[path_type]}"
        delete_array="${resolve_path_sgd_rtn[delete_array]}"
        path_item="${resolve_path_sgd_rtn[path_item]}"
        current_length="${resolve_path_sgd_rtn[current_length]}"

        if ((path_type == 1)) ; then
            if (($# == 0)) || [[ "$mode" == "set" ]] ; then
                path_metadata_now[0]=1
                path_metadata_now[3]="$current_path"

                if [[ " set delete " =~ " $mode " ]] ; then
                    path_metadata_now[4]="$path_item"
                    path_metadata_now[5]="$current_length"

                    if [[ "$mode" == "set" ]] ; then

                        # Slice the array to exclude the last 6 items. The reason
                        # for this operation is because items in the path are
                        # processed one by one and to define the metadata of
                        # an indexable item it is necessary to analyze it and
                        # its predecessor. A path item will be considered indexable
                        # if its successor is an index (or a wildcard representing
                        # it).
                        path_metadata_rtn_490c=("${path_metadata_rtn_490c[@]:0:$((${#path_metadata_rtn_490c[@]} - 6))}")

                    fi
                fi
            fi
            current_path="$current_path[$path_item]"
        else
            # "path_type" is "0".

            if (($# == 0)) || [[ "$mode" == "set" ]] ; then
                path_metadata_now[0]=0
                path_metadata_now[1]="$delete_array"
            fi
            current_path="${current_path}${current_path:+.}$path_item"
        fi

        if (($# == 0)) || [[ "$mode" == "set" ]] ; then
            path_metadata_now[2]="$current_path"
            path_metadata_rtn_490c+=("${path_metadata_now[@]}")
            path_metadata_now=()
        fi
    done

}

function json_like._get_native_declaration() {
    : 'Render a path the way BASH renders it inside a declaration.

    ARGUMENTS
        $1 - string, required. NAME of the variable to receive the rendered
             declaration.
        $2 - string, required. Full, already escaped path.

    RETURNS
        0 always.

    AWK has to find the path inside a "declare -p" dump, and BASH applies its
    own quoting to associative array keys: "[with.dot]" stays bare while
    "[\"with space\"]" gets quoted. The only reliable way to know how a path
    LOOKS in a declaration is to let BASH print one.
    '

    # NOTE: Suffixes are used to prevent circular references with namerefs.
    local -n native_declaration_rtn_4f83="$1"

    local path="$2"

    local -A associative_array
    associative_array["$path"]=1
    native_declaration_rtn_4f83=$(declare -p associative_array)
}

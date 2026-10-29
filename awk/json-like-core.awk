#
# json-like.awk - AWK back end for the "json-like" BASH library.
#
# This program is NOT meant to be run by hand. It is loaded once by
# "json-like.bash" (into "$_JSON_LIKE_AWK") and fed through a pipe whenever an
# operation has to walk the whole internal associative array. BASH loops over
# associative arrays are slow, so every O(n) operation is delegated here.
#
# INPUT (via stdin, one value per line)
#
#     line 1 .... mode
#     line 2 .... native_declaration
#     line 3 .... key_ends          (object modes)   | key_index  (array modes)
#     line 4 .... assoc_array_decl  (object modes)   | key_length (array modes)
#     line 5 .... --                (object modes)   | assoc_array_decl
#
# "native_declaration" is a `declare -p` dump of a throwaway associative array
# holding the target path as its single key. It is needed because BASH applies
# its own quoting/escaping rules to associative array keys, and the only
# reliable way to know how a given path LOOKS inside a declaration is to let
# BASH print it.
#
# "assoc_array_decl" is a `declare -p` dump of the array being operated on.
# BASH always renders values either double quoted ("...") or ANSI-C quoted
# ($'...'), never bare, which is what makes the row splitting below possible:
# newlines and tabs inside values arrive escaped, so a declaration is always a
# single line.
#
# MODES
#
#     get ................. return the subset of rows under a path
#     delete_path ......... drop a path and every descendant
#     delete_path_array ... drop one array element and renumber the higher ones
#     unset_type .......... same as delete_path, for the type cache
#     unset_length ........ same as delete_path, for the length cache
#     unset_type_array .... same as delete_path_array, for the type cache
#     unset_length_array .. same as delete_path_array, for the length cache
#
# OUTPUT
#
#     stdout .. the rows that survived, ready for `eval "arr=( ... )"`
#     stderr + exit 1 .. when a match was required but nothing matched
#
# json-like - Nested data structures for BASH "inverted (c)" BSD-3-Clause
# Eduardo Lucio Amorim Costa
#

# Extracts the target path out of the single key "native_declaration" dump.
#
# BASH renders `declare -p` of a one key associative array as either
#
#     declare -A associative_array=([plain_key]="1" )
#     declare -A associative_array=(["key needing quotes"]="1" )
#
# so the path is whatever sits between the fixed prefix and the fixed suffix,
# minus the optional surrounding double quotes.
function get_key_path_from_declaration(native_declaration,
                                           decl_prefix,
                                           decl_suffix,
                                           key_path) {

    decl_prefix = "declare -A associative_array=(["
    decl_suffix = "]=\"1\" )"

    # NOTE: substr([string], [1-based index start], [substring length]) .
    # [Ref(s).: https://thomas-cokelaer.info/blog/2011/05/awk-the-substr-command-to-select-a-substring/ ]
    key_path = substr(native_declaration,
                      length(decl_prefix) + 1,
                      length(native_declaration) - length(decl_prefix) \
                          - length(decl_suffix))

    # Remove the first and last characters if the result is double quoted.
    if (substr(key_path, 1, 1) == "\"") {
        key_path = substr(key_path, 2, length(key_path) - 2)
    }

    return key_path
}

# Tells whether "mode" addresses a single array element (and therefore reads
# "key_index"/"key_length" from stdin) instead of a whole path.
function is_array_mode(mode) {
    return (mode == "delete_path_array" \
            || mode == "unset_type_array" \
            || mode == "unset_length_array")
}

# Tells whether "mode" must match at least one row to be considered successful.
#
# The cache maintenance modes ("unset_*") may legitimately match nothing: a
# leaf has no descendants, and an array element need not have any entry in the
# type/length caches. Reporting that as an error is what used to make every
# successful "delete" print a bogus message to stderr.
function mode_requires_match(mode) {
    # "delete_path_array" is NOT here on purpose. The BASH side validates the
    # index against the array length before calling, so by this point the index
    # is known to exist. Matching no row only means the elements carry no data
    # of their own, which is what an empty container is; the rows above it still
    # have to be renumbered, and demanding a match would throw that work away.

    return (mode == "get" \
            || mode == "delete_path")
}

# Computes the derived values every row comparison needs, once, before the main
# loop.
function prepare_operation(mode,
                           native_declaration,
                           key_index,
                           key_length,
                           rtn_array,
                               key_path,
                               path_beginning,
                               key_path_begin,
                               key_path_end_for_index,
                               adjust_subsequent) {

    # Every one of these is mode dependent, so initialise them all: reading an
    # uninitialised argument is harmless in AWK but makes "--lint" noisy and
    # hides the real warnings.
    path_beginning = ""
    key_path_begin = ""
    key_path_end_for_index = 0
    adjust_subsequent = 0

    key_path = get_key_path_from_declaration(native_declaration)

    if (mode == "get") {

        # Defines the beginning of the path since the obtained array is a subset.
        # Pattern Explanation `\.[^.]*$`:
        # `\.`: Matches a literal dot.
        # `[^.]*`: Matches any number of characters that are not dots.
        # `$`: Ensures the match occurs at the end of the string.
        # Overall, this pattern matches the last dot in the string and everything
        # that follows it.
        # Function "sub" Behavior:
        # The "sub" function replaces the first occurrence of the pattern in the string.
        # If the pattern is not found, "sub" returns 0, and the string remains unchanged.
        path_beginning = key_path
        if (! sub(/\.[^.]*$/, ".", path_beginning)) {
            path_beginning = ""
        }

    } else if (is_array_mode(mode)) {

        # Start of the path as expected on each key. An array element key always
        # contains a "[", so BASH always double quotes it.
        key_path_begin = "[\"" key_path "["

        # Where the "start of index path" should end in the target key string.
        key_path_end_for_index = length(key_path_begin) + 1

        # Check if there are any higher index keys that need to be adjusted.
        adjust_subsequent = 0
        if (key_length > (key_index + 1)) {
            adjust_subsequent = 1
        }

    }

    rtn_array[1] = key_path
    rtn_array[2] = path_beginning
    rtn_array[3] = key_path_begin
    rtn_array[4] = key_path_end_for_index
    rtn_array[5] = adjust_subsequent
}

# Decides whether "current_row" belongs to "key_path".
#
# A plain prefix test is not enough: the path "object.a" must not match the row
# of "object.ab". Every comparison therefore pins both a prefix and a suffix
# around the path, so only the path itself ("]"/"\"]") or one of its descendants
# ("." / "[") can match.
function path_match_rules(mode,
                          current_row,
                          key_ends,
                          key_path,
                              index_start,
                              index_end) {

    # # "[key_path]"
    # path_fixes[1] = "["; path_fixes[2] = "]"
    # # "[key_path."
    # path_fixes[3] = "["; path_fixes[4] = "."
    # # "[\"key_path["
    # path_fixes[5] = "[\""; path_fixes[6] = "["
    # # "[\"key_path\"]"
    # path_fixes[7] = "[\""; path_fixes[8] = "\"]"
    # # "[\"key_path."
    # path_fixes[9] = "[\""; path_fixes[10] = "."

    if (key_ends == 0) {
        # 0 - Ends without index.

        index_end = 4

        if (mode == "unset_type" || mode == "unset_length") {

            # Descendants only. The path itself was already removed by the
            # caller, so matching it here would be wasted work.
            path_fixes_now[1] = path_fixes[3]
            path_fixes_now[2] = path_fixes[4]
            path_fixes_now[3] = path_fixes[9]
            path_fixes_now[4] = path_fixes[10]
        } else {

            # With this approach we reduce the amount of comparisons and loops needed.
            if (substr(current_row, 1, 2) == "[\"") {
                path_fixes_now[1] = path_fixes[7]
                path_fixes_now[2] = path_fixes[8]
                path_fixes_now[3] = path_fixes[9]
                path_fixes_now[4] = path_fixes[10]
            } else {
                path_fixes_now[1] = path_fixes[1]
                path_fixes_now[2] = path_fixes[2]
                path_fixes_now[3] = path_fixes[3]
                path_fixes_now[4] = path_fixes[4]
            }

        }

    } else {
        # 1 - Ends with index.

        index_end = 2
        path_fixes_now[1] = path_fixes[5]
        path_fixes_now[2] = path_fixes[6]
    }

    # Iterate through the array two elements at a time.
    for (index_start = 1; index_start <= index_end; index_start += 2) {
        if (index(current_row, path_fixes_now[index_start] key_path path_fixes_now[index_start+1]) == 1) {
            return 1
        }
    }

    return 0
}

# "get": keeps the matching rows, rebased on the parent of the requested path.
function process_get_rows(current_row,
                          key_ends,
                          key_path,
                          valid_path_or_indexes,
                          path_beginning,
                          assoc_array_output,
                          rtn_array,
                              substring_pos) {

    if (path_match_rules("get", current_row, key_ends, key_path) == 1) {
        valid_path_or_indexes = 1
        if (path_beginning != "") {
            # Removes the beginning of the path since the obtained array
            # is a subset.

            # Find the position (first occurrence) of the substring. The row is
            # known to start with the path, so this always hits the key and
            # never the value.
            substring_pos = index(current_row, path_beginning)

            # Remove the substring.
            current_row = substr(current_row, 1, substring_pos - 1) \
                            substr(current_row, substring_pos + length(path_beginning))

            assoc_array_output = assoc_array_output current_row "\n"
        } else {
            assoc_array_output = assoc_array_output current_row "\n"
        }
    }

    rtn_array[1] = valid_path_or_indexes
    rtn_array[2] = assoc_array_output
}

# "delete_path_array" / "unset_type_array" / "unset_length_array": drops every
# row under "key_path[key_index]" and shifts the higher indexes down by one, so
# the array stays dense.
#
# The same walk serves the data array and both caches. Keeping them in sync
# matters: a stale type or length entry makes a later "get"/"set" address an
# element that no longer exists.
function process_array_rows(current_row,
                            key_path_begin,
                            key_index,
                            valid_path_or_indexes,
                            adjust_subsequent,
                            key_path_end_for_index,
                            assoc_array_output,
                            rtn_array,
                                delete_row,
                                row_substring,
                                substring_pos,
                                index_now,
                                right_part) {

    delete_row = 0
    if (index(current_row, key_path_begin key_index "]") == 1) {
        delete_row = 1
        valid_path_or_indexes = 1
    }

    if (delete_row == 0) {
        if (adjust_subsequent == 1 && index(current_row, key_path_begin) == 1) {
            # Check if string starts with prefix.

            # Checks if the path index needs to be adjusted and adjusts
            # it if so.

            # Remove the prefix by extracting the substring after it
            row_substring = substr(current_row, key_path_end_for_index)

            # Find the position of the first delimiter
            substring_pos = index(row_substring, "]")

            # Extract the left part (before the delimiter)
            index_now = substr(row_substring, 1, substring_pos - 1)

            # Convert to number explicitly.
            index_now += 0

            # Extract the right part (after the delimiter)
            right_part = substr(row_substring, substring_pos + 1)

            if (index_now > key_index) {
                index_now--
            }

            assoc_array_output = assoc_array_output key_path_begin index_now "]" right_part "\n"

        } else {
            assoc_array_output = assoc_array_output current_row "\n"
        }
    }

    rtn_array[1] = valid_path_or_indexes
    rtn_array[2] = assoc_array_output
}

# "delete_path" / "unset_type" / "unset_length": keeps every row that does NOT
# belong to "key_path".
function process_delete_path_unset_type_unset_length_rows(mode,
                                                          current_row,
                                                          key_ends,
                                                          key_path,
                                                          valid_path_or_indexes,
                                                          assoc_array_output,
                                                          rtn_array) {

    # The "key_path" value needs to start at the first position of the string for
    # the line to be ignored.
    if (path_match_rules(mode, current_row, key_ends, key_path) == 0) {
        assoc_array_output = assoc_array_output current_row "\n"
    } else {
        valid_path_or_indexes = 1
    }

    rtn_array[1] = valid_path_or_indexes
    rtn_array[2] = assoc_array_output
}

# Dispatches one row to the handler of the current mode.
function process_rows(mode,
                      current_row,
                      key_ends,
                      key_path,
                      valid_path_or_indexes,
                      path_beginning,
                      assoc_array_output,
                      key_path_begin,
                      key_index,
                      adjust_subsequent,
                      key_path_end_for_index,
                      rtn_array) {

    if (mode == "get") {

        # Since arrays are passed by reference, you can modify them inside
        # a function and access the results outside of it.

        # NOTE: When we pass global variables as arguments to functions,
        # they become local to the scope of the function, preventing undue
        # modifications of these values.

        process_get_rows(current_row,
                         key_ends,
                         key_path,
                         valid_path_or_indexes,
                         path_beginning,
                         assoc_array_output,
                         rtn_array)
    } else if (mode == "delete_path" || mode == "unset_type" || mode == "unset_length") {
        process_delete_path_unset_type_unset_length_rows(mode,
                                                         current_row,
                                                         key_ends,
                                                         key_path,
                                                         valid_path_or_indexes,
                                                         assoc_array_output,
                                                         rtn_array)
    } else if (is_array_mode(mode)) {
        process_array_rows(current_row,
                           key_path_begin,
                           key_index,
                           valid_path_or_indexes,
                           adjust_subsequent,
                           key_path_end_for_index,
                           assoc_array_output,
                           rtn_array)
    }

}

BEGIN {

    # DECLARE VARIABLES

    # The operating mode that will be used.
    mode = ""

    # This is necessary because BASH escapes the keys of associative arrays in the
    # declaration. So we need to follow the same rules to find the desired keys inside
    # the declaration of the target associative array.
    native_declaration = ""

    # Iteration type (0 - Ends without index; 1 - Ends with index).
    key_ends = 0

    # Associative array declaration string.
    assoc_array_decl = ""

    # Associative array declaration string length.
    assoc_array_decl_len = 0

    # Lines pattern to be removed/adjusted.
    key_path = ""

    # Character being processed.
    current_char = ""

    # Row being processed.
    current_row = ""

    # Flag to indicate if we're inside a quote.
    in_quote = 0

    # Stores the current quote character.
    quote_char = ""

    # Flag for escape character.
    in_escape = 0

    # Counter for row insertion.
    insert_row_ctrl = -1

    # Allows you to eliminate the string before the first "(", including it.
    after_open_parenthesis = 0

    # Flag to indicate if we're inside a key.
    in_key = 0

    # Flag to indicate if we're inside a quote inside a key.
    in_quote_key = 0

    # Stores the associative array output with each of its keys on a row.
    assoc_array_output = ""

    # At least one row must be deleted or got, for the modes that require it.
    valid_path_or_indexes = 0

    # Index to be removed (array modes only).
    key_index = 0

    # Length before the index is removed (array modes only).
    key_length = 0

    # Path outer part ("get" only).
    path_beginning = ""

    # Start of index path as expected on each key (array modes only).
    key_path_begin = ""

    # Where the "start of index path" should end in the target key string.
    key_path_end_for_index = 0

    # Check if there are any higher index keys that need to be adjusted.
    adjust_subsequent = 0

    # Get key path prefixes suffixes.
    # "[key_path]"
    path_fixes[1] = "["; path_fixes[2] = "]"
    # "[key_path."
    path_fixes[3] = "["; path_fixes[4] = "."
    # "[\"key_path["
    path_fixes[5] = "[\""; path_fixes[6] = "["
    # "[\"key_path\"]"
    path_fixes[7] = "[\""; path_fixes[8] = "\"]"
    # "[\"key_path."
    path_fixes[9] = "[\""; path_fixes[10] = "."

    # NOTE: FS is deliberately left alone. No field is ever referenced: every
    # read is "$0" and the declaration is walked with "substr", so splitting
    # records would be pure overhead. It also keeps this program portable,
    # since FS="" is a gawk only extension.

}

{

    # GET PARAMETERS FROM STDIN

    # We use the approaches in this conditional to avoid problems with escaped characters
    # when passing it via "-v".
    if (NR == 1) {
        # Mode of use.

        mode = $0
    } else if (NR == 2) {
        # This is necessary because BASH escapes the keys of associative arrays.

        native_declaration = $0
    } else if (is_array_mode(mode)) {
        if (NR == 3) {
            # Index to be removed.

            key_index = $0
        } else if (NR == 4) {
            # Length before the index is removed.

            key_length = $0
        } else if (NR == 5) {
            # Associative array declaration.

            assoc_array_decl = $0
        }
    } else {
        if (NR == 3) {
            # Iteration type (0 - Ends without index; 1 - Ends with index).

            key_ends = $0
        } else if (NR == 4) {
            # Associative array declaration.

            assoc_array_decl = $0
        }
    }

}

END {

    # VALIDATE THE REQUESTED MODE

    if (mode != "get" \
            && mode != "delete_path" \
            && mode != "unset_type" \
            && mode != "unset_length" \
            && ! is_array_mode(mode)) {
        printf "%s", "ERROR! Unknown \"json-like\" AWK mode \"" mode "\"." > "/dev/stderr"
        close("/dev/stderr")
        exit 1
    }

    # CONFIGURE ADDITIONAL PARAMETERS

    delete rtn_array
    prepare_operation(mode, native_declaration, key_index, key_length, rtn_array)
    key_path = rtn_array[1]
    path_beginning = rtn_array[2]
    key_path_begin = rtn_array[3]
    key_path_end_for_index = rtn_array[4]
    adjust_subsequent = rtn_array[5]

    assoc_array_decl_len = length(assoc_array_decl)

    # MAIN LOGICAL BLOCK

    # The loop condition is "i < assoc_array_decl_len" to exclude the last ")" character.
    for (i = 1; i < assoc_array_decl_len; i++) {
        current_char = substr(assoc_array_decl, i, 1)

        # Skip to exclude the first "(" character.
        if (after_open_parenthesis == 0) {
            if (current_char != "(") {
                continue
            } else {
                after_open_parenthesis = 1
                continue
            }
        }

        if (in_escape == 1) {
            current_row = current_row current_char
            in_escape = 0
            continue
        }

        # Handle escape sequences.
        if (current_char == "\\") {
            current_row = current_row current_char
            in_escape = 1
            continue
        }

        # Handle the keys.
        if (in_quote == 0) {
            if (in_quote_key == 0 && current_char == "[") {
                in_key = 1
                current_row = current_row current_char
                continue
            } else if (in_quote_key == 0 && current_char == "]") {
                in_key = 0
                current_row = current_row current_char
                continue
            } else if (in_key == 1) {
                if (current_char == "\"") {
                    in_quote_key = !in_quote_key
                }
                current_row = current_row current_char
                continue
            }
        }

        current_row = current_row current_char

        # Handle the start and end of quoted strings.
        if (in_quote == 1 && current_char == quote_char) {
            # Closing quote detected.

            in_quote = 0
            quote_char = ""

            # Will insert row after one more character.
            insert_row_ctrl = 1

        } else if (in_quote == 0 && (current_char == "\"" || current_char == "'")) {
            in_quote = 1
            quote_char = current_char
        }

        if (insert_row_ctrl == 0) {
            # Insert row.

            # PROCESS OPERATIONS

            delete rtn_array
            process_rows(mode,
                         current_row,
                         key_ends,
                         key_path,
                         valid_path_or_indexes,
                         path_beginning,
                         assoc_array_output,
                         key_path_begin,
                         key_index,
                         adjust_subsequent,
                         key_path_end_for_index,
                         rtn_array)
            valid_path_or_indexes = rtn_array[1]
            assoc_array_output = rtn_array[2]

            current_row = ""
        }

        if (insert_row_ctrl < 0) continue
        insert_row_ctrl--

    }

    # RETURN RESPONSE

    if (valid_path_or_indexes == 1 || ! mode_requires_match(mode)) {
        printf "%s", assoc_array_output
    } else {

        # Print to "stderr" and exit with 1 error code.
        printf "%s", "ERROR! Invalid object path or index(es)." > "/dev/stderr"
        close("/dev/stderr")
        exit 1

    }

}

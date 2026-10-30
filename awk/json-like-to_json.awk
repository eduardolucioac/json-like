# awk/json-like-to_json.awk - writes a "json-like" object as JSON text, for "json-like.bash".
#
# Kept apart from "json-like.awk" on purpose: that program is a surgical editor
# of flattened paths and is left alone. This one is a codec, and its two modes
# share nothing with it but the way BASH hands an associative array over.
#
#     MODE "to_json"
#
#     line 1 .... "to_json"
#     line 2 .... indent width, 0 for compact
#     line 3 .... "declare -p" of the data array
#     line 4 .... "declare -p" of the type cache
#
#     Writes the JSON document to stdout.
#
# json-like - Nested data structures for BASH "inverted (c)" BSD-3-Clause
# Eduardo Lucio Amorim Costa
#

# Decode one value as BASH rendered it in a declaration.
#
#     ARGUMENTS
#         raw .. string, required. Either "..." or $'...', with the quotes.
#
#     LOCALS
#         out, i, n, c, nxt, ansi
#
#     RETURNS
#         The text it denotes.
#
# BASH never writes a value bare, so one of the two forms always applies. The
# ANSI-C form carries the control characters as escapes, which is what keeps a
# whole declaration on one line however many newlines a value holds.
function decode_value(raw,    out, i, n, c, nxt, ansi) {
    n = length(raw)
    if (n == 0) return ""

    ansi = 0
    if (substr(raw, 1, 2) == "$'") {
        ansi = 1
        raw = substr(raw, 3, n - 3)
    } else if (substr(raw, 1, 1) == "\"") {
        raw = substr(raw, 2, n - 2)
    }

    out = ""
    n = length(raw)
    for (i = 1; i <= n; i++) {
        c = substr(raw, i, 1)
        if (c != "\\") { out = out c; continue }

        nxt = substr(raw, i + 1, 1)
        i++
        if (ansi) {
            if (nxt == "n") out = out "\n"
            else if (nxt == "t") out = out "\t"
            else if (nxt == "r") out = out "\r"
            else if (nxt == "a") out = out sprintf("%c", 7)
            else if (nxt == "b") out = out sprintf("%c", 8)
            else if (nxt == "f") out = out sprintf("%c", 12)
            else if (nxt == "v") out = out sprintf("%c", 11)
            else if (nxt == "E") out = out sprintf("%c", 27)
            else out = out nxt            # \\ and \' land here
        } else {
            out = out nxt                 # \" \\ \$ \` land here
        }
    }
    return out
}

# Walk a "declare -p" dump and split it into keys and values.
#
#     ARGUMENTS
#         decl .. string, required. The dump.
#         keys .. array, required. Filled in, 1 based.
#         vals .. array, required. Filled in, 1 based, parallel to "keys".
#
#     LOCALS
#         i, n, c, depth, start, row, eq, rawkey, rawval, count
#
#     RETURNS
#         How many pairs were found.
#
# The dump is always a single line: BASH renders a newline inside a value as
# the two characters \n. A key is either bare or, when BASH decided it needed
# quoting, a double quoted string -- and a quoted one can contain "]", which is
# exactly what an array path looks like, so it has to be consumed as a string
# rather than scanned for its closing bracket.
function parse_declaration(decl, keys, vals,
                           i, n, c, depth, start, row, eq, rawkey, rawval, count) {
    count = 0
    n = length(decl)

    # Everything before the first "=(" is the "declare -A NAME" preamble.
    i = index(decl, "=(")
    if (i == 0) return 0
    i += 2

    while (i <= n) {
        c = substr(decl, i, 1)
        if (c == " ") { i++; continue }
        if (c == ")") break
        if (c != "[") { i++; continue }

        # The key is either bare or, when BASH decided it needed quoting, a
        # double quoted string. A bare key cannot contain "]"; a quoted one
        # can, which is exactly what an array path looks like, so the quoted
        # form has to be consumed as a string rather than scanned for "]".
        rawkey = ""
        i++
        if (substr(decl, i, 1) == "\"") {
            rawkey = "\""
            i++
            while (i <= n) {
                if (substr(decl, i, 1) == "\\") { rawkey = rawkey substr(decl, i, 2); i += 2; continue }
                if (substr(decl, i, 1) == "\"") break
                rawkey = rawkey substr(decl, i, 1)
                i++
            }
            rawkey = rawkey "\""
            i++
        } else {
            while (i <= n) {
                c = substr(decl, i, 1)
                if (c == "\\") { rawkey = rawkey substr(decl, i, 2); i += 2; continue }
                if (c == "]") break
                rawkey = rawkey c
                i++
            }
        }
        i++                                  # past "]"
        if (substr(decl, i, 1) != "=") continue
        i++

        # The value is quoted, and the quote it opens with is the one that ends
        # it. A backslash protects the next character.
        rawval = ""
        c = substr(decl, i, 1)
        if (c == "$") { rawval = "$"; i++; c = substr(decl, i, 1) }
        if (c == "\"" || c == "'") {
            rawval = rawval c
            i++
            while (i <= n) {
                if (substr(decl, i, 1) == "\\") { rawval = rawval substr(decl, i, 2); i += 2; continue }
                if (substr(decl, i, 1) == c) break
                rawval = rawval substr(decl, i, 1)
                i++
            }
            rawval = rawval c
            i++
        }

        count++
        keys[count] = unescape_declaration_key(rawkey)
        vals[count] = decode_value(rawval)
    }
    return count
}

# Take off the quoting BASH added around a key.
#
#     ARGUMENTS
#         raw .. string, required. The key as it appeared in the dump.
#
#     LOCALS
#         out, i, n, c
#
#     RETURNS
#         The key, still carrying the flattened-path escaping.
#
# Two layers of escaping meet here and only the outer one comes off. The inner
# one is undone later, by "unescape_path_key", and only for the last component
# of a path.
function unescape_declaration_key(raw,    out, i, n, c) {
    n = length(raw)
    if (n >= 2 && substr(raw, 1, 1) == "\"" && substr(raw, n, 1) == "\"") {
        raw = substr(raw, 2, n - 2)
        n = length(raw)
    }
    out = ""
    for (i = 1; i <= n; i++) {
        c = substr(raw, i, 1)
        if (c == "\\") { i++; out = out substr(raw, i, 1); continue }
        out = out c
    }
    return out
}

# Say whether the character at a position carries structure.
#
#     ARGUMENTS
#         path .. string, required. A flattened path.
#         pos ... integer, required. 1 based.
#
#     LOCALS
#         k, slashes
#
#     RETURNS
#         1 when the character is preceded by an EVEN number of backslashes,
#         0 otherwise.
#
# Exact, because the escaping doubles a backslash: a "." that came from a key
# always carries an odd count, and a separator always carries an even one.
function is_structural(path, pos,    k, slashes) {
    slashes = 0
    for (k = pos - 1; k >= 1 && substr(path, k, 1) == "\\"; k--) slashes++
    return (slashes % 2) == 0
}

# Split a flattened path into its parent and its last component.
#
#     ARGUMENTS
#         path .. string, required.
#
#     RETURNS
#         Nothing.
#
#     SIDE EFFECTS
#         Sets SPLIT_PARENT, SPLIT_ITEM and SPLIT_IS_INDEX.
#
# Three shapes have to be told apart: a path ending in an index, one ending in
# a key below another key, and one ending in a key below an array element.
function split_path(path,    i, n, c) {
    n = length(path)
    SPLIT_PARENT = ""; SPLIT_ITEM = path; SPLIT_IS_INDEX = 0

    if (n > 0 && substr(path, n, 1) == "]" && is_structural(path, n)) {
        for (i = n - 1; i >= 1; i--) {
            if (substr(path, i, 1) == "[" && is_structural(path, i)) {
                SPLIT_PARENT = substr(path, 1, i - 1)
                SPLIT_ITEM = substr(path, i + 1, n - i - 1)
                SPLIT_IS_INDEX = 1
                return
            }
        }
    }

    for (i = n; i >= 1; i--) {
        c = substr(path, i, 1)
        if (c == "." && is_structural(path, i)) {
            SPLIT_PARENT = substr(path, 1, i - 1)
            SPLIT_ITEM = substr(path, i + 1)
            return
        }
        if (c == "]" && is_structural(path, i)) {
            # The parent ends in an index, so this component starts after it.
            SPLIT_PARENT = substr(path, 1, i)
            SPLIT_ITEM = substr(path, i + 2)
            return
        }
    }
}

# Undo the flattened-path escaping of one key.
#
#     ARGUMENTS
#         key .. string, required. One component, already split off.
#
#     LOCALS
#         out, i, n, c
#
#     RETURNS
#         The key as the document spelled it.
function unescape_path_key(key,    out, i, n, c) {
    out = ""; n = length(key)
    for (i = 1; i <= n; i++) {
        c = substr(key, i, 1)
        if (c == "\\") { i++; out = out substr(key, i, 1); continue }
        out = out c
    }
    return out
}

# Escape a string for JSON output, and quote it.
#
#     ARGUMENTS
#         s .. string, required.
#
#     LOCALS
#         out, i, n, c, o
#
#     RETURNS
#         The string, escaped and wrapped in double quotes.
#
# Per RFC 8259 section 7: the quote and the backslash always, the three common
# control characters as their short forms, and everything else below space as
# "\u00XX".
function json_escape(s,    out, i, n, c, o) {
    out = ""; n = length(s)
    for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        if (c == "\"") { out = out "\\\""; continue }
        if (c == "\\") { out = out "\\\\"; continue }
        if (c == "\n") { out = out "\\n"; continue }
        if (c == "\t") { out = out "\\t"; continue }
        if (c == "\r") { out = out "\\r"; continue }
        o = index(CONTROL_CHARS, c)
        if (o > 0) { out = out sprintf("\\u%04x", o - 1); continue }
        out = out c
    }
    return "\"" out "\""
}

# Build the indentation for one nesting level.
#
#     ARGUMENTS
#         level .. integer, required.
#
#     LOCALS
#         s, i
#
#     RETURNS
#         The spaces, or "" when the document is compact.
function pad(level,    s, i) {
    if (INDENT == 0) return ""
    s = ""
    for (i = 0; i < level * INDENT; i++) s = s " "
    return s
}

# Give the line break a nesting level ends with.
#
#     RETURNS
#         A newline, or "" when the document is compact.
function nl() { return INDENT == 0 ? "" : "\n" }

# Render the node at a path, and everything under it.
#
#     ARGUMENTS
#         path ... string, required. "" is the root.
#         level .. integer, required. Used for indentation only.
#
#     LOCALS
#         t, i, out, n, child, sep
#
#     RETURNS
#         The JSON text for that node.
#
# Recursive. A value comes out in the shape of the type it was written with,
# which is what the value tags bought: a number bare, a string quoted. A
# container with no children comes out as {} or [], which is how an empty one
# is carried.
function emit(path, level,    t, i, out, n, child, sep) {
    t = TYPE[path]

    if (t == 3) return json_escape(DATA[path])
    if (t == 4 || t == 5 || t == 6) return DATA[path]

    n = CHILD_COUNT[path] + 0

    if (t == 1) {
        if (n == 0) return "[]"
        out = "[" nl()
        for (i = 0; i < n; i++) {
            child = (path == "" ? "" : path) "[" i "]"
            out = out pad(level + 1) emit(child, level + 1)
            if (i < n - 1) out = out ","
            out = out nl()
        }
        return out pad(level) "]"
    }

    if (n == 0) return "{}"
    out = "{" nl()
    for (i = 1; i <= n; i++) {
        child = CHILD[path, i]
        out = out pad(level + 1) json_escape(unescape_path_key(CHILD_KEY[path, i])) ":"
        if (INDENT > 0) out = out " "
        out = out emit(child, level + 1)
        if (i < n) out = out ","
        out = out nl()
    }
    return out pad(level) "}"
}

BEGIN {
    CONTROL_CHARS = ""
    for (i = 0; i < 32; i++) CONTROL_CHARS = CONTROL_CHARS sprintf("%c", i)
    MODE = ""; INDENT = 0; DATA_DECL = ""; TYPE_DECL = ""
}

{
    if (NR == 1) MODE = $0
    else if (NR == 2) INDENT = $0 + 0
    else if (NR == 3) DATA_DECL = $0
    else if (NR == 4) TYPE_DECL = $0
}

END {
    if (MODE != "to_json") {
        printf "%s", "ERROR! Unknown \"json-like\" codec mode \"" MODE "\"." > "/dev/stderr"
        close("/dev/stderr")
        exit 1
    }

    dn = parse_declaration(DATA_DECL, dkeys, dvals)
    for (i = 1; i <= dn; i++) DATA[dkeys[i]] = dvals[i]

    tn = parse_declaration(TYPE_DECL, tkeys, tvals)
    for (i = 1; i <= tn; i++) TYPE[tkeys[i]] = tvals[i] + 0

    # Register every node under its parent. Object children keep insertion
    # order as BASH happened to hand them over; array children are addressed by
    # their index, so their order is their own.
    for (p in TYPE) {
        split_path(p)
        if (SPLIT_IS_INDEX) {
            CHILD_COUNT[SPLIT_PARENT] = (CHILD_COUNT[SPLIT_PARENT] + 0) + 1
        } else {
            k = (CHILD_COUNT[SPLIT_PARENT] + 0) + 1
            CHILD_COUNT[SPLIT_PARENT] = k
            CHILD[SPLIT_PARENT, k] = p
            CHILD_KEY[SPLIT_PARENT, k] = SPLIT_ITEM
        }
    }

    TYPE[""] = 0
    printf "%s", emit("", 0)
    if (INDENT > 0) printf "\n"
}

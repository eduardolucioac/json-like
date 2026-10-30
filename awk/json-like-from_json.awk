#
# awk/json-like-from_json.awk - reads JSON text into a "json-like" object.
#
# Not meant to be run by hand. It is loaded once by "json-like.bash" and fed
# through a pipe by "json_like.from_json".
#
# INPUT (stdin)
#
#     line 1 .... "from_json"
#     line 2+ ... the JSON document, which may span any number of lines
#
# OUTPUT
#
#     stdout ........... three lines, each the body of a BASH associative
#                        array assignment: the data, the type cache, the
#                        length cache, in that order. The caller evaluates
#                        them into the arrays of a fresh object.
#     stderr + exit 1 .. when the document does not parse, with the reason and
#                        the position it stopped at.
#
# NOTES
#
#     Every string is emitted ANSI-C quoted, so each of the three output lines
#     is a single line whatever the document contained.
#
#     This program MUST be run under LC_ALL=C. It decodes \uXXXX into UTF-8 by
#     emitting the bytes one at a time, and outside the C locale "%c" produces
#     a CHARACTER rather than a byte, which would re-encode what is already
#     encoded.
#
# json-like - Nested data structures for BASH "inverted (c)" BSD-3-Clause
# Eduardo Lucio Amorim Costa
#

# Stop with a message that says where in the document it stopped.
#
#     ARGUMENTS
#         msg .. string, required. What was wrong, in lower case: it is read as
#                the middle of a sentence.
#
#     RETURNS
#         Never. Writes to stderr and exits 1.
#
# The position matters more than the wording. A document that fails to parse is
# usually long, and "at position 190" is the difference between a fix and a
# hunt.
function err(msg) {
    printf "%s", "ERROR! " msg " at position " POS "." > "/dev/stderr"
    close("/dev/stderr")
    exit 1
}

# Read one character of the document.
#
#     ARGUMENTS
#         n .. integer, required. 1 based position.
#
#     RETURNS
#         The character, or "" past the end.
function at(n) { return substr(DOC, n, 1) }

# Advance POS past any JSON whitespace.
#
#     LOCALS
#         c
#
#     RETURNS
#         Nothing.
#
#     SIDE EFFECTS
#         Moves POS.
#
# RFC 8259 section 2 allows space, tab, line feed and carriage return between
# any two tokens, and nothing else.
function skip_ws(    c) {
    while (POS <= DOCLEN) {
        c = at(POS)
        if (c == " " || c == "\t" || c == "\n" || c == "\r") POS++
        else break
    }
}

# Consume one required character, or stop.
#
#     ARGUMENTS
#         c .. string, required. The single character that must be there.
#
#     RETURNS
#         Nothing.
#
#     SIDE EFFECTS
#         Moves POS past it, or exits through "err".
function expect(c) {
    if (at(POS) != c) err("expected \"" c "\" but found \"" at(POS) "\"")
    POS++
}

# Turn one code point into its UTF-8 bytes.
#
#     ARGUMENTS
#         cp .. integer, required. The code point.
#
#     LOCALS
#         o
#
#     RETURNS
#         The bytes, as a string.
#
# Written out rather than left to "%c" with a large value, which depends on the
# locale: outside LC_ALL=C, "%c" hands back a CHARACTER and encodes what is
# already encoded. This is why the whole program is run under the C locale.
function utf8(cp,    o) {
    if (cp < 0x80) return sprintf("%c", cp)
    if (cp < 0x800)
        return sprintf("%c%c", 0xC0 + int(cp / 64), 0x80 + (cp % 64))
    if (cp < 0x10000)
        return sprintf("%c%c%c", 0xE0 + int(cp / 4096), \
                                 0x80 + (int(cp / 64) % 64), \
                                 0x80 + (cp % 64))
    return sprintf("%c%c%c%c", 0xF0 + int(cp / 262144), \
                               0x80 + (int(cp / 4096) % 64), \
                               0x80 + (int(cp / 64) % 64), \
                               0x80 + (cp % 64))
}

# Read exactly four hexadecimal digits.
#
#     LOCALS
#         i, c, v, n
#
#     RETURNS
#         Their value.
#
#     SIDE EFFECTS
#         Moves POS past them, or exits through "err" if any of the four is not
#         a hexadecimal digit.
function hex4(    i, c, v, n) {
    n = 0
    for (i = 0; i < 4; i++) {
        c = at(POS); POS++
        v = index("0123456789abcdef", tolower(c)) - 1
        if (v < 0) err("\"\\u\" needs four hexadecimal digits")
        n = n * 16 + v
    }
    return n
}

# Read a JSON string, from its opening quote to its closing one.
#
#     LOCALS
#         out, c, cp, lo
#
#     RETURNS
#         The text it denotes, decoded.
#
#     SIDE EFFECTS
#         Moves POS past the closing quote.
#
# Every escape the grammar allows is handled, "\uXXXX" included. A high
# surrogate must be followed by a low one, and a lone surrogate of either kind
# is refused: the pair denotes a single code point above the basic plane, and
# half of it denotes nothing. A raw control character inside a string is
# refused too, which RFC 8259 section 7 requires.
function parse_string(    out, c, cp, lo) {
    expect("\"")
    out = ""
    while (1) {
        if (POS > DOCLEN) err("unterminated string")
        c = at(POS)
        if (c == "\"") { POS++; return out }
        if (c != "\\") {
            # A raw control character is not allowed inside a JSON string.
            if (c < " " && c != "") err("a control character must be escaped inside a string")
            out = out c; POS++; continue
        }

        POS++
        c = at(POS); POS++
        if (c == "\"") out = out "\""
        else if (c == "\\") out = out "\\"
        else if (c == "/")  out = out "/"
        else if (c == "b")  out = out sprintf("%c", 8)
        else if (c == "f")  out = out sprintf("%c", 12)
        else if (c == "n")  out = out "\n"
        else if (c == "r")  out = out "\r"
        else if (c == "t")  out = out "\t"
        else if (c == "u") {
            cp = hex4()
            if (cp >= 0xD800 && cp <= 0xDBFF) {
                # A high surrogate: the low one has to follow, and the pair
                # together denotes one code point above the basic plane.
                if (at(POS) != "\\" || at(POS + 1) != "u") err("a high surrogate must be followed by a low one")
                POS += 2
                lo = hex4()
                if (lo < 0xDC00 || lo > 0xDFFF) err("invalid low surrogate")
                cp = 0x10000 + (cp - 0xD800) * 1024 + (lo - 0xDC00)
            } else if (cp >= 0xDC00 && cp <= 0xDFFF) {
                err("a low surrogate cannot stand on its own")
            }
            out = out utf8(cp)
        }
        else err("unknown escape \"\\" c "\"")
    }
}

# Read a JSON number.
#
#     LOCALS
#         start, c, seen
#
#     RETURNS
#         The TEXT that was written, not its value.
#
#     SIDE EFFECTS
#         Moves POS past it.
#
# Returning the text is deliberate: it goes back out exactly as it came in, so
# "1E+10" stays "1E+10" rather than becoming whatever a float would print. The
# grammar is the one in RFC 8259 section 6, which is why a leading zero is
# refused.
function parse_number(    start, c, seen) {
    start = POS
    if (at(POS) == "-") POS++
    if (at(POS) == "0") POS++
    else {
        seen = 0
        while (at(POS) >= "0" && at(POS) <= "9" && POS <= DOCLEN) { POS++; seen++ }
        if (seen == 0) err("a number needs at least one digit")
    }
    if (at(POS) == ".") {
        POS++
        seen = 0
        while (at(POS) >= "0" && at(POS) <= "9" && POS <= DOCLEN) { POS++; seen++ }
        if (seen == 0) err("a fraction needs at least one digit")
    }
    c = at(POS)
    if (c == "e" || c == "E") {
        POS++
        c = at(POS)
        if (c == "+" || c == "-") POS++
        seen = 0
        while (at(POS) >= "0" && at(POS) <= "9" && POS <= DOCLEN) { POS++; seen++ }
        if (seen == 0) err("an exponent needs at least one digit")
    }
    return substr(DOC, start, POS - start)
}

# Consume one of the three literal names, or stop.
#
#     ARGUMENTS
#         word .. string, required. "true", "false" or "null".
#
#     RETURNS
#         Nothing.
#
#     SIDE EFFECTS
#         Moves POS past it, or exits through "err".
function literal(word) {
    if (substr(DOC, POS, length(word)) != word) err("unexpected input")
    POS += length(word)
}

# Escape a key for a flattened path.
#
#     ARGUMENTS
#         k .. string, required. The key, as the document spells it.
#
#     LOCALS
#         out, i, c
#
#     RETURNS
#         The escaped key.
#
# The same escaping "json-like/path.bash" applies. The backslash goes FIRST,
# and it has to: it is the escape character, so leaving it alone would make the
# mapping lossy -- a key ending in one, joined to a child, would produce the
# same path as a single key holding a dot.
function esc_key(k,    out, i, c) {
    out = ""
    for (i = 1; i <= length(k); i++) {
        c = substr(k, i, 1)
        if (c == "\\" || c == "." || c == "[" || c == "]") out = out "\\"
        out = out c
    }
    return out
}

# Quote a string the ANSI-C way, so BASH can read it back.
#
#     ARGUMENTS
#         s .. string, required.
#
#     LOCALS
#         out, i, c, n
#
#     RETURNS
#         The string as "$'...'".
#
# Whatever the document held has to survive the trip back through BASH on a
# SINGLE line, because the three output blocks are read one line at a time. A
# newline inside a value would otherwise split a block in two.
function bq(s,    out, i, c, n) {
    out = ""
    for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c == "\\") { out = out "\\\\"; continue }
        if (c == "'")  { out = out "\\'";  continue }
        if (c == "\n") { out = out "\\n";  continue }
        if (c == "\t") { out = out "\\t";  continue }
        if (c == "\r") { out = out "\\r";  continue }
        n = index(CTRL, c)
        if (n > 0) { out = out sprintf("\\x%02x", n - 1); continue }
        out = out c
    }
    return "$'" out "'"
}

# Record one leaf: its value, and which JSON type it is.
#
#     ARGUMENTS
#         path .. string, required. The flattened path.
#         value . string, required. The value, decoded.
#         type .. integer, required. 3 string, 4 number, 5 boolean, 6 null.
#
#     RETURNS
#         Nothing.
#
#     SIDE EFFECTS
#         Appends to DATA_OUT and TYPE_OUT.
function put_data(path, value, type) {
    DATA_OUT = DATA_OUT "[" bq(path) "]=" bq(value) " "
    TYPE_OUT = TYPE_OUT "[" bq(path) "]=\"" type "\" "
}

# Record one container.
#
#     ARGUMENTS
#         path .. string, required. The flattened path.
#         type .. integer, required. 0 object, 1 array.
#
#     RETURNS
#         Nothing.
#
#     SIDE EFFECTS
#         Appends to TYPE_OUT, unless the path is the root, which is implicit
#         and has no row of its own.
#
# A container owns no data row: it exists in the type cache, and its children
# carry the values. That is also what makes an EMPTY container representable.
function put_node(path, type) {
    if (path == "") return            # the root is implicit
    TYPE_OUT = TYPE_OUT "[" bq(path) "]=\"" type "\" "
}

# Read any JSON value, dispatching on its first character.
#
#     ARGUMENTS
#         path .. string, required. Where this value sits. "" is the root.
#         depth . integer, required. Guards against runaway nesting.
#
#     LOCALS
#         c, s
#
#     RETURNS
#         Nothing.
#
#     SIDE EFFECTS
#         Moves POS, and records whatever it read.
function parse_value(path, depth,    c, s) {
    if (depth > 200) err("nesting is too deep")
    skip_ws()
    c = at(POS)

    if (c == "{") { parse_object(path, depth); return }
    if (c == "[") { parse_array(path, depth); return }
    if (c == "\"") { s = parse_string(); put_data(path, s, 3); return }
    if (c == "-" || (c >= "0" && c <= "9")) { s = parse_number(); put_data(path, s, 4); return }
    if (c == "t") { literal("true");  put_data(path, "true", 5);  return }
    if (c == "f") { literal("false"); put_data(path, "false", 5); return }
    if (c == "n") { literal("null");  put_data(path, "null", 6);  return }
    err("unexpected character \"" c "\"")
}

# Read an object, and every member of it.
#
#     ARGUMENTS
#         path .. string, required. Where the object sits.
#         depth . integer, required.
#
#     LOCALS
#         key, child, n
#
#     RETURNS
#         Nothing.
#
#     SIDE EFFECTS
#         Moves POS, and records the object and its descendants.
#
# The empty key is refused here. It is valid JSON, but at the first level its
# flattened path would be the empty string -- which is how the root itself is
# spelled -- and holding it deeper while refusing it at the top would be a
# positional exception. One rule instead.
function parse_object(path, depth,    key, child, n) {
    expect("{")
    put_node(path, 0)
    n = 0
    skip_ws()
    if (at(POS) == "}") { POS++; return }
    while (1) {
        skip_ws()
        key = parse_string()
        skip_ws()
        expect(":")
        if (key == "") err("the empty key is not accepted")
        child = (path == "" ? "" : path ".") esc_key(key)
        parse_value(child, depth + 1)
        n++
        skip_ws()
        if (at(POS) == ",") { POS++; continue }
        if (at(POS) == "}") { POS++; return }
        err("expected \",\" or \"}\"")
    }
}

# Read an array, and every element of it.
#
#     ARGUMENTS
#         path .. string, required. Where the array sits.
#         depth . integer, required.
#
#     LOCALS
#         child, n
#
#     RETURNS
#         Nothing.
#
#     SIDE EFFECTS
#         Moves POS, records the array and its descendants, and writes the
#         element count to LEN_OUT.
#
# An empty array still gets its length, zero, so that a later append lands at
# index 0 rather than finding nothing there.
function parse_array(path, depth,    child, n) {
    expect("[")
    put_node(path, 1)
    n = 0
    skip_ws()
    if (at(POS) == "]") {
        POS++
        LEN_OUT = LEN_OUT "[" bq(path) "]=\"0\" "
        return
    }
    while (1) {
        child = path "[" n "]"
        parse_value(child, depth + 1)
        n++
        skip_ws()
        if (at(POS) == ",") { POS++; continue }
        if (at(POS) == "]") {
            POS++
            LEN_OUT = LEN_OUT "[" bq(path) "]=\"" n "\" "
            return
        }
        err("expected \",\" or \"]\"")
    }
}

BEGIN {
    CTRL = ""
    for (i = 0; i < 32; i++) CTRL = CTRL sprintf("%c", i)
    MODE = ""; DOC = ""; FIRST = 1
}

{
    if (FIRST) { MODE = $0; FIRST = 0 }
    else DOC = (DOC == "" ? $0 : DOC "\n" $0)
}

END {
    if (MODE != "from_json") {
        printf "%s", "ERROR! Unknown \"json-like\" codec mode \"" MODE "\"." > "/dev/stderr"
        close("/dev/stderr")
        exit 1
    }

    DOCLEN = length(DOC)
    POS = 1
    DATA_OUT = ""; TYPE_OUT = ""; LEN_OUT = ""

    skip_ws()
    if (at(POS) != "{") {
        # RFC 8259 allows any value as a JSON text, but this model has no room
        # for one: the root is where keys hang from. An array at the root is
        # the case that actually occurs, so the message says how to carry it.
        found = "a value"
        if (at(POS) == "[") found = "an array"
        else if (at(POS) == "\"") found = "a string"
        else if (at(POS) == "t" || at(POS) == "f") found = "a boolean"
        else if (at(POS) == "n") found = "null"
        else if (at(POS) == "-" || (at(POS) >= "0" && at(POS) <= "9")) found = "a number"

        printf "%s", "ERROR! The root of a \"json-like\" object is always an object, and this document has " \
                     found " at the root. Wrap it under a key to carry it." > "/dev/stderr"
        close("/dev/stderr")
        exit 1
    }

    parse_value("", 0)

    skip_ws()
    if (POS <= DOCLEN) err("trailing content after the document")

    printf "(%s)\n", DATA_OUT
    printf "(%s)\n", TYPE_OUT
    printf "(%s)\n", LEN_OUT
}

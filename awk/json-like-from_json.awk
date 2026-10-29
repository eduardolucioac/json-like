# awk/json-like-from_json.awk - reads JSON text into a "json-like" object.
#
#     INPUT, on stdin
#
#     line 1 .... "from_json"
#     line 2+ ... the JSON document, which may span any number of lines
#
#     OUTPUT, on stdout
#
#     Three lines, each the body of a BASH associative array assignment, in
#     this order: the data, the type cache, the length cache. The caller
#     evaluates them into the arrays of a fresh object.
#
#     Every string is emitted ANSI-C quoted, so each of the three is a single
#     line no matter what the document contained.
#
# This program MUST be run under LC_ALL=C. It decodes \uXXXX into UTF-8 by
# emitting the bytes one at a time, and outside the C locale "%c" produces a
# CHARACTER rather than a byte, which would re-encode what is already encoded.
#
# json-like - Nested data structures for BASH "inverted (c)" BSD-3-Clause
# Eduardo Lucio Amorim Costa
#

function err(msg) {
    printf "%s", "ERROR! " msg " at position " POS "." > "/dev/stderr"
    close("/dev/stderr")
    exit 1
}

function at(n) { return substr(DOC, n, 1) }

function skip_ws(    c) {
    while (POS <= DOCLEN) {
        c = at(POS)
        if (c == " " || c == "\t" || c == "\n" || c == "\r") POS++
        else break
    }
}

function expect(c) {
    if (at(POS) != c) err("expected \"" c "\" but found \"" at(POS) "\"")
    POS++
}

# One code point into its UTF-8 bytes. Written out rather than left to "%c"
# with a large value, which depends on the locale.
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

# A JSON string, from its opening quote to its closing one. Returns the text
# it denotes, decoded.
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

# A JSON number, returned as the text that was written, so that it goes back
# out exactly as it came in.
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

function literal(word) {
    if (substr(DOC, POS, length(word)) != word) err("unexpected input")
    POS += length(word)
}

# The flattened-path escaping, the same one "json-like/path.bash" applies.
# The backslash goes first: it is the escape character, so leaving it alone
# would make the mapping lossy.
function esc_key(k,    out, i, c) {
    out = ""
    for (i = 1; i <= length(k); i++) {
        c = substr(k, i, 1)
        if (c == "\\" || c == "." || c == "[" || c == "]") out = out "\\"
        out = out c
    }
    return out
}

# ANSI-C quoting, so that whatever the document held survives the trip back
# through BASH on a single line.
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

function put_data(path, value, type) {
    DATA_OUT = DATA_OUT "[" bq(path) "]=" bq(value) " "
    TYPE_OUT = TYPE_OUT "[" bq(path) "]=\"" type "\" "
}

function put_node(path, type) {
    if (path == "") return            # the root is implicit
    TYPE_OUT = TYPE_OUT "[" bq(path) "]=\"" type "\" "
}

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

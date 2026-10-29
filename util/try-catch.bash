#!/bin/bash
#
# util/try-catch.bash - A "try/catch" idiom for BASH, built on process substitution.
#
# This is a CONSUMER convenience, not a dependency of "json-like.bash". The
# library itself only writes diagnostics to stderr and returns a non zero exit
# status; this module is for callers that want to capture those diagnostics and
# route them through a handler instead of letting them reach the terminal.
#
# USAGE
#
#     source "./try-catch.bash"
#
#     prog_concepts.try handler
#     some_command_that_may_fail 2> >($handler)
#     prog_concepts.catch "$handler" 0 "$?"
#
# The third argument of "catch" must be captured straight after the guarded
# command, because "$?" is clobbered by anything that runs in between.
#
# CLEAN UP
#
# Each "try" names a temporary file that is only created if the guarded command
# actually writes to stderr, and "catch" removes it after reading it. A file is
# left behind when a "try" is never followed by a "catch", so a script that uses
# this module should call "prog_concepts.cleanup" from its own EXIT trap:
#
#     trap 'prog_concepts.cleanup' EXIT
#
# This module deliberately does NOT install a trap of its own: BASH keeps a
# single handler per signal, so doing that would silently discard the trap of
# the script that sourced it.
#
# json-like - Nested data structures for BASH "inverted (c)" BSD-3-Clause
# Eduardo Lucio Amorim Costa
#

if ((BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 3))); then
    echo "ERROR! \"try-catch.bash\" requires BASH version 4.3 or higher." >&2
    return 1 2>/dev/null || exit 1
fi

function prog_concepts_default_catch_handler() {
    : 'Default handler used by "catch" when the error message is routed through a
    user supplied function instead of stderr.
    '
    echo "$1"
}

_PROG_CONCEPTS_DEFAULT_CATCH_HANDLER=""

function prog_concepts.set_default_catch_handler() {
    : 'Registers the function that "catch" should hand error messages to.

    Pass an empty string to go back to writing the messages to stderr verbatim.
    '
    _PROG_CONCEPTS_DEFAULT_CATCH_HANDLER="$1"
}

# Temporary files created by the stderr handlers, used as a clean up list.
declare -A _PROG_CONCEPTS_STDERR_FILES

function prog_concepts.cleanup() {
    : 'Removes every temporary stderr file still pending.

    Call this from the EXIT trap of the script that sources this module.
    '

    local prog_concepts_stderr_file
    for prog_concepts_stderr_file in "${!_PROG_CONCEPTS_STDERR_FILES[@]}"; do
        rm -f "$prog_concepts_stderr_file"
        unset "_PROG_CONCEPTS_STDERR_FILES[$prog_concepts_stderr_file]"
    done
}

function prog_concepts._handle_stderr_file() {
    : 'Writes the captured stderr to a file, or plays a captured file back.

    Allows the creation of a file with "stderr" output conditionally. That is,
    the file is only created if there is "stderr" output for it.
    '

    local stderr_file="$1"

    local print_stderr="$2"
    if [ -z "$print_stderr" ] ; then
        print_stderr=0
    fi

    if (( print_stderr > 0)); then
        # To deal with the hypothesis that the application returns an error code,
        # but does not print output (not generate a file) to stderr, we use
        # ` 2> /dev/null` for cat.

        if (( print_stderr > 1)); then
            # The user defined a default catch handler.

            cat "$stderr_file" 2> /dev/null
        else

            # The "echo" was used to add a line break.
            # { ...; } groups the commands together.
            # Redirect error messages to stderr using ">&2".
            # shellcheck disable=SC2005
            { cat "$stderr_file" 2> /dev/null && echo; } >&2

        fi
        rm -f "$stderr_file"
        unset "_PROG_CONCEPTS_STDERR_FILES[$stderr_file]"
    else
        local stderr_op

        # Captures the contents of stdin (caught from stderr) via process substitution.
        stderr_op=$(cat)

        if [ -n "$stderr_op" ] ; then
            echo -n "$stderr_op" > "$stderr_file"
            _PROG_CONCEPTS_STDERR_FILES["$stderr_file"]=1
        fi
    fi
}

function prog_concepts.try() {
    : 'Opens a guarded block by building the stderr handler command in "$1".

    NOTE: "mktemp -u" only reserves a NAME. The file is created later, and only
    if the guarded command really does write to stderr, which keeps a run of
    successful "try" blocks from littering the temporary directory.
    '
    local -n handler_ref_89ab="$1"
    # shellcheck disable=SC2034
    handler_ref_89ab="  prog_concepts._handle_stderr_file $(mktemp -u "${TMPDIR:-/tmp}/bash-try-catch.XXXXXX")"
}

function prog_concepts.catch() {
    : 'Closes a guarded block, reporting the error of the guarded command if any.

        $1 - the handler built by "try"
        $2 - 1 to exit the script on error, 0 to just return 1 (default 0)
        $3 - the exit status of the guarded command (defaults to "$?", which is
              only reliable when "catch" runs immediately after it)
    '
    local rtn_code_env="$?"
    local handler="$1"
    local exit_on_error="$2"
    local rtn_code="$3"
    if [ -z "$rtn_code" ] ; then
        rtn_code="$rtn_code_env"
    fi
    if [ -z "$exit_on_error" ] ; then
        exit_on_error=0
    fi
    if ((rtn_code > 0)) ; then

        if declare -f "$_PROG_CONCEPTS_DEFAULT_CATCH_HANDLER" > /dev/null; then

            $_PROG_CONCEPTS_DEFAULT_CATCH_HANDLER "$($handler 2)"

            if ((exit_on_error == 1)) ; then
                exit 1
            fi

            return 1
        else

            $handler 1
            if ((exit_on_error == 1)) ; then
                exit 1
            fi
            return 1

        fi

    fi
}

prog_concepts.set_default_catch_handler "prog_concepts_default_catch_handler"

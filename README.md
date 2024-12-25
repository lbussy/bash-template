<!-- omit in toc -->
# Script Documentation: Bash Template Script

<!-- omit in toc -->
## Table of Contents
- [Overview](#overview)
- [Key Features](#key-features)
- [Usage](#usage)
- [Documentation Style](#documentation-style)
- [Debugging](#debugging)
  - [Debugging Example](#debugging-example)
- [Exemplar Functions](#exemplar-functions)
  - [One (optional) Arg](#one-optional-arg)
  - [Three (plus One) Args](#three-plus-one-args)
  - [Multiple Arguments](#multiple-arguments)

## Overview

This script serves as a comprehensive Bash template, designed for advanced functionality, robust error handling, and detailed logging. It includes features such as:

- Stack tracing for debugging
- System validation
- Dynamic logging and configuration

## Key Features

1. **Robust Framework**:
    - Handles various failure scenarios.
    - Detailed system checks and validation.

2. **Logging**:
    - Supports dynamic log levels.
    - Provides extensive logging details.

3. **Error Handling**:
    - Uses stack traces for debugging.
    - Graceful handling of common Bash pitfalls.

4. **Modular Design**:
    - Includes reusable functions for extensibility.
    - Designed for easy integration with other scripts.

## Usage

To use this template:

1. Customize the placeholders with your script-specific logic.
2. Follow the provided function and variable documentation style.

## Documentation Style

This script adheres to Doxygen-style documentation:

```bash
# -----------------------------------------------------------------------------
# @brief Brief description of the function's purpose.
# @details Detailed explanation, including context and operation.
#
# @param $1 Description of the first parameter.
# @param $2 Description of the second parameter.
# ...
#
# @global GLOBAL_VAR_NAME Description of global variable usage.
# ...
#
# @throws Description of errors the function may produce.
#
# @return Description of the return value or behavior.
#
# @example
# Example usage of the function with expected output or behavior.
# -----------------------------------------------------------------------------
```

## Debugging
Debugging can be enabled by passing a `debug` flag to functions. When enabled, debug messages are printed to `stderr` to avoid conflicting with functions intended to return text or numbers to the calling script.

### Debugging Example
```bash
local debug="${1:-}"  # Optional debug flag
[[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$FUNCNAME" "$caller_name" "$caller_line"
```

## Exemplar Functions

These functions serve as an example of how you can build upon the script.

### One (optional) Arg

This shows how a function can receive an optional "debug" argument to trigger debug printing:

``` bash
one_arg() {
    # Debug setup
    local debug="${1:-}"  # Optional debug flag, defaults to an empty string if not provided
    local func_name="${FUNCNAME[0]}"
    local caller_name="${FUNCNAME[1]}"
    local caller_line="${BASH_LINENO[0]}"
    # Print debug information if the flag is set
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$func_name" "$caller_name" "$caller_line" >&2

    # Do stuff

    # Debug log: function exit
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Exiting function '%s()'.\n" "$func_name" >&2
}
```

### Three (plus One) Args

This exmaple has up to three arguments, plus the optional debug argument:

``` bash
optional_args() {
    # Initialize variables
    local severity="$1"   # Level is always passed as the first argument to log_message_with_severity
    local message=""
    local extended_message=""
    local debug=""
    local func_name="${FUNCNAME[1]}"
    local caller_name="${FUNCNAME[2]}"
    local caller_line="${BASH_LINENO[1]}"

    # Process arguments
    if [[ -n "$2" ]]; then
        if [[ "$2" == "debug" ]]; then
            echo "[ERROR]: Empty message. The first argument cannot be 'debug'." >&2
            exit 1
        else
            message="$2"
        fi
    else
        echo "[ERROR]: Message is required." >&2
        exit 1
    fi

    if [[ -n "$3" ]]; then
        if [[ "$3" == "debug" ]]; then
            debug="debug"
        else
            extended_message="$3"
        fi
    fi

    if [[ -n "$4" && "$4" == "debug" ]]; then
        debug="debug"
    fi

    # Print debug information if the flag is set
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$func_name" "$caller_name" "$caller_line" >&2

    # Log the primary message
    log_message "$severity" "$message" "$debug"

    # Do stuff

    # Debug log: function exit
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Exiting function '%s()'.\n" "$func_name" >&2
}

```

### Multiple Arguments

When you don;t know how many you will have (such as parsing command-line args, check them all:

``` bash
many_args() {
    local func_name="${FUNCNAME[0]}"
    local caller_name="${FUNCNAME[1]}"
    local caller_line="${BASH_LINENO[0]}"
    # Check for the "debug" argument anywhere
    for arg in "$@"; do
        if [[ "$arg" == "debug" ]]; then
            debug="debug"
            shift
            break
        fi
    done
    debug="${debug:-}"
    # Print debug information if the flag is set
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$func_name" "$caller_name" "$caller_line" >&2

    # Process the filtered arguments
    for arg in "$@"; do
        case "$arg" in
            --help|-h|-?)
                usage "$debug"
                exit 0
                ;;
            *)
                printf "Unknown option: %s\n" "${filtered_args[0]}"
                usage "$debug"
                exit 1
                ;;
        esac
        filtered_args=("${filtered_args[@]:1}") # Shift the processed argument
    done

    # Debug log: function exit
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Exiting function '%s()'.\n" "$func_name" >&2
}
```

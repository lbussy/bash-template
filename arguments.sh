#!/usr/bin/env bash
set -uo pipefail
IFS=$'\n\t'
set +o noclobber

start_debug() {
    # Find "debug" in arguments
    local debug=""
    local args=()  # Array to hold non-debug arguments
    for arg in "$@"; do
        if [[ "$arg" == "debug" ]]; then
            debug="debug"
        else
            args+=("$arg")  # Add non-debug arguments to the array
        fi
    done
    # Restore positional parameters
    set -- "${args[@]}"

    # Handle empty or unset FUNCNAME and BASH_LINENO gracefully
    local func_name="${FUNCNAME[1]:-script_body}"
    local caller_name="${FUNCNAME[2]:-script_body}"
    local caller_line=${BASH_LINENO[1]:-0}
    # Determine if we are piped
    local is_piped=false
    if [[ "$0" == "bash" ]]; then
        is_piped=true
    fi

    # Special processing for calling from bash/body/piped
    if [[ $is_piped == "true" && $func_name == "script_body" ]];then
        caller_name="bash"
        local caller_line=${BASH_LINENO[0]:-0}
    elif [[ $is_piped == "true" && $func_name == "main" ]];then
        caller_name="script_body"
    elif [[ $func_name == "main" && $caller_name == "script_body" ]]; then
        func_name="script_body"
        caller_name="bash"
        caller_line=${BASH_LINENO[0]:-0}
    elif [[ $func_name == "main" && $caller_name == "main" ]]; then
        func_name="main"
        caller_name="script_body"
        caller_line=${BASH_LINENO[1]:-0}
    fi

    # Print debug information if the flag is set
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Starting function '%s()' called by '%s()' at line %s in '%s'.\n" \
        "$func_name" "$caller_name" "$caller_line" "$THIS_SCRIPT" >&2

    # Return debug flag if present
    printf "%s\n" "${debug:-}"
}

print_debug() {
    # Find "debug" in arguments
    local debug=""
    local args=()  # Array to hold non-debug arguments
    for arg in "$@"; do
        if [[ "$arg" == "debug" ]]; then
            debug="debug"
        else
            args+=("$arg")  # Add non-debug arguments to the array
        fi
    done
    # Restore positional parameters
    set -- "${args[@]}"

    # Handle empty or unset FUNCNAME and BASH_LINENO gracefully
    local func_name="${FUNCNAME[1]:-script_body}"
    local caller_name="${FUNCNAME[2]:-script_body}"
    local caller_line=${BASH_LINENO[0]:-0}
    # Determine if we are piped
    local is_piped=false
    if [[ "$0" == "bash" ]]; then
        is_piped=true
    fi

    # Special processing for calling from bash/body/piped
    if [[ $is_piped == "true" && $func_name == "script_body" ]];then
        caller_name="bash"
        local caller_line=${BASH_LINENO[0]:-0}
    elif [[ $is_piped == "true" && $func_name == "main" ]];then
        caller_name="script_body"
    elif [[ $func_name == "main" && $caller_name == "script_body" ]]; then
        func_name="script_body"
    elif [[ $func_name == "main" && $caller_name == "main" ]]; then
        func_name="main"
    fi

    # Assign the remaining argument to the message
    local message="${1:-<unset>}"  # Debug message, defaults to <unset>
    message=$(remove_period "$message")

    # Print debug information if the flag is set
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Message: '%s' called by '%s()' at line %s in '%s'.\n" \
        "$message" "$func_name" "$caller_line" "$THIS_SCRIPT" >&2
}

end_debug() {
    # Find "debug" in arguments
    local debug=""
    local args=()  # Array to hold non-debug arguments
    for arg in "$@"; do
        if [[ "$arg" == "debug" ]]; then
            debug="debug"
        else
            args+=("$arg")  # Add non-debug arguments to the array
        fi
    done
    # Restore positional parameters
    set -- "${args[@]}"

    # Handle empty or unset FUNCNAME and BASH_LINENO gracefully
    local func_name="${FUNCNAME[1]:-script_body}"
    local caller_name="${FUNCNAME[2]:-script_body}"
    local caller_line=${BASH_LINENO[0]:-0}
    # Determine if we are piped
    local is_piped=false
    if [[ "$0" == "bash" ]]; then
        is_piped=true
    fi

    # Special processing for calling from bash/body/piped
    if [[ $is_piped == "true" && $func_name == "script_body" ]];then
        caller_name="bash"
        local caller_line=${BASH_LINENO[0]:-0}
    elif [[ $is_piped == "true" && $func_name == "main" ]];then
        caller_name="script_body"
    elif [[ $func_name == "main" && $caller_name == "main" ]]; then
        func_name="main"
    elif [[ $func_name == "main" && $caller_name == "script_body" ]]; then
        func_name="script_body"
    fi

    [[ "$debug" == "debug" ]] && printf "[DEBUG] Ending function '%s()' at line number %d in '%s'.\n" \
        "$func_name" "$caller_line" "$THIS_SCRIPT" >&2
}

############
### Arguments Functions
############
#!/usr/bin/env bash
set -uo pipefail
IFS=$'\n\t'
set +o noclobber

############
### Arguments Functions
############

# Positional arguments: each entry is "<word> <function> <description> <exit_flag>"
pos_arguments_list=(
    "file process_file The file to process 0"
    "output set_output The output directory 1"
)

# Optional arguments: each entry is "<flag> <complex_flag> <function> <description> <exit_flag>"
opt_arguments_list=(
    "-u|--usage 0 usage Displays usage information 1"
    "-d|--debug 0 start_debug Enables debug mode 0"
    "-v|--verbose 0 enable_verbose Enables verbose output 1"
    "-c|--complex 1 handle_compound_action <argument> 0"
    "-h|--help 0 show_help Displays this help message 0"
)

usage() {
    echo "Usage: $0 [--debug] <item1> [<item2> ...]"
    echo "Available items:"
    
    # Display positional arguments
    echo "Positional arguments:"
    for entry in "${pos_arguments_list[@]}"; do
        # Parse each entry using positional splitting
        word=$(echo "$entry" | cut -d' ' -f1)
        func=$(echo "$entry" | cut -d' ' -f2)
        description=$(echo "$entry" | cut -d' ' -f3- | rev | cut -d' ' -f2- | rev)
        exit_flag=$(echo "$entry" | awk '{print $NF}')
        echo "  $word  -> $description"
    done

    # Display optional arguments
    echo "Optional arguments:"
    for entry in "${opt_arguments_list[@]}"; do
        # Parse each entry using positional splitting
        flag=$(echo "$entry" | cut -d' ' -f1)
        complex_flag=$(echo "$entry" | cut -d' ' -f2)
        func=$(echo "$entry" | cut -d' ' -f3)
        description=$(echo "$entry" | cut -d' ' -f4- | rev | cut -d' ' -f2- | rev)
        exit_flag=$(echo "$entry" | awk '{print $NF}')
        echo "  $flag  -> $description"
    done

    echo "Options:"
    echo "  --debug - Enable debug mode"
}

process_file() {
    local arg="$1"
    echo "Processing file: $arg"
}

set_output() {
    local arg="$1"
    echo "Setting output directory to: $arg"
}

start_debug() {
    echo "Debug mode enabled."
}

enable_verbose() {
    echo "Verbose mode enabled."
}

handle_compound_action() {
    echo "Handling complex action."
}

show_help() {
    echo "This is the help message."
}

_main() {
    # Show usage if "-u" or "--usage" is passed
    usage
}

main() { _main "$@"; return "$?"; }

debug=$(start_debug "$@") # Debug declarations, must be first line
retval=0
main "$@"
retval="$?"
end_debug "$debug" # Next line must be a return/print/exit out of function
exit "$retval"

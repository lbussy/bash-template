<!-- omit in toc -->
# Script Documentation: Bash Template Script

<!-- omit in toc -->
## Table of Contents
- [Overview](#overview)
- [Key Features](#key-features)
- [Usage and Customization](#usage-and-customization)
  - [Global Declarations](#global-declarations)
    - [Intended Customization Points - Dynamic](#intended-customization-points---dynamic)
    - [Read-Only Globals](#read-only-globals)
    - [Global Placeholders](#global-placeholders)
- [Documentation Style](#documentation-style)
- [Debugging](#debugging)
  - [Debugging Example](#debugging-example)
- [Exemplar Function](#exemplar-function)

## Overview

This script is a comprehensive Bash template designed for advanced functionality, robust error handling, and detailed logging. It includes features such as:

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

## Usage and Customization

To use this template:

1. Customize the placeholders with your script-specific logic.
2. Follow the provided function and variable documentation style.

### Global Declarations

You can modify the script's functionality and function by using the global declarations at the beginning of the script. While some scripts have three lines up top with some minor changes you can make, this, being more extensible, requires a little scrolling.

Most of these will use environment values, or allow default if the environment does not have this setting: `DRY_RUN=" ${DRY_RUN:-false}" ` means if you set DRY_RUN in the environment (or use `DRY_RUN=true scriptname.sh` to execute), it will default to that value. If the environment does not have this variable set, it will take whatever is to the right of the hyphen (`-`) as its default value.

#### Intended Customization Points - Dynamic

These may be modified dynamically within the script, so I have declared them as such.

* `DRY_RUN="${DRY_RUN:-false}"` - If you set this true, exec_command() will simulate your commands with a one second delay.  You can use this within your functions by checking if `[["${DRY_RUN}" == "true"]]`. You can also set this at runtime with `--dry-run` or `-d'.
* `THIS_SCRIPT=" ${THIS_SCRIPT:-$(basename "$0")}" ` - Sometimes, like when you curl/pipe a script through bash, the script is not aware of its name. You can set a default one here. In most cases, the script uses this for display purposes, but you may have other uses for it.
* USE_CONSOLE="${USE_CONSOLE:-true}"
* `TERSE=" ${TERSE:-false}" ` - As written, when TERSE is true, it will skip blocks, such as the "press any key" in `start_script()`. You may also set this at runtime with the `--terse` or `-t` arguments.
* `LOG_OUTPUT=" ${LOG_OUTPUT:-both}" ` - Determines whether the script will print log output to the console, the log file, or both. The script may programmatically override these.
* `LOG_FILE=" ${LOG_FILE:-}" ` - Also can be overridden in the arguments function with `--log-file` or `-f,` this declares a place to store runtime logs. If blank, the script will store the log in the real user's home (`~`) directory, named `${$SCRIPT_NAME.LOG}`.
* `LOG_LEVEL=" ${LOG_LEVEL:-DEBUG}" ` - The log level at which level and above the script will provide log messages. This facility is independent of the `"$debug"` logging intended purely for script validation and testing purposes. You may set this choice at runtime with the `--log-level` or `-l` arguments.

#### Read-Only Globals

* `REQUIRE_SUDO=" ${REQUIRE_SUDO:-true}" ` - Whether or not the script enforces the use of sudo. Currently, it only allows sudo and not root when executed. I restrict this because it is good practice, but you can change whatever you want.
* `REQUIRE_INTERNET=" ${REQUIRE_INTERNET:-true}" ` - checks to see if the Internet is available, like when you need apt packages.
* `MIN_BASH_VERSION=" ${MIN_BASH_VERSION:-4.0}"` - Minimum bash version required.
* `MIN_OS=11` - Minimum OS version required.
* `MAX_OS=15` - Maximum OS version supported, or use -1 for no limit.
* `SUPPORTED_BITNESS= "32"` - Require 32 or 64-bit (or "both are supported.)
* `SUPPORTED_MODELS` - The script uses this array in the `check_arch()` function, specifically when Raspberry Pi model requirements are important. For instance, a script may not work on the Raspberry Pi 5. Change the models to` = "Supported"` or `= "Not Supported" `as required.
* `DEPENDENCIES` - This is an array of system tools the script requires to work, such as `awk`, `grep`, `cut`, etc.. These are iterated and checked by the `validate_depends()` function.
* `ENV_VARS_BASE` and `ENV_VARS` - `ENV_VARS_BASE` is an array of environment variables the script expects to be present at runtime. Subsequently, the script concatenates this into `ENV_VARS`, which is checked by `validate_env_vars()` at runtime.
* `SYSTEM_READS` - An array of system files that are required to be accessible to the script for proper function. These are iterated and checked by `validate_sys_accs()`.
* `APT_PACKAGES` - A list of apt packages to be installed or upgraded.
WARN_STACK_TRACE="${WARN_STACK_TRACE:-false}"
* `LOG_PROPERTIES` -  This is an exception to the rule of holding these declarations within the script header. The array is created in `setup_log()` depending on color codes set up by `init_colors()`. This array holds an associative array of properties for the logging functions, such as log level, how the level displays in the log, the color to use on the console for such messages (if supported), and the hierarchical number used to determine the message requested meets or exceeds the current log level.
* Another exception to the "declare up top" rule. Colors and commands for terminal capabilities get set within `init_colors()` and are available globally by invoking the variables, e.g. `${FGRED}This is red.${RESET}`. You should be aware that setting and unsetting are intended as stream events; setting blinking, typing a word, and then resetting or setting no_blink will not change the previous letters; it will only turn the mode off for subsequent text.
    * Utility Sequences
        * `RESET` - Resets to the default terminal appearance.
        * `BOLD` - Bolds text.
        * `SMSO` - Sets standout mode, which may differ depending on the terminal type.
        * `RMSO` - Useta standout mode.
        * `UNDERLINE` - Underlines text.
        * `NO_UNDERLINE` - Turns off underline.
        * `BLINK` - Blinks text. For the love of God, please only use this in the event of an impending nuclear strike.
        * `NO_BLINK` - Turns off blinking text mode.
        * `ITALIC` - Italicises text.
        * `NO_ITALIC` - Turns off italics.
        * `MOVE_UP` - Moves the cursor up a line (often used with `CLEAR_LINE`.)
        * `CLEAR_LINE` - Clears the current line of text.
    * Foreground Colors
        * `FGBLK` - Green text
        * `FGRED` - Red text
        * `FGGRN` - Green text
        * `FGYLW` - Yellow text
        * `FGBLU` - Blue text
        * `FGMAG` - Magenta text
        * `FGCYN` - Cyan text
        * `FGWHT` - White text
        * `FGGLD` - Gold text
        * `FGRST` - Reset text color
    * Background Colors
        * `BGBLK` - Black background
        * `BGRED` - Red background
        * `BGGRN` - Green background
        * `BGYLW` - Yellow background
        * `BGBLU` - Blue background
        * `BGMAG` - Magenta background
        * `BGCYN` - Cyan background
        * `BGWHT` - White background
        * `BGRST` - Background color reset

#### Global Placeholders

It is good form to declare variables before use so that the scope is clear. I have declared several globals for such purposes.

* `IS_PATH=" ${IS_PATH:-false}" ` - Within the typical run, `handle_execution_context()` will determine if the script is running from a path in your `PATH` environment. For instance, you may use this within your functions to determine if you have previously installed the script.
* **Project Parameters** - These placehlders are are set when `get_proj_params()` is executed.  You can use defaults that provide some information if you execute the script outside a git repo. The script will fail to these values and continue (useful if you curl/pipe.)
  * `IS_GITHUB_REPO=" ${IS_GITHUB_REPO:-false}" ` - A semaphore for whether you executed the script within a local git repo.
  * `REPO_ORG=" ${REPO_ORG:-lbussy}" ` - The org owner, determined by a part in the origin URL. The script uses this to reconstruct a URL for git manipulations.
  * `REPO_NAME=" ${REPO_NAME:-bash-template}" ` - The repo name, determined by a part in the origin URL. The script uses this to reconstruct a URL for git manipulations and to choose the project's name.
  * `GIT_BRCH=" ${GIT_BRCH:-main}" ` - The current branch, determined by the `git branch `command and used for URL and display purposes.
  * `GIT_TAG=" ${GIT_TAG:-0.0.1}" ` - The default tag (version), determined by the `git tag` command. The script uses this variable to construct a semantic version for display and `-v `checks.
  * `SEM_VER=" ${GIT_TAG:-0.0.1}"` - Holds a generated semantic version; `get_proj_params()` will call `get_sem_ver()` to put together the current semantically correct version from the local repo, e.g., `1.0.0-main.2726605-dirty`. I have tested this version style to be correct for use with `dpkg --compare-versions` if needed.
  * `LOCAL_SOURCE_DIR=" ${LOCAL_SOURCE_DIR:-}" ` - Will hold the git repo base path.
  * `LOCAL_WWW_DIR=" ${LOCAL_WWW_DIR:-}" ` - Will hold the web file locations, by default `$LOCAL_SOURCE_DIR/data`. A use case would be to extend the script to install a set of web pages in the data directory.
  * `LOCAL_SCRIPTS_DIR=" ${LOCAL_SCRIPTS_DIR:-}" ` - Will hold the script file locations, by default `$LOCAL_SCRIPTS_DIR/scripts`. A use case would be extending the script to execute a set of scripts or source libraries located in the scripts directory.
  * `GIT_RAW="${GIT_RAW:-"https://raw.githubusercontent.com/$REPO_ORG/$REPO_NAME"}"` - A placeholder to access a file on GitHub in raw text form.
  * `GIT_API="${GIT_API:-"https://api.github.com/repos/$REPO_ORG/$REPO_NAME"}"` - A URL which you may use with helper applications (like `jq`) to read information about your GitHub repo.
* `CONSOLE_STATE="${CONSOLE_STATE:-$USE_CONSOLE}"` - Holds the previious `CONSOLE_STATE` when `USE_CONSOLE` is changed within the program.
* `OPTIONS` - This variable is a placeholder for usage menu options.

## Documentation Style

This script adheres to Doxygen-style documentation. While I've tried to make this README comprehensive, you must delve into the script at some point. There are way more comment lines than script lines. For fun, I wrote a little script (of course!) to find that out:

``` bash
#!/bin/bash

# Check if a file is provided as an argument
if [ $# -ne 1 ]; then
    echo "Usage: $0 <script.sh>"
    exit 1
fi

# File to be analyzed
file= "$1"

# Count actual lines (non-empty and not comments)
real_lines=$(grep -v '^\s*#' "$file" | grep -v '^\s*$' | wc -l)

# Count comment lines (lines that start with #)
comment_lines=$(grep '^\s*#' "$file" | wc -l)

# Count whitespace lines (empty or only whitespace)
whitespace_lines=$(grep '^\s*$' "$file" | wc -l)

# Output the results
echo "Real lines: $real_lines"
echo "Comment lines: $comment_lines"
echo "Whitespace lines: $whitespace_lines"
```
The results:

* Real lines: 1751
* Comment lines: 1853
* Whitespace lines: 407

Here's an example of the comments I've tried to provide everywhere:

``` bash
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
You may enable debugging by passing a `debug` flag to functions. When enabled, debug messages are printed to `stderr` to avoid conflicting with functions that need to return text or numbers to the calling script.

### Debugging Example
``` bash
local debug="${1:-}"  # Optional debug flag
[[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$FUNCNAME" "$caller_name" "$caller_line"
```

The $debug argument is passed to ass subsequent functions. If you pass it to the script, e.g., `./template "debug"`, you will see the debug output of every function called like this:

```
pi@pi:~/bash-template $ sudo ./template.sh "debug"
[DEBUG] Function 'main()' called by 'main()' at line 4010.
[DEBUG] Function 'handle_execution_context()' called by 'main()' at line 3969.
[DEBUG] Function 'determine_execution_context()' called by 'handle_execution_context()' at line 1278.
[DEBUG] Determining script execution context.
[DEBUG] Resolved script path: /home/pi/bash-template/template.sh.
[DEBUG] GitHub repository detected at depth 0: /home/pi/bash-template.
[DEBUG] Execution context: Script is within a GitHub repository.
[DEBUG] Function 'get_proj_params()' called by 'main()' at line 3970.
[DEBUG] Configuring local mode with GitHub repository context.
[DEBUG] THIS_SCRIPT set to: template.sh
[DEBUG] Function 'get_repo_org()' called by 'get_proj_params()' at line 3310.
[DEBUG] Retrieved organization from local Git remote URL: lbussy
[DEBUG] Exiting function' get_repo_org()'.
[DEBUG] REPO_ORG set to: lbussy
[DEBUG] Function 'get_repo_name()' called by 'get_proj_params()' at line 3313.
[DEBUG] Exiting function 'get_repo_name()'.
[DEBUG] REPO_NAME set to: bash-template
[DEBUG] Function 'get_git_branch()' called by 'get_proj_params()' at line 3316.
[DEBUG] Exiting function 'get_git_branch()'.
[DEBUG] GIT_BRCH set to: main
[DEBUG] Function 'get_last_tag()' called by 'get_proj_params()' at line 3319.
[DEBUG] Retrieved tag from Git: 1.0.0
[DEBUG] Exiting function' get_last_tag()'.
[DEBUG] GIT_TAG set to: 1.0.0
[DEBUG] Function 'get_sem_ver()' called by 'get_proj_params()' at line 3322.
[DEBUG] Function 'get_last_tag()' called by 'get_sem_ver()' at line 3228.
[DEBUG] Retrieved tag from Git: 1.0.0
[DEBUG] Exiting function' get_last_tag()'.
[DEBUG] Received tag: from get_last_tag().
[DEBUG] Function 'get_git_branch()' called by 'get_sem_ver()' at line 3238.
[DEBUG] Exiting function 'get_git_branch()'.
[DEBUG] Appended branch name to version: main
[DEBUG] Function 'get_num_commits()' called by 'get_sem_ver()' at line 3243.
[DEBUG] Exiting function 'get_num_commits()'.
[DEBUG] Function 'get_short_hash()' called by 'get_sem_ver()' at line 3250.
[DEBUG] Short hash of the current commit: 2726605
[DEBUG] Exiting function' get_short_hash()'.
[DEBUG] Appended short hash to version: 2726605
[DEBUG] Function 'get_dirty()' called by 'get_sem_ver()' at line 3255.
[DEBUG] Changes detected..
[DEBUG] Exiting function' get_dirty()'.
[DEBUG] Repository is dirty. Appended '-dirty' to version.
[DEBUG] Exiting function' get_sem_ver()', SEM_VER is 1.0.0-main.2726605-dirty.
[DEBUG] SEM_VER set to: 1.0.0-main.2726605-dirty
[DEBUG] LOCAL_SOURCE_DIR set to: /home/pi/bash-template
[DEBUG] LOCAL_WWW_DIR set to: /home/pi/bash-template/data
[DEBUG] LOCAL_SCRIPTS_DIR set to: /home/pi/bash-template/scripts
[DEBUG] Exiting function' get_proj_params()'.
[DEBUG] Function 'parse_args()' called by 'main()' at line 3971.
[ERROR] Unknown option: debug
[DEBUG] Function 'usage()' called by 'parse_args()' at line 3908.
pi@pi:~/bash-template $
```

## Exemplar Function

This example shows how a function can receive an optional "debug" argument to enable debug printing:

``` bash
one_arg() {
    # Debug declarations
    local debug=$(start_debug "$@")

    # Do stuff
    # ...
    local var="foo"
    debug_print "This is a conditional debug print that says $foo."

    # Debug log: function exit
    end_debug "$debug"
}
```

#!/usr/bin/env bash
set -uo pipefail # Setting -e is far too much work here
IFS=$'\n\t'
set +o noclobber

# -----------------------------------------------------------------------------
# @file
# @brief Comprehensive Bash script template with advanced functionality.
#
# @details
# This script provides a robust framework for managing installation processes
# with extensive logging, error handling, and system validation. It includes:
# - Detailed stack traces for debugging.
# - Dynamic logging configuration with support for various levels (DEBUG, INFO, etc.).
# - System checks for compatibility with OS versions, architectures, dependencies, and environment variables.
# - Internet connectivity validation with proxy support.
# - Git repository context retrieval and semantic versioning utilities.
#
# @author Lee Bussy
# @date December 21, 2024
# @version 1.0.0
#
# @copyright
# This script is open-source and can be modified or distributed under the terms
# of the MIT license.
#
# @par Usage:
# ```bash
# ./template.sh [OPTIONS]
# ```
# Run `./template.sh --help` for detailed options.
#
# @par Requirements:
# - Bash version 4.0 or higher.
# - Dependencies as specified in the `DEPENDENCIES` array.
#
# @par Features:
# - Comprehensive environment validation (Bash, OS, dependencies, etc.).
# - Automatic Git context resolution for local and remote repositories.
# - Semantic version generation based on Git tags and commit history.
# - Flexible logging with customizable verbosity and output locations.
#
# @see
# Refer to the repository README for detailed function-level explanations.
#
# @warning
# Ensure this script is executed with appropriate permissions (e.g., sudo for installation tasks).
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# @brief Trap unexpected errors during script execution.
# @details Captures any errors (via the ERR signal) that occur during script execution.
# Logs the function name and line number where the error occurred and exits the script.
# The trap calls an error-handling function for better flexibility.
#
# @global FUNCNAME Array containing function names in the call stack.
# @global LINENO Line number where the error occurred.
# @global THIS_SCRIPT Name of the script.
#
# @return None (exits the script with an error code).
# -----------------------------------------------------------------------------
# shellcheck disable=2329
trap_error() {
    # Capture function name, line number, and script name
    local func="${FUNCNAME[1]:-main}"  # Get the calling function name (default: "main")
    local line="${1:-}"                # Line number where the error occurred
    local script="${this_script:-$(basename "${BASH_SOURCE[0]:-$0}")}"

    # Use global THIS_SCRIPT if it exists and is not empty; otherwise, determine the script name
    if [[ -n "${THIS_SCRIPT:-}" ]]; then
        script="$THIS_SCRIPT"
    else
        script="${this_script:-$(basename "${BASH_SOURCE[0]:-$0}")}"

        # Check if the script name is valid; fallback to "temp_script.sh" if it's bash or invalid
        if [[ "$script" == "bash" || -z "$script" ]]; then
            script="temp_script.sh"
        fi
    fi

    # Validate that the line number is set
    if [[ -z "$line" ]]; then
        line="unknown"
    fi

    # Log the error message to stderr
    printf "\n[ERROR] An unexpected error occurred in function '%s()' at line %s of script '%s'. Exiting.\n" \
        "$func" "$line" "$script" >&2

    # Exit with a non-zero status code
    exit 1
}

# Set the trap to call trap_error on any error
# Uncomment the next line to help with script debugging
# trap 'trap_error "$LINENO"' ERR

############
### Global Script Declarations
############

# -----------------------------------------------------------------------------
# @brief Determines the script name to use.
# @details This block of code determines the value of `THIS_SCRIPT` based on
#          the following logic:
#          1. If `THIS_SCRIPT` is already set in the environment, it is used.
#          2. If `THIS_SCRIPT` is not set, the script checks if
#             `${BASH_SOURCE[0]}` is available:
#             - If `${BASH_SOURCE[0]}` is set and not equal to `"bash"`, the
#               script extracts the filename (without the path) using
#               `basename` and assigns it to `THIS_SCRIPT`.
#             - If `${BASH_SOURCE[0]}` is unbound or equals `"bash"`, it falls
#               back to using the value of `FALLBACK_SCRIPT_NAME`, which
#               defaults to `debug_print.sh`.
#
# @var FALLBACK_SCRIPT_NAME
# @brief Default name for the script in case `BASH_SOURCE[0]` is unavailable.
# @details This variable is used as a fallback value if `BASH_SOURCE[0]` is
#          not set or equals `"bash"`. The default value is `"debug_print.sh"`.
#
# @var THIS_SCRIPT
# @brief Holds the name of the script to use.
# @details The script attempts to determine the name of the script to use. If
#          `THIS_SCRIPT` is already set in the environment, it is used
#          directly. Otherwise, the script tries to extract the filename from
#          `${BASH_SOURCE[0]}` (using `basename`). If that fails, it defaults
#          to `FALLBACK_SCRIPT_NAME`.
# -----------------------------------------------------------------------------
declare FALLBACK_SCRIPT_NAME="${FALLBACK_SCRIPT_NAME:-debug_print.sh}"
if [[ -z "${THIS_SCRIPT:-}" ]]; then
    if [[ -n "${BASH_SOURCE[0]:-}" && "${BASH_SOURCE[0]:-}" != "bash" ]]; then
        # Use BASH_SOURCE[0] if it is available and not "bash"
        THIS_SCRIPT=$(basename "${BASH_SOURCE[0]}")
    else
        # If BASH_SOURCE[0] is unbound or equals "bash", use FALLBACK_SCRIPT_NAME
        THIS_SCRIPT="${FALLBACK_SCRIPT_NAME}"
    fi
fi

# -----------------------------------------------------------------------------
# @var DRY_RUN
# @brief Enables simulated execution of certain commands.
# @details When set to `true`, commands are not actually executed but are
#          simulated to allow testing or validation without side effects.
#          If set to `false`, commands execute normally.
#
# @example
# DRY_RUN=true ./template.sh  # Run the script in dry-run mode.
# -----------------------------------------------------------------------------
declare DRY_RUN="${DRY_RUN:-false}"  # Use existing value, or default to "false".

# -----------------------------------------------------------------------------
# @var IS_PATH
# @brief Indicates whether the script was executed from a `PATH` location.
# @details This variable is initialized to `false` by default. During execution,
#          it is dynamically set to `true` if the script is determined to have
#          been executed from a directory listed in the `PATH` environment variable.
#
# @example
# if [[ "$IS_PATH" == "true" ]]; then
#     echo "Script was executed from a PATH directory."
# else
#     echo "Script was executed from a non-PATH directory."
# fi
# -----------------------------------------------------------------------------
declare IS_PATH="${IS_PATH:-false}"  # Default to "false".

# -----------------------------------------------------------------------------
# @var IS_REPO
# @brief Indicates whether the script resides in a GitHub repository or subdirectory.
# @details This variable is initialized to `false` by default. During execution, it
#          is dynamically set to `true` if the script is detected to be within a
#          GitHub repository (i.e., if a `.git` directory exists in the directory
#          hierarchy of the script's location).
#
# @example
# if [[ "$IS_REPO" == "true" ]]; then
#     echo "This script resides within a GitHub repository."
# else
#     echo "This script is not located within a GitHub repository."
# fi
# -----------------------------------------------------------------------------
declare IS_REPO="${IS_REPO:-false}"  # Default to "false".

# -----------------------------------------------------------------------------
# @brief Project metadata constants used throughout the script.
# @details These variables provide metadata about the script, including ownership,
#          versioning, project details, and GitHub URLs. They are initialized with
#          default values or dynamically set during execution to reflect the project's
#          context.
#
# @vars
# - @var REPO_ORG The organization or owner of the repository (default: "lbussy").
# - @var REPO_NAME The name of the repository (default: "bash-template").
# - @var REPO_BRANCH The current Git branch name (default: "main").
# - @var GIT_TAG The current Git tag (default: "0.0.1").
# - @var SEM_VER The semantic version of the project (default: "0.0.1").
# - @var LOCAL_REPO_DIR The local source directory path (default: unset).
# - @var LOCAL_WWW_DIR The local web directory path (default: unset).
# - @var LOCAL_SCRIPTS_DIR The local scripts directory path (default: unset).
# - @var GIT_RAW The base URL for accessing raw GitHub content
#                (default: "https://raw.githubusercontent.com/$REPO_ORG/$REPO_NAME").
# - @var GIT_API The base URL for the GitHub API for this repository
#                (default: "https://api.github.com/repos/$REPO_ORG/$REPO_NAME").
# - @var GIT_CLONE The clone URL for the GitHub repository
#                (default: "https://api.github.com/repos/$REPO_ORG/$REPO_NAME").
#
# @example
# echo "Repository: $REPO_ORG/$REPO_NAME"
# echo "Branch: $REPO_BRANCH, Tag: $GIT_TAG, Version: $SEM_VER"
# echo "Source Directory: ${LOCAL_REPO_DIR:-Not Set}"
# echo "WWW Directory: ${LOCAL_WWW_DIR:-Not Set}"
# echo "Scripts Directory: ${LOCAL_SCRIPTS_DIR:-Not Set}"
# echo "Raw URL: $GIT_RAW"
# echo "API URL: $GIT_API"
# -----------------------------------------------------------------------------
declare REPO_ORG="${REPO_ORG:-lbussy}"
declare REPO_NAME="${REPO_NAME:-bash-template}"
declare REPO_BRANCH="${REPO_BRANCH:-main}"
declare GIT_TAG="${GIT_TAG:-0.0.1}"
declare SEM_VER="${GIT_TAG:-0.0.1}"
declare LOCAL_REPO_DIR="${LOCAL_REPO_DIR:-}"
declare LOCAL_WWW_DIR="${LOCAL_WWW_DIR:-}"
declare LOCAL_SCRIPTS_DIR="${LOCAL_SCRIPTS_DIR:-}"
declare GIT_RAW="${GIT_RAW:-"https://raw.githubusercontent.com/$REPO_ORG/$REPO_NAME"}"
declare GIT_API="${GIT_API:-"https://api.github.com/repos/$REPO_ORG/$REPO_NAME"}"

# -----------------------------------------------------------------------------
# Declare Menu Variables
# -----------------------------------------------------------------------------
declare -A MENU_ITEMS       # Associative array of menu items
declare -a MAIN_MENU        # Array defining the main menu screen
declare -a SUB_MENU         # Array defining the sub-menu screen
declare MENU_HEADER="${MENU_HEADER:-Menu}"  # Global menu header

# -----------------------------------------------------------------------------
# @var GIT_DIRS
# @brief List of relevant directories for download.
# @details This array contains the names of the directories within the GitHub
#          repository that will be processed and downloaded. The directories
#          include 'man', 'scripts', and 'conf'. These directories are used
#          in the script to determine which content to fetch from the repository.
# -----------------------------------------------------------------------------
readonly GIT_DIRS=("man" "scripts" "conf")

# -----------------------------------------------------------------------------
# @var USER_HOME
# @brief Home directory of the current user.
# @details This variable stores the home directory of the user executing the script.
#          If the script is run with `sudo`, it uses the home directory of the
#          `SUDO_USER`, otherwise, it defaults to the current user's home directory.
# -----------------------------------------------------------------------------
declare USER_HOME
if [[ -n "${SUDO_USER-}" ]]; then
    readonly USER_HOME=$(eval echo "~$SUDO_USER")
else
    readonly USER_HOME="$HOME"
fi

# -----------------------------------------------------------------------------
# @var REAL_USER
# @brief Actual user executing the script.
# @details This variable stores the real user who is running the script. If the
#          script is being executed with `sudo`, it will store the user who invoked
#          `sudo` (i.e., the actual user), otherwise it stores the current user.
# -----------------------------------------------------------------------------
declare REAL_USER
if [[ -n "${SUDO_USER-}" ]]; then
    readonly REAL_USER="$SUDO_USER"
else
    readonly REAL_USER="$(whoami)"
fi

# -----------------------------------------------------------------------------
# @var USE_CONSOLE
# @brief Controls whether logging output is directed to the console.
# @details When set to `true`, log messages are displayed on the console in
#          addition to being written to the log file (if enabled). When set
#          to `false`, log messages are written only to the log file, making
#          it suitable for non-interactive or automated environments.
#
# @example
# - USE_CONSOLE=true: Logs to both console and file.
# - USE_CONSOLE=false: Logs only to file.
# -----------------------------------------------------------------------------
declare USE_CONSOLE="${USE_CONSOLE:-true}"

# -----------------------------------------------------------------------------
# @var CONSOLE_STATE
# @brief Tracks the original console logging state.
# @details This variable mirrors the value of USE_CONSOLE and provides a
#          consistent reference for toggling or querying the state of console
#          logging.
#
# @example
# - CONSOLE_STATE="USE_CONSOLE": Console logging matches USE_CONSOLE.
# -----------------------------------------------------------------------------
declare CONSOLE_STATE="${CONSOLE_STATE:-$USE_CONSOLE}"

# -----------------------------------------------------------------------------
# @var TERSE
# @brief Enables or disables terse logging mode.
# @details When `TERSE` is set to `true`, log messages are minimal and optimized
#          for automated environments where concise output is preferred. When
#          set to `false`, log messages are verbose, providing detailed
#          information suitable for debugging or manual intervention.
#
# @example
# TERSE=true  # Enables terse logging mode.
# ./template.sh
#
# TERSE=false # Enables verbose logging mode.
# ./template.sh
# -----------------------------------------------------------------------------
declare TERSE="${TERSE:-false}"  # Default to "false" (verbose logging).

# -----------------------------------------------------------------------------
# @var REQUIRE_SUDO
# @brief Indicates whether root privileges are required to run the script.
# @details This variable determines if the script requires execution with root
#          privileges. It defaults to `true`, meaning the script will enforce
#          that it is run with `sudo` or as a root user. This behavior can be
#          overridden by setting the `REQUIRE_SUDO` environment variable to `false`.
#
# @default true
#
# @example
# REQUIRE_SUDO=false ./template.sh  # Run the script without enforcing root privileges.
# -----------------------------------------------------------------------------
readonly REQUIRE_SUDO="${REQUIRE_SUDO:-true}"  # Default to "true" if not specified.

# -----------------------------------------------------------------------------
# @var REQUIRE_INTERNET
# @type string
# @brief Flag indicating if internet connectivity is required.
# @details Controls whether the script should verify internet connectivity
#          during initialization. This variable can be overridden by setting
#          the `REQUIRE_INTERNET` environment variable before running the script.
#
# @values
# - `"true"`: Internet connectivity is required.
# - `"false"`: Internet connectivity is not required.
#
# @default "true"
#
# @example
# REQUIRE_INTERNET=false ./template.sh  # Run the script without verifying internet connectivity.
# -----------------------------------------------------------------------------
readonly REQUIRE_INTERNET="${REQUIRE_INTERNET:-true}"  # Default to "true" if not set.

# -----------------------------------------------------------------------------
# @var MIN_BASH_VERSION
# @brief Specifies the minimum supported Bash version.
# @details Defines the minimum Bash version required to execute the script. By
#          default, it is set to `4.0`. This value can be overridden by setting
#          the `MIN_BASH_VERSION` environment variable before running the script.
#          To disable version checks entirely, set this variable to `"none"`.
#
# @default "4.0"
#
# @example
# MIN_BASH_VERSION="none" ./template.sh  # Disable Bash version checks.
# MIN_BASH_VERSION="5.0" ./template.sh   # Require at least Bash 5.0.
# -----------------------------------------------------------------------------
readonly MIN_BASH_VERSION="${MIN_BASH_VERSION:-4.0}"  # Default to "4.0" if not specified.

# -----------------------------------------------------------------------------
# @var MIN_OS
# @brief Specifies the minimum supported OS version.
# @details Defines the lowest OS version that the script supports. This value
#          should be updated as compatibility requirements evolve. It is used
#          to ensure the script is executed only on compatible systems.
#
# @default 11
#
# @example
# if [[ "$CURRENT_OS_VERSION" -lt "$MIN_OS" ]]; then
#     echo "This script requires OS version $MIN_OS or higher."
#     exit 1
# fi
# -----------------------------------------------------------------------------
readonly MIN_OS=11  # Minimum supported OS version.

# -----------------------------------------------------------------------------
# @var MAX_OS
# @brief Specifies the maximum supported OS version.
# @details Defines the highest OS version that the script supports. If the script
#          is executed on a system with an OS version higher than this value,
#          it may not function as intended. Set this to `-1` to indicate no upper
#          limit on supported OS versions.
#
# @default 15
#
# @example
# if [[ "$CURRENT_OS_VERSION" -gt "$MAX_OS" && "$MAX_OS" -ne -1 ]]; then
#     echo "This script supports OS versions up to $MAX_OS."
#     exit 1
# fi
# -----------------------------------------------------------------------------
readonly MAX_OS=15  # Maximum supported OS version (use -1 for no upper limit).

# -----------------------------------------------------------------------------
# @var SUPPORTED_BITNESS
# @brief Specifies the supported system bitness.
# @details Defines the system architectures that the script supports. Acceptable
#          values are:
#          - `"32"`: Only supports 32-bit systems.
#          - `"64"`: Only supports 64-bit systems.
#          - `"both"`: Supports both 32-bit and 64-bit systems.
#          This variable ensures compatibility with the intended system architecture.
#          It defaults to `"32"` if not explicitly set.
#
# @default "32"
#
# @example
# if [[ "$SYSTEM_BITNESS" != "$SUPPORTED_BITNESS" && "$SUPPORTED_BITNESS" != "both" ]]; then
#     echo "This script supports $SUPPORTED_BITNESS-bit systems only."
#     exit 1
# fi
# -----------------------------------------------------------------------------
readonly SUPPORTED_BITNESS="32"  # Supported bitness ("32", "64", or "both").

# -----------------------------------------------------------------------------
# @var SUPPORTED_MODELS
# @brief Associative array of Raspberry Pi models and their support statuses.
# @details This associative array maps Raspberry Pi model identifiers to their
#          corresponding support statuses. Each key is a pipe-delimited string
#          containing:
#          - The model name (e.g., "Raspberry Pi 4 Model B").
#          - A simplified identifier (e.g., "4-model-b").
#          - The chipset identifier (e.g., "bcm2711").
#
#          The value is the support status, which can be:
#          - `"Supported"`: Indicates the model is fully supported by the script.
#          - `"Not Supported"`: Indicates the model is not supported.
#
#          This array is marked as `readonly` to ensure it remains immutable at runtime.
#
# @example
# for model in "${!SUPPORTED_MODELS[@]}"; do
#     IFS="|" read -r full_name short_name chipset <<< "$model"
#     echo "Model: $full_name ($short_name, $chipset) - Status: ${SUPPORTED_MODELS[$model]}"
# done
# -----------------------------------------------------------------------------
declare -A SUPPORTED_MODELS=(
    # Unsupported Models
    ["Raspberry Pi 5|5-model-b|bcm2712"]="Not Supported"              # Raspberry Pi 5 Model B
    ["Raspberry Pi 400|400|bcm2711"]="Not Supported"                  # Raspberry Pi 400
    ["Raspberry Pi Compute Module 4|4-compute-module|bcm2711"]="Not Supported" # Compute Module 4
    ["Raspberry Pi Compute Module 3|3-compute-module|bcm2837"]="Not Supported" # Compute Module 3
    ["Raspberry Pi Compute Module|compute-module|bcm2835"]="Not Supported"     # Original Compute Module

    # Supported Models
    ["Raspberry Pi 4 Model B|4-model-b|bcm2711"]="Supported"          # Raspberry Pi 4 Model B
    ["Raspberry Pi 3 Model A+|3-model-a-plus|bcm2837"]="Supported"    # Raspberry Pi 3 Model A+
    ["Raspberry Pi 3 Model B+|3-model-b-plus|bcm2837"]="Supported"    # Raspberry Pi 3 Model B+
    ["Raspberry Pi 3 Model B|3-model-b|bcm2837"]="Supported"          # Raspberry Pi 3 Model B
    ["Raspberry Pi 2 Model B|2-model-b|bcm2836"]="Supported"          # Raspberry Pi 2 Model B
    ["Raspberry Pi Model A+|model-a-plus|bcm2835"]="Supported"        # Raspberry Pi Model A+
    ["Raspberry Pi Model B+|model-b-plus|bcm2835"]="Supported"        # Raspberry Pi Model B+
    ["Raspberry Pi Model B Rev 2|model-b-rev2|bcm2835"]="Supported"   # Raspberry Pi Model B Rev 2
    ["Raspberry Pi Model A|model-a|bcm2835"]="Supported"              # Raspberry Pi Model A
    ["Raspberry Pi Model B|model-b|bcm2835"]="Supported"              # Raspberry Pi Model B
    ["Raspberry Pi Zero 2 W|model-zero-2-w|bcm2837"]="Supported"      # Raspberry Pi Zero 2 W
    ["Raspberry Pi Zero|model-zero|bcm2835"]="Supported"              # Raspberry Pi Zero
    ["Raspberry Pi Zero W|model-zero-w|bcm2835"]="Supported"          # Raspberry Pi Zero W
)
readonly SUPPORTED_MODELS

# -----------------------------------------------------------------------------
# @var LOG_OUTPUT
# @brief Controls where log messages are directed.
# @details Specifies the logging destination(s) for the script's output. This
#          variable can be set to one of the following values:
#          - `"file"`: Log messages are written only to a file.
#          - `"console"`: Log messages are displayed only on the console.
#          - `"both"`: Log messages are written to both the console and a file.
#          - `unset`: Defaults to `"both"`.
#
#          This variable allows flexible logging behavior depending on the
#          environment or use case.
#
# @default "both"
#
# @example
# LOG_OUTPUT="file" ./template.sh      # Logs to a file only.
# LOG_OUTPUT="console" ./template.sh   # Logs to the console only.
# LOG_OUTPUT="both" ./template.sh      # Logs to both destinations.
# -----------------------------------------------------------------------------
declare LOG_OUTPUT="${LOG_OUTPUT:-both}"  # Default to logging to both console and file.

# -----------------------------------------------------------------------------
# @var LOG_FILE
# @brief Specifies the path to the log file.
# @details Defines the file path where log messages are written when logging
#          to a file is enabled. If not explicitly set, this variable defaults
#          to blank, meaning no log file will be used unless a specific path
#          is assigned at runtime or through an external environment variable.
#
# @default ""
#
# @example
# LOG_FILE="/var/log/my_script.log" ./template.sh  # Use a custom log file.
# -----------------------------------------------------------------------------
declare LOG_FILE="${LOG_FILE:-}"  # Use the provided LOG_FILE or default to blank.

# -----------------------------------------------------------------------------
# @var LOG_LEVEL
# @brief Specifies the logging verbosity level.
# @details Defines the verbosity level for logging messages. This variable
#          controls which messages are logged based on their severity. It
#          defaults to `"DEBUG"` if not set. Common log levels include:
#          - `"DEBUG"`: Detailed messages for troubleshooting and development.
#          - `"INFO"`: Informational messages about normal operations.
#          - `"WARN"`: Warning messages indicating potential issues.
#          - `"ERROR"`: Errors that require immediate attention.
#          - `"CRITICAL"`: Critical issues that may cause the script to fail.
#
# @default "DEBUG"
#
# @example
# LOG_LEVEL="INFO" ./template.sh  # Set the log level to INFO.
# -----------------------------------------------------------------------------
declare LOG_LEVEL="${LOG_LEVEL:-DEBUG}"  # Default log level is DEBUG if not set.

# -----------------------------------------------------------------------------
# @var DEPENDENCIES
# @type array
# @brief List of required external commands for the script.
# @details This array defines the external commands that the script depends on
#          to function correctly. Each command in this list is checked for
#          availability at runtime. If a required command is missing, the script
#          may fail or display an error message.
#
#          Best practices:
#          - Ensure all required commands are included.
#          - Use a dependency-checking function to verify their presence early in the script.
#
# @default
# A predefined set of common system utilities:
# - `"awk"`, `"grep"`, `"tput"`, `"cut"`, `"tr"`, `"getconf"`, `"cat"`, `"sed"`,
#   `"basename"`, `"getent"`, `"date"`, `"printf"`, `"whoami"`, `"touch"`,
#   `"dpkg"`, `"git"`, `"dpkg-reconfigure"`, `"curl"`, `"wget"`, `"realpath"`.
#
# @note Update this list as needed to reflect the actual commands used in the script.
#
# @example
# for cmd in "${DEPENDENCIES[@]}"; do
#     if ! command -v "$cmd" &>/dev/null; then
#         echo "Error: Missing required command: $cmd"
#         exit 1
#     fi
# done
# -----------------------------------------------------------------------------
declare -ar DEPENDENCIES=(
    "awk"
    "grep"
    "tput"
    "cut"
    "tr"
    "getconf"
    "cat"
    "sed"
    "basename"
    "getent"
    "date"
    "printf"
    "whoami"
    "touch"
    "dpkg"
    "git"
    "dpkg-reconfigure"
    "curl"
    "wget"
    "realpath"
)
readonly DEPENDENCIES

# -----------------------------------------------------------------------------
# @var ENV_VARS_BASE
# @type array
# @brief Base list of required environment variables.
# @details Defines the core environment variables that the script relies on,
#          regardless of the runtime context. These variables must be set to
#          ensure the script functions correctly.
#
#          - `HOME`: Specifies the home directory of the current user.
#          - `COLUMNS`: Defines the width of the terminal, used for formatting.
#
# @example
# for var in "${ENV_VARS_BASE[@]}"; do
#     if [[ -z "${!var}" ]]; then
#         echo "Error: Required environment variable '$var' is not set."
#         exit 1
#     fi
# done
# -----------------------------------------------------------------------------
declare -ar ENV_VARS_BASE=(
    "HOME"       # Home directory of the current user
    "COLUMNS"    # Terminal width for formatting
)

# -----------------------------------------------------------------------------
# @var ENV_VARS
# @type array
# @brief Final list of required environment variables.
# @details This array extends `ENV_VARS_BASE` to include additional variables
#          required under specific conditions. If the script requires root
#          privileges (`REQUIRE_SUDO=true`), the `SUDO_USER` variable is added
#          dynamically during runtime. Otherwise, it inherits only the base
#          environment variables.
#
#          - `SUDO_USER`: Identifies the user who invoked the script using `sudo`.
#
# @note Ensure `ENV_VARS_BASE` is properly defined before constructing `ENV_VARS`.
#
# @example
# for var in "${ENV_VARS[@]}"; do
#     if [[ -z "${!var}" ]]; then
#         echo "Error: Required environment variable '$var' is not set."
#         exit 1
#     fi
# done
# -----------------------------------------------------------------------------
if [[ "$REQUIRE_SUDO" == true ]]; then
    readonly -a ENV_VARS=("${ENV_VARS_BASE[@]}" "SUDO_USER")
else
    readonly -a ENV_VARS=("${ENV_VARS_BASE[@]}")
fi

# -----------------------------------------------------------------------------
# @var COLUMNS
# @brief Terminal width in columns.
# @details The `COLUMNS` variable represents the width of the terminal in
#          characters. It is used for formatting output to fit within the
#          terminal's width. If not already set by the environment, it defaults
#          to `80` columns. This value can be overridden externally by setting
#          the `COLUMNS` environment variable before running the script.
#
# @default 80
#
# @example
# echo "The terminal width is set to $COLUMNS columns."
# -----------------------------------------------------------------------------
COLUMNS="${COLUMNS:-80}"  # Default to 80 columns if unset.

# -----------------------------------------------------------------------------
# @var SYSTEM_READS
# @type array
# @brief List of critical system files to check.
# @details Defines the absolute paths to system files that the script depends on
#          for its execution. These files must be present and readable to ensure
#          the script operates correctly. The following files are included:
#          - `/etc/os-release`: Contains operating system identification data.
#          - `/proc/device-tree/compatible`: Identifies hardware compatibility,
#            commonly used in embedded systems like Raspberry Pi.
#
# @example
# for file in "${SYSTEM_READS[@]}"; do
#     if [[ ! -r "$file" ]]; then
#         echo "Error: Required system file '$file' is missing or not readable."
#         exit 1
#     fi
# done
# -----------------------------------------------------------------------------
declare -ar SYSTEM_READS=(
    "/etc/os-release"               # OS identification file
    "/proc/device-tree/compatible"  # Hardware compatibility file
)
readonly SYSTEM_READS

# -----------------------------------------------------------------------------
# @var APT_PACKAGES
# @type array
# @brief List of required APT packages.
# @details Defines the APT packages that the script depends on for its execution.
#          These packages should be available in the system's default package
#          repository. The script will check for their presence and attempt to
#          install any missing packages as needed.
#
#          Packages included:
#          - `jq`: JSON parsing utility.
#          - `git`: Version control system.
#
# @example
# for pkg in "${APT_PACKAGES[@]}"; do
#     if ! dpkg -l "$pkg" &>/dev/null; then
#         echo "Error: Required package '$pkg' is not installed."
#         exit 1
#     fi
# done
# -----------------------------------------------------------------------------
readonly APT_PACKAGES=(
    "jq"   # JSON parsing utility
    "git"  # Version control system
)

# -----------------------------------------------------------------------------
# @var WARN_STACK_TRACE
# @type string
# @brief Flag to enable stack trace logging for warnings.
# @details Controls whether stack traces are printed alongside warning messages.
#          This feature is particularly useful for debugging and tracking the
#          script's execution path in complex workflows.
#
#          Possible values:
#          - `"true"`: Enables stack trace logging for warnings.
#          - `"false"`: Disables stack trace logging for warnings (default).
#
# @default "false"
#
# @example
# WARN_STACK_TRACE=true ./template.sh  # Enable stack traces for warnings.
# WARN_STACK_TRACE=false ./template.sh # Disable stack traces for warnings.
# -----------------------------------------------------------------------------
readonly WARN_STACK_TRACE="${WARN_STACK_TRACE:-false}"  # Default to false if not set.

############
### Common Functions
############

# -----------------------------------------------------------------------------
# @brief Starts the debug process.
# @details This function checks if the "debug" flag is present in the
#          arguments, and if so, prints the debug information including the
#          function call and the line number.
#
# @param "$@" Arguments to check for the "debug" flag.
# @return The "debug" flag if present, or an empty string if not.
# -----------------------------------------------------------------------------
debug_start() {
    local debug=""
    local args=()  # Array to hold non-debug arguments
    for arg in "$@"; do
        if [[ "$arg" == "debug" ]]; then
            debug="debug"
            break  # Exit the loop as soon as we find "debug"
        fi
    done

    # Handle empty or unset FUNCNAME and BASH_LINENO gracefully
    local func_name="${FUNCNAME[1]:-main}"
    local caller_name="${FUNCNAME[2]:-main}"
    local caller_line=${BASH_LINENO[0]:-0}

    # Print debug information if the flag is set
    if [[ "$debug" == "debug" ]]; then
        printf "[DEBUG:%s] Starting function %s() called by %s():%d.\n" \
        "$THIS_SCRIPT" "$func_name" "$caller_name" "$caller_line" >&2
    fi

    # Return debug flag if present
    printf "%s\n" "${debug:-}"
    return 0
}

# -----------------------------------------------------------------------------
# @brief Filters out the "debug" flag from the arguments.
# @details This function removes the "debug" flag from the list of arguments
#          and returns the filtered arguments. The debug flag is not passed
#          to other functions.
#
# @param "$@" Arguments to filter.
# @return Filtered arguments, excluding "debug".
# -----------------------------------------------------------------------------
debug_filter() {
    local args=()
    for arg in "$@"; do
        [[ "$arg" == "debug" ]] || args+=("$arg")
    done
    printf "%q " "${args[@]}"
}

# -----------------------------------------------------------------------------
# @brief Prints a debug message if the debug flag is set.
# @details This function checks if the "debug" flag is present in the arguments
#          and, if so, prints the provided debug message along with the function
#          and line number where it was called.
#
# @param "$@" Arguments to check for the "debug" flag and message.
# @global debug Debug flag, passed from the calling function.
# @return None
# -----------------------------------------------------------------------------
debug_print() {
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
    local caller_name="${FUNCNAME[1]:-main}"
    local caller_line=${BASH_LINENO[0]:-0}

    # Assign the remaining argument to the message. Defaults to <unset>
    local message="${1:-<unset>}"

    # Print debug information if the flag is set
    if [[ "$debug" == "debug" ]]; then
        printf "[DEBUG:%s] Message: '%s' sent by %s():%d.\n" \
        "$THIS_SCRIPT" "$message" "$caller_name" "$caller_line" >&2
    fi
}

# -----------------------------------------------------------------------------
# @brief Ends the debug process.
# @details This function checks if the "debug" flag is present in the arguments
#          and, if so, prints the debug information indicating the exit of
#          the function, along with the function name and line number.
#
# @param "$@" Arguments to check for the "debug" flag.
# @global debug Debug flag, passed from the calling function.
# @return None
# -----------------------------------------------------------------------------
debug_end() {
    local debug=""
    local args=()  # Array to hold non-debug arguments
    for arg in "$@"; do
        if [[ "$arg" == "debug" ]]; then
            debug="debug"
            break  # Exit the loop as soon as we find "debug"
        fi
    done

    # Handle empty or unset FUNCNAME and BASH_LINENO gracefully
    local func_name="${FUNCNAME[1]:-main}"
    local caller_name="${FUNCNAME[2]:-main}"
    local caller_line=${BASH_LINENO[0]:-0}

    # Print debug information if the flag is set
    if [[ "$debug" == "debug" ]]; then
        printf "[DEBUG:%s] Exiting function %s() called by %s():%d.\n" \
        "$THIS_SCRIPT" "$func_name" "$caller_name" "$caller_line" >&2
    fi
}

# -----------------------------------------------------------------------------
# @brief Pads a number with spaces.
# @details Pads the input number with spaces to the left. Defaults to 4 characters wide but accepts an optional width.
#          Also accepts an optional debug flag, which, when set to "debug", enables debug output.
#
# @param $1 The number to pad (e.g., "7").
# @param $2 (Optional) The width of the output (default is 4). If debug is provided here, it will be considered the debug flag.
# @param $3 (Optional) The debug flag. Pass "debug" to enable debug output.
#
# @return The padded number with spaces as a string.
# -----------------------------------------------------------------------------
pad_with_spaces() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"
    # Declare locals
    local number="$1"       # Input number (mandatory)
    local width="${2:-4}"   # Optional width (default is 4)

    # If the second parameter is "debug", adjust the arguments
    if [[ "$width" == "debug" ]]; then
        debug="$width"
        width=4  # Default width to 4 if "debug" was passed in place of width
    fi

    # Validate input for the number
    if [[ -z "${number:-}" || ! "$number" =~ ^[0-9]+$ ]]; then
        die 1 "Input must be a valid non-negative integer."
    fi

    # Ensure the width is a positive integer
    if [[ ! "$width" =~ ^[0-9]+$ || "$width" -lt 1 ]]; then
        die 1 "Error: Width must be a positive integer."
    fi

    # Strip leading zeroes to prevent octal interpretation
    number=$((10#$number))  # Forces the number to be interpreted as base-10

    # Format the number with leading spaces and return it as a string
    printf "%${width}d\n" "$number"

    debug_end "$debug" # Next line must be a return/print/exit out of function
    return 0
}

# -----------------------------------------------------------------------------
# @brief Wraps primary and secondary messages with ellipses for overflow lines.
# @details Ensures that the primary and secondary messages fit within the
#          specified line width. If a line overflows, ellipses are appended
#          (or prepended for continuation lines). The processed messages are
#          returned as a single string, separated by an ASCII delimiter (␞).
#
# @param $1 [required] Maximum width of each line (numeric).
# @param $2 [required] Primary message string.
# @param $3 [required] Secondary message string.
#
# @global None.
#
# @throws None.
#
# @return A single string containing the formatted primary, overflow, and
#         secondary messages, separated by the ASCII delimiter ␞.
#
# @example
# result=$(wrap_messages 50 "Primary message" "Secondary message")
# echo "$result"
# -----------------------------------------------------------------------------
wrap_messages() {
    local line_width=$1        # Maximum width of each line
    local primary=$2           # Primary message string
    local secondary=$3         # Secondary message string
    local delimiter="␞"        # ASCII delimiter (code 30) for separating messages

    # -----------------------------------------------------------------------------
    # @brief Wraps a message into lines with ellipses for overflow or continuation.
    # @details Splits the message into lines, appending an ellipsis for overflowed
    #          lines and prepending it for continuation lines.
    #
    # @param $1 [required] The message string to wrap.
    # @param $2 [required] Maximum width of each line (numeric).
    #
    # @global None.
    #
    # @throws None.
    #
    # @return A single string with wrapped lines, ellipses added as necessary.
    #
    # @example
    # wrapped=$(wrap_message "This is a long message" 50)
    # echo "$wrapped"
    # -----------------------------------------------------------------------------
    local wrap_message
    wrap_message() {
        local message=$1        # Input message to wrap
        local width=$2          # Maximum width of each line
        local result=()         # Array to store wrapped lines
        local adjusted_width=$((width - 2))  # Adjust width for ellipses

        # Process message line-by-line
        while IFS= read -r line; do
            result+=("$line")
        done <<< "$(printf "%s\n" "$message" | fold -s -w "$adjusted_width")"

        # Add ellipses to wrapped lines
        for ((i = 0; i < ${#result[@]}; i++)); do
            if ((i == 0)); then
                # Append ellipsis to the first line
                result[i]="${result[i]% }…"
            elif ((i == ${#result[@]} - 1)); then
                # Prepend ellipsis to the last line
                result[i]="…${result[i]}"
            else
                # Add ellipses to both ends of middle lines
                result[i]="…${result[i]% }…"
            fi
        done

        # Return the wrapped lines as a single string
        printf "%s\n" "${result[@]}"
    }

    # Process the primary message
    local overflow=""          # Stores overflow lines from the primary message
    if [[ ${#primary} -gt $line_width ]]; then
        local wrapped_primary  # Temporarily stores the wrapped primary message
        wrapped_primary=$(wrap_message "$primary" "$line_width")
        overflow=$(printf "%s\n" "$wrapped_primary" | tail -n +2)
        primary=$(printf "%s\n" "$wrapped_primary" | head -n 1)
    fi

    # Process the secondary message
    if [[ ${#secondary} -gt $line_width ]]; then
        secondary=$(wrap_message "$secondary" "$line_width")
    fi

    # Return the combined messages
    printf "%s%b%s%b%s" "$primary" "$delimiter" "$overflow" "$delimiter" "$secondary"
}

# -----------------------------------------------------------------------------
# @brief Prints a stack trace with optional formatting and a message.
# @details This function generates and displays a formatted stack trace for
#          debugging purposes. It includes a log level and optional details,
#          with color-coded formatting and proper alignment.
#
# @param $1 [optional] Log level (DEBUG, INFO, WARN, ERROR, CRITICAL). Defaults to INFO.
# @param $2 [optional] Primary message for the stack trace.
# @param $@ [optional] Additional context or details for the stack trace.
#
# @global FUNCNAME Array of function names in the call stack.
# @global BASH_LINENO Array of line numbers corresponding to the call stack.
# @global THIS_SCRIPT The name of the current script, used for logging.
# @global COLUMNS Console width, used for formatting output.
#
# @throws None.
#
# @return None. Outputs the stack trace and message to standard output.
#
# @example
# stack_trace WARN "Unexpected condition detected."
# -----------------------------------------------------------------------------
stack_trace() {
    # Determine log level and message
    local level="${1:-INFO}"  # Default to INFO if $1 is not provided
    local message=""

    # Check if $1 is a valid level, otherwise treat it as the message
    case "$level" in
        DEBUG|INFO|WARN|WARNING|ERROR|CRIT|CRITICAL)
            shift
            ;;
        *)
            # If $1 is not a valid level, treat it as the beginning of the message
            message="$level"
            level="INFO"
            shift
            ;;
    esac

    # Concatenate all remaining arguments into $message
    for arg in "$@"; do
        message+="$arg "
    done
    # Trim trailing space
    message="${message% }"

    # Block width and character for header/footer
    local width=60
    local char="-"

    # Define functions to skip
    local skip_functions=("die" "warn" "stack_trace")
    local encountered_main=0 # Track the first occurrence of main()

    # Get the current function name in title case
    local raw_function_name="${FUNCNAME[0]}"
    local function_name
    function_name="$(echo "$raw_function_name" | sed -E 's/_/ /g; s/\b(.)/\U\1/g; s/(\b[A-Za-z])([A-Za-z]*)/\1\L\2/g')"

    # -----------------------------------------------------------------------------
    # @brief Determines if a function should be skipped in the stack trace.
    # @details Skips functions specified in the `skip_functions` list and
    #          ignores duplicate `main()` entries.
    #
    # @param $1 Function name to evaluate.
    #
    # @return 0 if the function should be skipped, 1 otherwise.
    #
    # @example
    # should_skip "main" && continue
    # -----------------------------------------------------------------------------
    should_skip() {
        local func="$1"
        for skip in "${skip_functions[@]}"; do
            if [[ "$func" == "$skip" ]]; then
                return 0 # Skip this function
            fi
        done
        # Skip duplicate main()
        if [[ "$func" == "main" ]]; then
            if (( encountered_main > 0 )); then
                return 0 # Skip subsequent occurrences of main
            fi
            ((encountered_main++))
        fi
        return 1 # Do not skip
    }

    # Iterate through the stack to build the displayed stack
    local displayed_stack=()
    local longest_length=0  # Track the longest function name length

    # Handle a piped script calling stack_trace from main
    if [[ -p /dev/stdin && ${#FUNCNAME[@]} == 1 ]]; then
        displayed_stack+=("$(printf "%s|%s" "main()" "${BASH_LINENO[0]}")")
    fi

    # Handle the rest of the stack
    for ((i = 1; i < ${#FUNCNAME[@]}; i++)); do
        local func="${FUNCNAME[i]}"
        local line="${BASH_LINENO[i - 1]}"
        local current_length=${#func}

        # Skip ignored functions
        if should_skip "$func"; then
            continue
        elif (( current_length > longest_length )); then
            longest_length=$current_length
        fi

        # Prepend the formatted stack entry to reverse the order
        displayed_stack=("$(printf "%s|%s" "$func()" "$line")" "${displayed_stack[@]}")
    done

    # -----------------------------------------------------------------------------
    # @brief Provides a fallback for `tput` commands when errors occur.
    # @details Returns an empty string if `tput` fails, ensuring no errors
    #          propagate during color or formatting setup.
    #
    # @param $@ Command-line arguments passed directly to `tput`.
    #
    # @return Output of `tput` if successful, or an empty string if it fails.
    #
    # @example
    # local bold=$(safe_tput bold)
    # -----------------------------------------------------------------------------
    safe_tput() { tput "$@" 2>/dev/null || printf ""; }

    # General text attributes
    local reset=$(safe_tput sgr0)
    local bold=$(safe_tput bold)

    # Foreground colors
    local fgred=$(safe_tput setaf 1)  # Red text
    local fggrn=$(safe_tput setaf 2)  # Green text
    local fgylw=$(safe_tput setaf 3)  # Yellow text
    local fgblu=$(safe_tput setaf 4)  # Blue text
    local fgmag=$(safe_tput setaf 5)  # Magenta text
    local fgcyn=$(safe_tput setaf 6)  # Cyan text
    local fggld=$(safe_tput setaf 220)  # Gold text
    [[ -z "$fggld" ]] && fggld="$fgylw"  # Fallback to yellow

    # Determine color and label based on the log level
    local color label
    case "$level" in
        DEBUG) color=${fgcyn}; label="[DEBUG]";;
        INFO) color=${fggrn}; label="[INFO ]";;
        WARN|WARNING) color=${fggld}; label="[WARN ]";;
        ERROR) color=${fgmag}; label="[ERROR]";;
        CRIT|CRITICAL) color=${fgred}; label="[CRIT ]";;
    esac

    # Create header
    local dash_count=$(( (width - ${#function_name} - 2) / 2 ))
    local header_l header_r
    header_l="$(printf '%*s' "$dash_count" | tr ' ' "$char")"
    header_r="$header_l"
    [[ $(( (width - ${#function_name}) % 2 )) -eq 1 ]] && header_r="${header_r}${char}"
    local header=$(printf "%b%s%b %b%b%s%b %b%s%b" "${color}" "${header_l}" "${reset}" "${color}" "${bold}" "${function_name}" "${reset}" "${color}" "${header_r}" "${reset}")

    # Create footer
    local footer="$(printf '%*s' "$width" "" | tr ' ' "$char")"
    [[ -n "$color" ]] && footer="${color}${footer}${reset}"

    # Print header
    printf "%s\n" "$header"

    # Print the message, if provided
    if [[ -n "$message" ]]; then
        # Extract the first word and preserve the rest
        local first="${message%% *}"          # Extract up to the first space
        local remainder="${message#* }"      # Remove the first word and the space

        # Format the message
        message="$(printf "%b%b%s%b %b%b%s%b" \
            "${bold}" "${color}" "$first" \
            "${reset}" "${color}" "$remainder" \
            "${reset}")"

        # Print the formatted message
        printf "%b\n" "$message"
    fi

    # Calculate indent for proper alignment
    local indent=$(( ($width / 2) - ((longest_length + 28) / 2) ))

    # Print the displayed stack in reverse order
    for ((i = ${#displayed_stack[@]} - 1, idx = 0; i >= 0; i--, idx++)); do
        IFS='|' read -r func line <<< "${displayed_stack[i]}"
        printf "%b%*s [%d] Function: %-*s Line: %4s%b\n" "${color}" "$indent" ">" "$idx" "$((longest_length + 2))" "$func" "$line" "${reset}"
    done

    # Print footer
    printf "%b%s%b\n\n" "${color}" "$footer" "${reset}"
}

# -----------------------------------------------------------------------------
# @brief Logs a warning message with optional details and stack trace.
# @details Formats and logs a warning message to standard error. The function
#          supports color-coded formatting, automatic line wrapping, and
#          extended details. Optionally includes a stack trace if enabled.
#
# @param $1 [optional] Numeric error code. Defaults to none.
# @param $2 [optional] Primary warning message. Defaults to a generic warning.
# @param $@ [optional] Additional details or context for the warning.
#
# @global THIS_SCRIPT The name of the current script, used for logging.
# @global FUNCNAME Array of function names in the call stack.
# @global BASH_LINENO Array of line numbers corresponding to the call stack.
# @global COLUMNS Console width, used for formatting output.
# @global WARN_STACK_TRACE Enables stack trace logging if set to true.
#
# @throws None.
#
# @return None. Outputs the warning message to standard error.
#
# @example
# warn 1 "Configuration file missing." "Using default settings."
# -----------------------------------------------------------------------------
warn() {
    # Initialize variables
    local script="${THIS_SCRIPT:-unknown}"       # This script's name
    local func_name="${FUNCNAME[1]:-main}"       # Calling function
    local caller_line=${BASH_LINENO[0]:-0}       # Calling line
    local error_code=""                          # Error code, default blank
    local message=""                             # Primary message
    local details=""                             # Additional details
    local width=${COLUMNS:-80}                   # Max console width
    local delimiter="␞"                          # Delimiter for wrapped parts

    # -----------------------------------------------------------------------------
    # @brief Provides a fallback for `tput` commands when errors occur.
    # @details Returns an empty string if `tput` fails, ensuring no errors
    #          propagate during color or formatting setup.
    #
    # @param $@ Command-line arguments passed directly to `tput`.
    #
    # @return Output of `tput` if successful, or an empty string if it fails.
    #
    # @example
    # local bold=$(safe_tput bold)
    # -----------------------------------------------------------------------------
    safe_tput() { tput "$@" 2>/dev/null || printf ""; }

    # General text attributes
    local reset=$(safe_tput sgr0)
    local bold=$(safe_tput bold)

    # Foreground colors
    local fgylw=$(safe_tput setaf 3)  # Yellow text
    local fgblu=$(safe_tput setaf 4)  # Blue text
    local fgcyn=$(safe_tput setaf 6)  # Cyan text
    local fggld=$(safe_tput setaf 220)  # Gold text
    [[ -z "$fggld" ]] && fggld="$fgylw"  # Fallback to yellow

    # -----------------------------------------------------------------------------
    # @brief Creates a formatted prefix for logging messages.
    # @details Combines color, labels, and positional information into a prefix.
    #
    # @param $1 Color for the prefix.
    # @param $2 Label for the message (e.g., "[WARN ]").
    #
    # @return Formatted prefix as a string.
    #
    # @example
    # local warn_prefix=$(format_prefix "$fggld" "[WARN ]")
    # -----------------------------------------------------------------------------
    format_prefix() {
        local color=$1
        local label=$2
        printf "%b%s%b %b[%s:%s:%s]%b " \
            "${bold}${color}" "$label" "${reset}" \
            "${bold}" "$script" "$func_name" "$caller_line" "${reset}"
    }

    # Generate prefixes
    local warn_prefix=$(format_prefix "$fggld" "[WARN ]")
    local extd_prefix=$(format_prefix "$fgcyn" "[EXTND]")
    local dets_prefix=$(format_prefix "$fgblu" "[DETLS]")

    # Strip ANSI escape sequences for length calculation
    local plain_warn_prefix=$(echo -e "$warn_prefix" | sed 's/\x1b\[[0-9;]*m//g')
    local prefix_length=${#plain_warn_prefix}
    local adjusted_width=$((width - prefix_length))

    # Parse error code if the first parameter is numeric
    if [[ -n "${1:-}" && "$1" =~ ^[0-9]+$ ]]; then
        error_code=$((10#$1))  # Convert to numeric
        shift
    fi

    # Process primary message
    message=$(add_period "${1:-A warning was raised on this line}")
    if [[ -n "$error_code" ]]; then
        message=$(printf "%s Code: (%d)" "$message" "$error_code")
    fi
    shift

    # Process additional details
    details="${1:-}"
    shift
    for arg in "$@"; do
        details+=" $arg"
    done
    if [[ -n $details ]]; then
        details=$(add_period "$details")
    fi

    # Call wrap_and_combine_messages
    local result
    result=$(wrap_messages "$adjusted_width" "$message" "$details")

    # Parse wrapped parts
    local primary="${result%%${delimiter}*}"
    result="${result#*${delimiter}}"
    local overflow="${result%%${delimiter}*}"
    local secondary="${result#*${delimiter}}"

    # Print the primary message
    printf "%s%s\n" "$warn_prefix" "$primary" >&2

    # Print overflow lines
    if [[ -n "$overflow" ]]; then
        while IFS= read -r line; do
            printf "%s%s\n" "$extd_prefix" "$line" >&2
        done <<< "$overflow"
    fi

    # Print secondary details
    if [[ -n "$secondary" ]]; then
        while IFS= read -r line; do
            printf "%s%s\n" "$dets_prefix" "$line" >&2
        done <<< "$secondary"
    fi

    # Include stack trace for warnings if enabled
    if [[ "${WARN_STACK_TRACE:-false}" == "true" ]]; then
        stack_trace "WARNING" "$message"
    fi
}

# -----------------------------------------------------------------------------
# @brief Terminates the script with a critical error message and details.
# @details This function prints a critical error message along with optional
#          details, formats them with color and indentation, and includes a
#          stack trace for debugging. It then exits with the specified error code.
#
# @param $1 [optional] Numeric error code. Defaults to 1 if not provided.
# @param $2 [optional] Primary error message. Defaults to "Critical error"
#                      if not provided.
# @param $@ [optional] Additional details or context for the error.
#
# @global THIS_SCRIPT The script's name, used for logging.
# @global COLUMNS Console width, used to calculate message formatting.
#
# @throws Exits the script with the provided error code or the default value (1).
#
# @return None. Outputs formatted error messages and terminates the script.
#
# @example
# die 127 "File not found" "The specified file is missing or inaccessible."
# -----------------------------------------------------------------------------
die() {
    # Initialize variables
    local script="${THIS_SCRIPT:-unknown}"       # This script's name
    local func_name="${FUNCNAME[1]:-main}"       # Calling function
    local caller_line=${BASH_LINENO[0]:-0}       # Calling line
    local error_code=""                          # Error code, default blank
    local message=""                             # Primary message
    local details=""                             # Additional details
    local width=${COLUMNS:-80}                   # Max console width
    local delimiter="␞"                          # Delimiter for wrapped parts

    # -----------------------------------------------------------------------------
    # @brief Provides a fallback for `tput` commands when errors occur.
    # @details Returns an empty string if `tput` fails, ensuring no errors
    #          propagate during color or formatting setup.
    #
    # @param $@ Command-line arguments passed directly to `tput`.
    #
    # @return Output of `tput` if successful, or an empty string if it fails.
    #
    # @example
    # local bold=$(safe_tput bold)
    # -----------------------------------------------------------------------------
    safe_tput() {
        tput "$@" 2>/dev/null || printf ""
    }

    # General text attributes
    local reset=$(safe_tput sgr0)
    local bold=$(safe_tput bold)

    # Foreground colors
    local fgred=$(safe_tput setaf 1)  # Red text
    local fgblu=$(safe_tput setaf 4)  # Blue text
    local fgcyn=$(safe_tput setaf 6)  # Cyan text

    # -----------------------------------------------------------------------------
    # @brief Formats a log message prefix with a specified label and color.
    # @details Constructs a formatted prefix string that includes the label,
    #          the script name, the calling function name, and the line number.
    #
    # @param $1 [required] Color for the label (e.g., `$fgred` for red text).
    # @param $2 [required] Label for the prefix (e.g., "[CRIT ]").
    #
    # @return A formatted prefix string with color and details.
    #
    # @example
    # local crit_prefix=$(format_prefix "$fgred" "[CRIT ]")
    # -----------------------------------------------------------------------------
    format_prefix() {
        local color=$1
        local label=$2
        printf "%b%s%b %b[%s:%s:%s]%b " "${bold}${color}" "$label" "${reset}" "${bold}" "$script" "$func_name" "$caller_line" "${reset}"
    }

    # Generate prefixes
    local crit_prefix=$(format_prefix "$fgred" "[CRIT ]")
    local extd_prefix=$(format_prefix "$fgcyn" "[EXTND]")
    local dets_prefix=$(format_prefix "$fgblu" "[DETLS]")

    # Strip ANSI escape sequences for length calculation
    local plain_crit_prefix=$(echo -e "$crit_prefix" | sed 's/\x1b\[[0-9;]*m//g')
    local prefix_length=${#plain_crit_prefix}
    local adjusted_width=$((width - prefix_length))

    # Parse error code if the first parameter is numeric, default to 1
    if [[ -n "${1:-}" && "$1" =~ ^[0-9]+$ ]]; then
        error_code=$((10#$1))  # Convert to numeric
        shift
    else
        error_code=1  # Default to 1 if no numeric value is provided
    fi

    # Process primary message
    message=$(add_period "${1:-Critical error}")
    if [[ -n "$error_code" ]]; then
        message=$(printf "%s Code: (%d)" "$message" "$error_code")
    fi
    shift

    # Process additional details
    details="${1:-}"
    shift
    for arg in "$@"; do
        details+=" $arg"
    done
    if [[ -n $details ]]; then
        details=$(add_period "$details")
    fi

    # Call wrap_and_combine_messages
    local result
    result=$(wrap_messages "$adjusted_width" "$message" "$details")

    # Parse wrapped parts
    local primary="${result%%${delimiter}*}"
    result="${result#*${delimiter}}"
    local overflow="${result%%${delimiter}*}"
    local secondary="${result#*${delimiter}}"

    # Print the primary message
    printf "%s%s\n" "$crit_prefix" "$primary" >&2

    # Print overflow lines
    if [[ -n "$overflow" ]]; then
        while IFS= read -r line; do
            printf "%s%s\n" "$extd_prefix" "$line" >&2
        done <<< "$overflow"
    fi

    # Print secondary details
    if [[ -n "$secondary" ]]; then
        while IFS= read -r line; do
            printf "%s%s\n" "$dets_prefix" "$line" >&2
        done <<< "$secondary"
    fi

    # Include stack trace for warnings if enabled
    stack_trace "CRITICAL" "$message"
    exit "$error_code"
}

# -----------------------------------------------------------------------------
# @brief Add a dot (`.`) at the beginning of a string if it's missing.
# @details This function ensures the input string starts with a leading dot.
#          If the input string is empty, the function logs a warning and returns
#          an error code.
#
# @param $1 The input string to process.
#
# @return Outputs the modified string with a leading dot if it was missing.
# @retval 1 If the input string is empty.
#
# @example
# add_dot "example"   # Outputs ".example"
# add_dot ".example"  # Outputs ".example"
# add_dot ""          # Logs a warning and returns an error.
# -----------------------------------------------------------------------------
add_dot() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"

    local input=${1:-}  # Input string to process

    # Validate input
    if [[ -z "$input" ]]; then
        warn "Input to add_dot cannot be empty."
            debug_end "$debug" # Next line must be a return/print/exit out of function
        return 1
    fi

    # Add a leading dot if it's missing
    if [[ "$input" != .* ]]; then
        input=".$input"
    fi

    debug_end "$debug" # Next line must be a return/print/exit out of function
    printf "%s\n" "$input"
}

# -----------------------------------------------------------------------------
# @brief Remove a leading dot (`.`) from a string if present.
# @details This function processes the input string and removes a leading dot
#          if it exists. If the input string is empty, the function logs an error
#          and returns an error code.
#
# @param $1 The input string to process.
#
# @return Outputs the modified string without a leading dot if one was present.
# @retval 1 If the input string is empty.
#
# @example
# remove_dot ".example"  # Outputs "example"
# remove_dot "example"   # Outputs "example"
# remove_dot ""          # Logs an error and returns an error code.
# -----------------------------------------------------------------------------
remove_dot() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"

    local input=${1:-}  # Input string to process

    # Validate input
    if [[ -z "$input" ]]; then
        warn "ERROR" "Input to remove_dot cannot be empty."
            debug_end "$debug" # Next line must be a return/print/exit out of function
        return 1
    fi

    # Remove the leading dot if present
    if [[ "$input" == *. ]]; then
        input="${input#.}"
    fi

    debug_end "$debug" # Next line must be a return/print/exit out of function
    printf "%s\n" "$input"
}

# -----------------------------------------------------------------------------
# @brief Add a periot (`.`) at the end of a string if it's missing.
# @details This function ensures the input string ends with a period.
#          If the input string is empty, the function logs a warning and returns
#          an error code.
#
# @param $1 The input string to process.
#
# @return Outputs the modified string with a trailing period if it was missing.
# @retval 1 If the input string is empty.
#
# @example
# add_period "example"   # Outputs "example."
# add_period "example."  # Outputs "example."
# add_period ""          # Logs a warning and returns an error.
# -----------------------------------------------------------------------------
add_period() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"

    local input=${1:-}  # Input string to process

    # Validate input
    if [[ -z "$input" ]]; then
        warn "Input to add_period cannot be empty."
            debug_end "$debug" # Next line must be a return/print/exit out of function
        return 1
    fi

    # Add a trailing period if it's missing
    if [[ "$input" != *. ]]; then
        input="$input."
    fi

    debug_end "$debug" # Next line must be a return/print/exit out of function
    printf "%s\n" "$input"
}

# -----------------------------------------------------------------------------
# @brief Remove a trailing period (`.`) from a string if present.
# @details This function processes the input string and removes a trailing period
#          if it exists. If the input string is empty, the function logs an error
#          and returns an error code.
#
# @param $1 The input string to process.
#
# @return Outputs the modified string without a trailing period if one was present.
# @retval 1 If the input string is empty.
#
# @example
# remove_period "example."  # Outputs "example"
# remove_period "example"   # Outputs "example"
# remove_period ""          # Logs an error and returns an error code.
# -----------------------------------------------------------------------------
remove_period() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"

    local input=${1:-}  # Input string to process

    # Validate input
    if [[ -z "$input" ]]; then
        warn "ERROR" "Input to remove_period cannot be empty."
            debug_end "$debug" # Next line must be a return/print/exit out of function
        return 1
    fi

    # Remove the trailing period if present
    if [[ "$input" == *. ]]; then
        input="${input%.}"
    fi

    debug_end "$debug" # Next line must be a return/print/exit out of function
    printf "%s\n" "$input"
}

# -----------------------------------------------------------------------------
# @brief Add a trailing slash (`/`) to a string if it's missing.
# @details This function ensures that the input string ends with a trailing slash.
#          If the input string is empty, the function logs an error and returns
#          an error code.
#
# @param $1 The input string to process.
#
# @return Outputs the modified string with a trailing slash if one was missing.
# @retval 1 If the input string is empty.
#
# @example
# add_slash "/path/to/directory"  # Outputs "/path/to/directory/"
# add_slash "/path/to/directory/" # Outputs "/path/to/directory/"
# add_slash ""                    # Logs an error and returns an error code.
# -----------------------------------------------------------------------------
add_slash() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"

    local input="$1"  # Input string to process

    # Validate input
    if [[ -z "${input:-}" ]]; then
        warn "ERROR" "Input to add_slash cannot be empty."
            debug_end "$debug" # Next line must be a return/print/exit out of function
        return 1
    fi

    # Add a trailing slash if it's missing
    if [[ "$input" != */ ]]; then
        input="$input/"
    fi

    debug_end "$debug" # Next line must be a return/print/exit out of function
    printf "%s\n" "$input"
}

# -----------------------------------------------------------------------------
# @brief Remove a trailing slash (`/`) from a string if present.
# @details This function ensures that the input string does not end with a trailing
#          slash. If the input string is empty, the function logs an error and
#          returns an error code.
#
# @param $1 The input string to process.
#
# @return Outputs the modified string without a trailing slash if one was present.
# @retval 1 If the input string is empty.
#
# @example
# remove_slash "/path/to/directory/"  # Outputs "/path/to/directory"
# remove_slash "/path/to/directory"   # Outputs "/path/to/directory"
# remove_slash ""                     # Logs an error and returns an error code.
# -----------------------------------------------------------------------------
remove_slash() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"

    local input="$1"  # Input string to process

    # Validate input
    if [[ -z "${input:-}" ]]; then
        warn "ERROR" "Input to remove_slash cannot be empty."
            debug_end "$debug" # Next line must be a return/print/exit out of function
        return 1
    fi

    # Remove the trailing slash if present
    if [[ "$input" == */ ]]; then
        input="${input%/}"
    fi

    debug_end "$debug" # Next line must be a return/print/exit out of function
    printf "%s\n" "$input"
}

# -----------------------------------------------------------------------------
# @brief Pauses execution and waits for user input to continue.
# @details This function displays a message prompting the user to press any key
#          to continue. It waits for a single key press, then resumes execution.
#
# @example
# pause
# -----------------------------------------------------------------------------
pause() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"

    printf "Press any key to continue.\n"
    read -n 1 -sr key < /dev/tty || true
    printf "\n"
    debug_print "$key" "$debug"

    debug_end "$debug" # Next line must be a return/print/exit out of function
    return 0
}

############
### Print/Display Environment Functions
############

# -----------------------------------------------------------------------------
# @brief Print the system information to the log.
# @details Extracts and logs the system's name and version using information
#          from `/etc/os-release`. If the information cannot be extracted, logs
#          a warning message. Includes debug output when the `debug` argument is provided.
#
# @param $1 [Optional] Debug flag to enable detailed output (`debug`).
#
# @global None
#
# @return None
#
# @example
# print_system debug
# Outputs system information with debug logs enabled.
# -----------------------------------------------------------------------------
# shellcheck disable=2329
print_system() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"

    # Declare local variables
    local system_name

    # Extract system name and version from /etc/os-release
    system_name=$(grep '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d '=' -f2 | tr -d '"')

    # Debug: Log extracted system name
    debug_print "Extracted system name: ${system_name:-<empty>}\n" "$debug"

    # Check if system_name is empty and log accordingly
    if [[ -z "${system_name:-}" ]]; then
        warn "System: Unknown (could not extract system information)."  # Log warning if system information is unavailable
        debug_print "System information could not be extracted." "$debug"
    else
        logI "System: $system_name."  # Log the system information
        debug_print "Logged system information: $system_name" "$debug"
    fi

    debug_end "$debug" # Next line must be a return/print/exit out of function
    return 0
}

# -----------------------------------------------------------------------------
# @brief Print the script version and optionally log it.
# @details This function displays the version of the script stored in the global
#          variable `SEM_VER`. If called by `parse_args`, it uses `printf` to
#          display the version; otherwise, it logs the version using `logI`.
#          If the debug flag is set to "debug," additional debug information
#          will be printed.
#
# @param $1 [Optional] Debug flag. Pass "debug" to enable debug output.
#
# @global THIS_SCRIPT The name of the script.
# @global SEM_VER The version of the script.
# @global REPO_NAME The name of the repository.
#
# @return None
#
# @example
# print_version debug
# -----------------------------------------------------------------------------
print_version() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"

    # Check the name of the calling function
    local caller="${FUNCNAME[1]}"

    if [[ "$caller" == "parse_args" ]]; then
        printf "%s: version %s\n" "$THIS_SCRIPT" "$SEM_VER" # Display the script name and version
    else
        logI "Running $(repo_to_title_case "$REPO_NAME")'s '$THIS_SCRIPT', version $SEM_VER" # Log the script name and version
    fi

    debug_end "$debug" # Next line must be a return/print/exit out of function
    return 0
}

############
### Check Environment Functions
############

# -----------------------------------------------------------------------------
# @brief Determine the script's execution context.
# @details Identifies how the script was executed, returning one of the
#          predefined context codes. Handles errors gracefully and outputs
#          additional debugging information when the "debug" argument is passed.
#
# Context Codes:
#   - `0`: Script executed via pipe.
#   - `1`: Script executed with `bash` in an unusual way.
#   - `2`: Script executed directly (local or from PATH).
#   - `3`: Script executed from within a GitHub repository.
#   - `4`: Script executed from a PATH location.
#
# @param $1 [Optional] Pass "debug" to enable verbose logging for debugging purposes.
#
# @throws Exits with an error if the script path cannot be resolved or
#         directory traversal exceeds the maximum depth.
#
# @return Returns a context code (described above) indicating the script's
#         execution context.
# -----------------------------------------------------------------------------
determine_execution_context() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"

    local script_path   # Full path of the script
    local current_dir   # Temporary variable to traverse directories
    local max_depth=10  # Limit for directory traversal depth
    local depth=0       # Counter for directory traversal

    # Check if the script is executed via pipe
    if [[ "$0" == "bash" ]]; then
        if [[ -p /dev/stdin ]]; then
            debug_print "Execution context: Script executed via pipe." "$debug"
                    debug_end "$debug" # Next line must be a return/print/exit out of function
            return 0  # Execution via pipe
        else
            warn "Unusual bash execution detected."
                    debug_end "$debug" # Next line must be a return/print/exit out of function
            return 1  # Unusual bash execution
        fi
    fi

    # Get the script path
    script_path=$(realpath "$0" 2>/dev/null) || script_path=$(pwd)/$(basename "$0")
    if [[ ! -f "$script_path" ]]; then
            debug_end "$debug" # Next line must be a return/print/exit out of function
        die 1 "Unable to resolve script path: $script_path"
    fi
    debug_print "Resolved script path: $script_path" "$debug"

    # Initialize current_dir with the directory part of script_path
    current_dir="${script_path%/*}"
    current_dir="${current_dir:-.}"

    # Safeguard against invalid current_dir during initialization
    if [[ ! -d "$current_dir" ]]; then
            debug_end "$debug" # Next line must be a return/print/exit out of function
        die 1 "Invalid starting directory: $current_dir"
    fi

    # Traverse upwards to detect a GitHub repository
    while [[ "$current_dir" != "/" && $depth -lt $max_depth ]]; do
        if [[ -d "$current_dir/.git" ]]; then
            debug_print "GitHub repository detected at depth $depth: $current_dir" "$debug"
                    debug_end "$debug" # Next line must be a return/print/exit out of function
            return 3  # Execution within a GitHub repository
        fi
        current_dir=$(dirname "$current_dir") # Move up one directory
        ((depth++))
    done

    # Handle loop termination conditions
    if [[ $depth -ge $max_depth ]]; then
            debug_end "$debug" # Next line must be a return/print/exit out of function
        die 1 "Directory traversal exceeded maximum depth ($max_depth)"
    fi

    # Check if the script is executed from a PATH location
    local resolved_path
    resolved_path=$(command -v "$(basename "$0")" 2>/dev/null)
    if [[ "$resolved_path" == "$script_path" ]]; then
        debug_print "Script executed from a PATH location: $resolved_path." "$debug"
            debug_end "$debug" # Next line must be a return/print/exit out of function
        return 4  # Execution from a PATH location
    fi

    # Default: Direct execution from the local filesystem
    debug_print "Default context: Script executed directly." "$debug"

    debug_end "$debug" # Next line must be a return/print/exit out of function
    return 2
}

# -----------------------------------------------------------------------------
# @brief Handle the execution context of the script.
# @details Determines the script's execution context by invoking
#          `determine_execution_context` and sets global variables based on
#          the context. Outputs debug information if the "debug" argument is
#          passed. Provides safeguards for unknown or invalid context codes.
#
# @param $1 [Optional] Pass "debug" to enable verbose logging for debugging purposes.
#
# @throws Exits with an error if an invalid context code is returned.
#
# @return None
# -----------------------------------------------------------------------------
handle_execution_context() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"

    # Call determine_execution_context and capture its output
    determine_execution_context "$debug"
    local context=$?  # Capture the return code to determine context

    # Validate the context
    if ! [[ "$context" =~ ^[0-4]$ ]]; then
        debug_end "$debug" # Next line must be a return/print/exit out of function
        die 1 "Invalid context code returned: $context"
    fi

    # Initialize and set global variables based on the context
    case $context in
        0)
            THIS_SCRIPT="piped_script"
            USE_LOCAL=false
            IS_REPO=false
            IS_PATH=false
            debug_print "Execution context: Script was piped (e.g., 'curl url | sudo bash')." "$debug"
            ;;
        1)
            THIS_SCRIPT="piped_script"
            USE_LOCAL=false
            IS_REPO=false
            IS_PATH=false
            warn "Execution context: Script run with 'bash' in an unusual way."
            ;;
        2)
            THIS_SCRIPT=$(basename "$0")
            USE_LOCAL=true
            IS_REPO=false
            IS_PATH=false
            debug_print "Execution context: Script executed directly from $THIS_SCRIPT." "$debug"
            ;;
        3)
            THIS_SCRIPT=$(basename "$0")
            USE_LOCAL=true
            IS_REPO=true
            IS_PATH=false
            debug_print "Execution context: Script is within a GitHub repository."\n" >&2" "$debug"
            ;;
        4)
            THIS_SCRIPT=$(basename "$0")
            USE_LOCAL=true
            IS_REPO=false
            IS_PATH=true
            debug_print "Execution context: Script executed from a PATH location ($(command -v "$THIS_SCRIPT"))" "$debug"
            ;;
        *)
                    debug_end "$debug" # Next line must be a return/print/exit out of function
            die 99 "Unknown execution context."
            ;;
    esac

    debug_end "$debug" # Next line must be a return/print/exit out of function
    return 0
}

# -----------------------------------------------------------------------------
# @brief Enforce that the script is run directly with `sudo`.
# @details Ensures the script is executed with `sudo` privileges and not:
#          - From a `sudo su` shell.
#          - As the root user directly.
#
# @global REQUIRE_SUDO Boolean indicating if `sudo` is required.
# @global SUDO_USER User invoking `sudo`.
# @global SUDO_COMMAND The command invoked with `sudo`.
# @global THIS_SCRIPT Name of the current script.
#
# @param $1 [Optional] Debug flag. Pass "debug" to enable debug output.
#
# @return None
# @exit 1 if the script is not executed correctly.
#
# @example
# enforce_sudo debug
# -----------------------------------------------------------------------------
enforce_sudo() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"

    if [[ "$REQUIRE_SUDO" == true ]]; then
        if [[ "$EUID" -eq 0 && -n "$SUDO_USER" && "$SUDO_COMMAND" == *"$0"* ]]; then
            debug_print "Sudo conditions met. Proceeding." "$debug"
            # Script is properly executed with `sudo`
        elif [[ "$EUID" -eq 0 && -n "$SUDO_USER" ]]; then
            debug_print "Script run from a root shell. Exiting." "$debug"
            die 1 "This script should not be run from a root shell." \
                  "Run it with 'sudo $THIS_SCRIPT' as a regular user."
        elif [[ "$EUID" -eq 0 ]]; then
            debug_print "Script run as root. Exiting." "$debug"
            die 1 "This script should not be run as the root user." \
                  "Run it with 'sudo $THIS_SCRIPT' as a regular user."
        else
            debug_print "Script not run with sudo. Exiting." "$debug"
            die 1 "This script requires 'sudo' privileges." \
                  "Please re-run it using 'sudo $THIS_SCRIPT'."
        fi
    fi
    debug_print "Function parameters:\n\t- REQUIRE_SUDO='$REQUIRE_SUDO'\n\t- EUID='$EUID'\n\t- SUDO_USER='$SUDO_USER'\n\t- SUDO_COMMAND='$SUDO_COMMAND'" "$debug"

    debug_end "$debug" # Next line must be a return/print/exit out of function
    return 0
}

# -----------------------------------------------------------------------------
# @brief Check for required dependencies and report any missing ones.
# @details Iterates through the dependencies listed in the global array `DEPENDENCIES`,
#          checking if each one is installed. Logs missing dependencies and exits
#          the script with an error code if any are missing.
#
# @param $1 [Optional] Debug flag. Pass "debug" to enable debug output.
#
# @global DEPENDENCIES Array of required dependencies.
#
# @return None
# @exit 1 if any dependencies are missing.
#
# @example
# validate_depends debug
# -----------------------------------------------------------------------------
validate_depends() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"

    # Declare local variables
    local missing=0  # Counter for missing dependencies
    local dep        # Iterator for dependencies

    # Iterate through dependencies
    for dep in "${DEPENDENCIES[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            warn "Missing dependency: $dep"
            ((missing++))
            debug_print "Missing dependency: $dep" "$debug"
        else
            debug_print "Found dependency: $dep" "$debug"
        fi
    done

    # Handle missing dependencies
    if ((missing > 0)); then
            debug_end "$debug" # Next line must be a return/print/exit out of function
        die 1 "Missing $missing dependencies. Install them and re-run the script."
    fi

    debug_print "All dependencies are present." "$debug"

    debug_end "$debug" # Next line must be a return/print/exit out of function
    return 0
}

# -----------------------------------------------------------------------------
# @brief Check the availability of critical system files.
# @details Verifies that each file listed in the `SYSTEM_READS` array exists and is readable.
#          Logs an error for any missing or unreadable files and exits the script if any issues are found.
#
# @param $1 [Optional] Debug flag. Pass "debug" to enable debug output.
#
# @global SYSTEM_READS Array of critical system file paths to check.
#
# @return None
# @exit 1 if any required files are missing or unreadable.
#
# @example
# validate_sys_accs debug
# -----------------------------------------------------------------------------
validate_sys_accs() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"

    # Declare local variables
    local missing=0  # Counter for missing or unreadable files
    local file       # Iterator for files

    # Iterate through system files
    for file in "${SYSTEM_READS[@]}"; do
        if [[ ! -r "$file" ]]; then
            warn "Missing or unreadable file: $file"
            ((missing++))
            debug_print "Missing or unreadable file: $file" "$debug"
        else
            debug_print "File is accessible: $file" "$debug"
        fi
    done

    # Handle missing files
    if ((missing > 0)); then
            debug_end "$debug" # Next line must be a return/print/exit out of function
        die 1 "Missing or unreadable $missing critical system files."
    fi

    debug_print "All critical system files are accessible." "$debug"

    debug_end "$debug" # Next line must be a return/print/exit out of function
    return 0
}

# -----------------------------------------------------------------------------
# @brief Validate the existence of required environment variables.
# @details Checks if the environment variables specified in the `ENV_VARS` array
#          are set. Logs any missing variables and exits the script if any are missing.
#
# @param $1 [Optional] Debug flag. Pass "debug" to enable debug output.
#
# @global ENV_VARS Array of required environment variables.
#
# @return None
# @exit 1 if any environment variables are missing.
#
# @example
# validate_env_vars debug
# -----------------------------------------------------------------------------
validate_env_vars() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"

    # Declare local variables
    local missing=0  # Counter for missing environment variables
    local var        # Iterator for environment variables

    # Iterate through environment variables
    for var in "${ENV_VARS[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            printf "ERROR: Missing environment variable: %s\n" "$var" >&2
            ((missing++))
            debug_print "Missing environment variable: $var" "$debug"
        else
            debug_print "Environment variable is set: $var=${!var}" "$debug"
        fi
    done

    # Handle missing variables
    if ((missing > 0)); then
        printf "ERROR: Missing %d required environment variables. Ensure all required environment variables are set and re-run the script.\n" "$missing" >&2
            debug_end "$debug" # Next line must be a return/print/exit out of function
        exit 1
    fi

    debug_end "$debug" # Next line must be a return/print/exit out of function
    return 0
}

# -----------------------------------------------------------------------------
# @brief Check if the script is running in a Bash shell.
# @details Ensures the script is executed with Bash, as it may use Bash-specific features.
#          If the "debug" argument is passed, detailed logging will be displayed for each check.
#
# @param $1 [Optional] "debug" to enable verbose output for all checks.
#
# @global BASH_VERSION The version of the Bash shell being used.
#
# @return None
# @exit 1 if not running in Bash.
#
# @example
# check_bash
# check_bash debug
# -----------------------------------------------------------------------------
check_bash() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"

    # Ensure the script is running in a Bash shell
    if [[ -z "${BASH_VERSION:-}" ]]; then
            debug_end "$debug" # Next line must be a return/print/exit out of function
        die 1 "This script requires Bash. Please run it with Bash."
    fi

    debug_end "$debug" # Next line must be a return/print/exit out of function
    return 0
}

# -----------------------------------------------------------------------------
# @brief Check if the current Bash version meets the minimum required version.
# @details Compares the current Bash version against a required version specified
#          in the global variable `MIN_BASH_VERSION`. If `MIN_BASH_VERSION` is "none",
#          the check is skipped. Outputs debug information if enabled.
#
# @param $1 [Optional] "debug" to enable verbose output for this check.
#
# @global MIN_BASH_VERSION Minimum required Bash version (e.g., "4.0") or "none".
# @global BASH_VERSINFO Array containing the major and minor versions of the running Bash.
#
# @return None
# @exit 1 if the Bash version is insufficient.
#
# @example
# check_sh_ver
# check_sh_ver debug
# -----------------------------------------------------------------------------
check_sh_ver() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"

    local required_version="${MIN_BASH_VERSION:-none}"

    # If MIN_BASH_VERSION is "none", skip version check
    if [[ "$required_version" == "none" ]]; then
        debug_print "Bash version check is disabled (MIN_BASH_VERSION='none')." "$debug"
    else
        debug_print "Minimum required Bash version is set to '$required_version'." "$debug"

        # Extract the major and minor version components from the required version
        local required_major="${required_version%%.*}"
        local required_minor="${required_version#*.}"
        required_minor="${required_minor%%.*}"

        # Log current Bash version for debugging
        debug_print "Current Bash version is ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}." "$debug"

        # Compare the current Bash version with the required version
        if (( BASH_VERSINFO[0] < required_major ||
              (BASH_VERSINFO[0] == required_major && BASH_VERSINFO[1] < required_minor) )); then
                    debug_end "$debug" # Next line must be a return/print/exit out of function
            die 1 "This script requires Bash version $required_version or newer."
        fi
    fi

    debug_end "$debug" # Next line must be a return/print/exit out of function
    return 0
}

# -----------------------------------------------------------------------------
# @brief Check system bitness compatibility.
# @details Validates whether the current system's bitness matches the supported
#          configuration. Outputs debug information if debug mode is enabled.
#
# @param $1 [Optional] "debug" to enable verbose output for the check.
#
# @global SUPPORTED_BITNESS Specifies the bitness supported by the script ("32", "64", or "both").
#
# @return None
# @exit 1 if the system bitness is unsupported.
#
# @example
# check_bitness
# check_bitness debug
# -----------------------------------------------------------------------------
check_bitness() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"

    local bitness  # Stores the detected bitness of the system.

    # Detect the system bitness
    bitness=$(getconf LONG_BIT)

    # Debugging: Detected system bitness
    debug_print "Detected system bitness: $bitness-bit." "$debug"

    case "$SUPPORTED_BITNESS" in
        "32")
            debug_print "Script supports only 32-bit systems." "$debug"
            if [[ "$bitness" -ne 32 ]]; then
                            debug_end "$debug" # Next line must be a return/print/exit out of function
                die 1 "Only 32-bit systems are supported. Detected $bitness-bit system."
            fi
            ;;
        "64")
            debug_print "Script supports only 64-bit systems." "$debug"
            if [[ "$bitness" -ne 64 ]]; then
                            debug_end "$debug" # Next line must be a return/print/exit out of function
                die 1 "Only 64-bit systems are supported. Detected $bitness-bit system."
            fi
            ;;
        "both")
            debug_print "Script supports both 32-bit and 64-bit systems." "$debug"
            ;;
        *)
            debug_print "Invalid SUPPORTED_BITNESS configuration: '$SUPPORTED_BITNESS'." "$debug"
                    debug_end "$debug" # Next line must be a return/print/exit out of function
            die 1 "Configuration error: Invalid value for SUPPORTED_BITNESS ('$SUPPORTED_BITNESS')."
            ;;
    esac

    debug_end "$debug" # Next line must be a return/print/exit out of function
    return 0
}

# -----------------------------------------------------------------------------
# @brief Check Raspbian OS version compatibility.
# @details This function ensures that the Raspbian version is within the supported
#          range and logs an error if the compatibility check fails.
#
# @param $1 [Optional] "debug" to enable verbose output for this check.
#
# @global MIN_OS Minimum supported OS version.
# @global MAX_OS Maximum supported OS version (-1 indicates no upper limit).
# @global log_message Function for logging messages.
# @global die Function to handle critical errors and terminate the script.
#
# @return None Exits the script with an error code if the OS version is incompatible.
#
# @example
# check_release
# check_release debug
# -----------------------------------------------------------------------------
check_release() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"

    local ver  # Holds the extracted version ID from /etc/os-release.

    # Ensure the file exists and is readable.
    if [[ ! -f /etc/os-release || ! -r /etc/os-release ]]; then
        die 1 "Unable to read /etc/os-release. Ensure this script is run on a compatible system."
    fi

    # Extract the VERSION_ID from /etc/os-release.
    if [[ -f /etc/os-release ]]; then
        ver=$(grep "VERSION_ID" /etc/os-release | awk -F "=" '{print $2}' | tr -d '"')
    else
        warn "File /etc/os-release not found."
        ver="unknown"
    fi
    debug_print "Raspbian version '$ver' detected." "$debug"

    # Ensure the extracted version is not empty.
    if [[ -z "${ver:-}" ]]; then
            debug_end "$debug" # Next line must be a return/print/exit out of function
        die 1 "VERSION_ID is missing or empty in /etc/os-release."
    fi

    # Check if the version is older than the minimum supported version.
    if [[ "$ver" -lt "$MIN_OS" ]]; then
            debug_end "$debug" # Next line must be a return/print/exit out of function
        die 1 "Raspbian version $ver is older than the minimum supported version ($MIN_OS)."
    fi

    # Check if the version is newer than the maximum supported version, if applicable.
    if [[ "$MAX_OS" -ne -1 && "$ver" -gt "$MAX_OS" ]]; then
            debug_end "$debug" # Next line must be a return/print/exit out of function
        die 1 "Raspbian version $ver is newer than the maximum supported version ($MAX_OS)."
    fi

    debug_end "$debug" # Next line must be a return/print/exit out of function
    return 0
}

# -----------------------------------------------------------------------------
# @brief Check if the detected Raspberry Pi model is supported.
# @details Reads the Raspberry Pi model from /proc/device-tree/compatible and checks
#          it against a predefined list of supported models. Logs an error if the
#          model is unsupported or cannot be detected. Optionally outputs debug information
#          about all models if `debug` is set to `true`.
#
# @param $1 [Optional] "debug" to enable verbose output for all supported/unsupported models.
#
# @global SUPPORTED_MODELS Associative array of supported and unsupported Raspberry Pi models.
# @global log_message Function for logging messages.
# @global die Function to handle critical errors and terminate the script.
#
# @return None Exits the script with an error code if the architecture is unsupported.
#
# @example
# check_arch
# check_arch debug
# -----------------------------------------------------------------------------
check_arch() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"

    local detected_model is_supported key full_name model chip this_model this_chip

    # Read and process the compatible string
    if ! detected_model=$(cat /proc/device-tree/compatible 2>/dev/null | tr '\0' '\n' | grep "raspberrypi" | sed 's/raspberrypi,//'); then
            debug_end "$debug" # Next line must be a return/print/exit out of function
        die 1 "Failed to read or process /proc/device-tree/compatible. Ensure compatibility."
    fi

    # Check if the detected model is empty
    if [[ -z "${detected_model:-}" ]]; then
            debug_end "$debug" # Next line must be a return/print/exit out of function
        die 1 "No Raspberry Pi model found in /proc/device-tree/compatible. This system may not be supported."
    fi
    debug_print "Detected model: $detected_model" "$debug"

    # Initialize is_supported flag
    is_supported=false

    # Iterate through supported models to check compatibility
    for key in "${!SUPPORTED_MODELS[@]}"; do
        IFS='|' read -r full_name model chip <<< "$key"
        if [[ "$model" == "$detected_model" ]]; then
            if [[ "${SUPPORTED_MODELS[$key]}" == "Supported" ]]; then
                is_supported=true
                this_model="$full_name"
                this_chip="$chip"
                debug_print "Model: '$full_name' ($chip) is supported." "$debug"
            else
                            debug_end "$debug" # Next line must be a return/print/exit out of function
                die 1 "Model: '$full_name' ($chip) is not supported."
            fi
            break
        fi
    done

    # Debug output of all models if requested
    if [[ "$debug" == "debug" ]]; then
        # Arrays to hold supported and unsupported models
        declare -a supported_models=()
        declare -a unsupported_models=()

        # Group the models into supported and unsupported
        for key in "${!SUPPORTED_MODELS[@]}"; do
            IFS='|' read -r full_name model chip <<< "$key"
            if [[ "${SUPPORTED_MODELS[$key]}" == "Supported" ]]; then
                supported_models+=("$full_name ($chip)")
            else
                unsupported_models+=("$full_name ($chip)")
            fi
        done

        # Sort and print supported models
        if [[ ${#supported_models[@]} -gt 0 ]]; then
            printf "[DEBUG] Supported models:\n" >&2
            for model in $(printf "%s\n" "${supported_models[@]}" | sort); do
                printf "\t- %s\n" "$model" >&2
            done
        fi

        # Sort and print unsupported models
        if [[ ${#unsupported_models[@]} -gt 0 ]]; then
            printf "[DEBUG] Unsupported models:\n" >&2
            for model in $(printf "%s\n" "${unsupported_models[@]}" | sort); do
                printf "\t- %s\n" "$model" >&2
            done
        fi
    fi

    # Log an error if no supported model was found
    if [[ "$is_supported" == false ]]; then
            debug_end "$debug" # Next line must be a return/print/exit out of function
        die 1 "Detected Raspberry Pi model '$detected_model' is not recognized or supported."
    fi

    debug_end "$debug" # Next line must be a return/print/exit out of function
    return 0
}

# -----------------------------------------------------------------------------
# @brief Validate proxy connectivity by testing a known URL.
# @details Uses `check_url` to verify connectivity through the provided proxy settings.
#
# @param $1 [Optional] Proxy URL to validate (defaults to `http_proxy` or `https_proxy` if not provided).
# @param $2 [Optional] "debug" to enable verbose output for the proxy validation.
#
# @global http_proxy The HTTP proxy URL (if set).
# @global https_proxy The HTTPS proxy URL (if set).
#
# @return 0 if the proxy is functional, 1 otherwise.
#
# @example
# validate_proxy "http://myproxy.com:8080"
# validate_proxy debug
# -----------------------------------------------------------------------------
validate_proxy() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"

    # Check if proxy_url is passed
    local proxy_url=""
    # Check if proxy_url is the first argument (if set)
    if [[ -n "$1" && "$1" =~ ^https?:// ]]; then
        # First argument is proxy_url
        proxy_url="$1"
        shift  # Move to the next argument
    fi

    # Default to global proxy settings if no proxy is provided
    [[ -z "${proxy_url:-}" ]] && proxy_url="${http_proxy:-$https_proxy}"

    # Validate that a proxy is set
    if [[ -z "${proxy_url:-}" ]]; then
        warn "No proxy URL configured for validation."
            debug_end "$debug" # Next line must be a return/print/exit out of function
        return 1
    fi

    logI "Validating proxy: $proxy_url"

    # Test the proxy connectivity using check_url (passing the debug flag)
    if check_url "$proxy_url" "curl" "--silent --head --max-time 10 --proxy $proxy_url" "$debug"; then
        logI "Proxy $proxy_url is functional."
        debug_print "Proxy $proxy_url is functional." "$debug"
            debug_end "$debug" # Next line must be a return/print/exit out of function
        return 0
    else
        warn "Proxy $proxy_url is unreachable or misconfigured."
        debug_print "Proxy $proxy_url failed validation." "$debug"
            debug_end "$debug" # Next line must be a return/print/exit out of function
        return 1
    fi
}

# -----------------------------------------------------------------------------
# @brief Check connectivity to a URL using a specified tool.
# @details Attempts to connect to a given URL with `curl` or `wget` based on the
#          provided arguments. Ensures that the tool's availability is checked
#          and handles timeouts gracefully. Optionally prints debug information
#          if the "debug" flag is set.
#
# @param $1 The URL to test.
# @param $2 The tool to use for the test (`curl` or `wget`).
# @param $3 Options to pass to the testing tool (e.g., `--silent --head` for `curl`).
# @param $4 [Optional] "debug" to enable verbose output during the check.
#
# @return 0 if the URL is reachable, 1 otherwise.
#
# @example
# check_url "http://example.com" "curl" "--silent --head" debug
# -----------------------------------------------------------------------------
check_url() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"

    local url="$1"
    local tool="$2"
    local options="$3"

    # Validate inputs
    if [[ -z "${url:-}" ]]; then
        printf "ERROR: URL and tool parameters are required for check_url.\n" >&2
            debug_end "$debug" # Next line must be a return/print/exit out of function
        return 1
    fi

    # Check tool availability
    if ! command -v "$tool" &>/dev/null; then
        printf "ERROR: Tool '%s' is not installed or unavailable.\n" "$tool" >&2
            debug_end "$debug" # Next line must be a return/print/exit out of function
        return 1
    fi

    # Perform the connectivity check, allowing SSL and proxy errors
    local retval
    # shellcheck disable=2086
    if $tool $options "$url" &>/dev/null; then
        debug_print "Successfully connected to $#url using $tool." "$debug"
        retval=0
    else
        debug_print "Failed to connect to $url using $tool." "$debug"
        retval=1
    fi

    debug_end "$debug" # Next line must be a return/print/exit out of function
    return 0
}

# -----------------------------------------------------------------------------
# @brief Comprehensive internet and proxy connectivity check.
# @details Combines proxy validation and direct internet connectivity tests
#          using `check_url`. Validates proxy configuration first, then
#          tests connectivity with and without proxies. Outputs debug information if enabled.
#
# @param $1 [Optional] "debug" to enable verbose output for all checks.
#
# @global http_proxy Proxy URL for HTTP (if set).
# @global https_proxy Proxy URL for HTTPS (if set).
# @global no_proxy Proxy exclusions (if set).
#
# @return 0 if all tests pass, 1 if any test fails.
#
# @example
# check_internet debug
# -----------------------------------------------------------------------------
check_internet() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"

    local primary_url="http://google.com"
    local secondary_url="http://1.1.1.1"
    local proxy_valid=false

    # Validate proxy settings
    if [[ -n "${http_proxy:-}" || -n "${https_proxy:-}" ]]; then
        debug_print "Proxy detected. Validating proxy configuration." "$debug"
        if validate_proxy "$debug"; then  # Pass debug flag to validate_proxy
            proxy_valid=true
            debug_print "Proxy validation succeeded." "$debug"
        else
            warn "Proxy validation failed. Proceeding with direct connectivity checks."
        fi
    fi

    # Check connectivity using curl
    if command -v curl &>/dev/null; then
        debug_print "curl is available. Testing internet connectivity using curl." "$debug"

        # Check with proxy
        if $proxy_valid && curl --silent --head --max-time 10 --proxy "${http_proxy:-${https_proxy:-}}" "$primary_url" &>/dev/null; then
            logI "Internet is available using curl with proxy."
            debug_print "curl successfully connected via proxy." "$debug"
                    debug_end "$debug" # Next line must be a return/print/exit out of function
            return 0
        fi

        # Check without proxy
        if curl --silent --head --max-time 10 "$primary_url" &>/dev/null; then
            debug_print "curl successfully connected without proxy." "$debug"
                    debug_end "$debug" # Next line must be a return/print/exit out of function
            return 0
        fi

        debug_print "curl failed to connect." "$debug"
    else
        debug_print "curl is not available." "$debug"
    fi

    # Check connectivity using wget
    if command -v wget &>/dev/null; then
        debug_print "wget is available. Testing internet connectivity using wget." "$debug"

        # Check with proxy
        if $proxy_valid && wget --spider --quiet --timeout=10 --proxy="${http_proxy:-${https_proxy:-}}" "$primary_url" &>/dev/null; then
            logI "Internet is available using wget with proxy."
            debug_print "wget successfully connected via proxy." "$debug"
                    debug_end "$debug" # Next line must be a return/print/exit out of function
            return 0
        fi

        # Check without proxy
        if wget --spider --quiet --timeout=10 "$secondary_url" &>/dev/null; then
            logI "Internet is available using wget without proxy."
            debug_print "wget successfully connected without proxy." "$debug"
                    debug_end "$debug" # Next line must be a return/print/exit out of function
            return 0
        fi

        debug_print "wget failed to connect." "$debug"
    else
        debug_print "wget is not available." "$debug"
    fi

    # Final failure message
    warn "No internet connection detected after all checks."
    debug_print "All internet connectivity tests failed." "$debug"
    debug_end "$debug" # Next line must be a return/print/exit out of function
    return 1
}

############
### Logging Functions
############

# -----------------------------------------------------------------------------
# @brief Log a message with optional details to the console and/or file.
# @details Handles combined logic for logging to console and/or file, supporting
#          optional details. If details are provided, they are logged with an
#          "[EXTENDED]" tag.
#
# @param $1 Timestamp of the log entry.
# @param $2 Log level (e.g., DEBUG, INFO, WARN, ERROR).
# @param $3 Color code for the log level.
# @param $4 Line number where the log entry originated.
# @param $5 The main log message.
# @param $6 [Optional] Additional details for the log entry.
#
# @global LOG_OUTPUT Specifies where to output logs ("console", "file", or "both").
# @global LOG_FILE File path for log storage if `LOG_OUTPUT` includes "file".
# @global THIS_SCRIPT The name of the current script.
# @global RESET ANSI escape code to reset text formatting.
#
# @return None
# -----------------------------------------------------------------------------
print_log_entry() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"

    # Declare local variables at the start of the function
    local timestamp="$1"
    local level="$2"
    local color="$3"
    local lineno="$4"
    local message="$5"

    # Skip logging if the message is empty
    if [[ -z "$message" ]]; then
            debug_end "$debug" # Next line must be a return/print/exit out of function
        return 1
    fi

    # Log to file if required
    if [[ "$LOG_OUTPUT" == "file" || "$LOG_OUTPUT" == "both" ]]; then
        printf "%s [%s] [%s:%d] %s\\n" "$timestamp" "$level" "$THIS_SCRIPT" "$lineno" "$message" >> "$LOG_FILE"
    fi

    # Log to console if required and USE_CONSOLE is true
    if [[ "$USE_CONSOLE" == "true" && ("$LOG_OUTPUT" == "console" || "$LOG_OUTPUT" == "both") ]]; then
        printf "%b[%s] %s%b\\n" "$color" "$level" "$message" "$RESET"
    fi

    debug_end "$debug" # Next line must be a return/print/exit out of function
    return 0
}

# -----------------------------------------------------------------------------
# @brief Generate a timestamp and line number for log entries.
#
# @details This function retrieves the current timestamp and the line number of
#          the calling script. If the optional debug flag is provided, it will
#          print debug information, including the function name, caller's name,
#          and the line number where the function was called.
#
# @param $1 [Optional] Debug flag. Pass "debug" to enable debug output.
#
# @return A pipe-separated string in the format: "timestamp|line_number".
#
# @example
# prepare_log_context "debug"
# -----------------------------------------------------------------------------
prepare_log_context() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"

    local timestamp
    local lineno

    # Generate the current timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")

    # Retrieve the line number of the caller
    lineno="${BASH_LINENO[2]}"

    # Pass debug flag to pad_with_spaces
    lineno=$(pad_with_spaces "$lineno" "$debug") # Pass debug flag

    # Return the pipe-separated timestamp and line number
    printf "%s|%s\n" "$timestamp" "$lineno"

    debug_end "$debug" # Next line must be a return/print/exit out of function
    return 0
}

# -----------------------------------------------------------------------------
# @brief Log a message with the specified log level.
# @details Logs messages to both the console and/or a log file, depending on the
#          configured log output. The function uses the `LOG_PROPERTIES` associative
#          array to determine the log level, color, and severity. If the "debug"
#          argument is provided, debug logging is enabled for additional details.
#
# @param $1 Log level (e.g., DEBUG, INFO, ERROR). The log level controls the message severity.
# @param $2 Main log message to log.
# @param $3 [Optional] Debug flag. Pass "debug" to enable debug output.
#
# @global LOG_LEVEL The current logging verbosity level.
# @global LOG_PROPERTIES Associative array defining log level properties, such as severity and color.
# @global LOG_FILE Path to the log file (if configured).
# @global USE_CONSOLE Boolean flag to enable or disable console output.
# @global LOG_OUTPUT Specifies where to log messages ("file", "console", "both").
#
# @return None
#
# @example
# log_message "INFO" "This is a message"
# log_message "INFO" "This is a message" "debug"
# -----------------------------------------------------------------------------
log_message() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"

    # Ensure the calling function is log_message_with_severity()
    if [[ "${FUNCNAME[1]}" != "log_message_with_severity" ]]; then
        warn "log_message() can only be called from log_message_with_severity()."
            debug_end "$debug" # Next line must be a return/print/exit out of function
        return 1
    fi

    local level="UNSET"          # Default to "UNSET" if no level is provided
    local message="<no message>" # Default to "<no message>" if no message is provided

    local context timestamp lineno custom_level color severity config_severity

    # Get level if it exists (must be one of the predefined values)
    if [[ -n "$1" && "$1" =~ ^(DEBUG|INFO|WARNING|ERROR|CRITICAL|EXTENDED)$ ]]; then
        level="$1"
        shift  # Move to the next argument
    fi

    # Get message if it exists and is not "debug"
    if [[ -n "$1" ]]; then
        message="$1"
        shift  # Move to the next argument
    fi

    # Validate the log level and message if needed
    if [[ "$level" == "UNSET" || -z "${LOG_PROPERTIES[$level]:-}" || "$message" == "<no message>" ]]; then
        warn "Invalid log level '$level' or empty message."
            debug_end "$debug" # Next line must be a return/print/exit out of function
        return 1
    fi

    # Prepare log context (timestamp and line number)
    context=$(prepare_log_context "$debug")  # Pass debug flag to sub-function
    IFS="|" read -r timestamp lineno <<< "$context"

    # Extract log properties for the specified level
    IFS="|" read -r custom_level color severity <<< "${LOG_PROPERTIES[$level]}"

    # Check if all three values (custom_level, color, severity) were successfully parsed
    if [[ -z "$custom_level" || -z "$color" || -z "$severity" ]]; then
        warn "Malformed log properties for level '$level'. Using default values."
        custom_level="UNSET"
        color="$RESET"
        severity=0
    fi

    # Extract severity threshold for the configured log level
    IFS="|" read -r _ _ config_severity <<< "${LOG_PROPERTIES[$LOG_LEVEL]}"

    # Check for valid severity level
    if [[ -z "$config_severity" || ! "$config_severity" =~ ^[0-9]+$ ]]; then
        warn "Malformed severity value for level '$LOG_LEVEL'."
            debug_end "$debug" # Next line must be a return/print/exit out of function
        return 1
    fi

    # Skip logging if the message's severity is below the configured threshold
    if (( severity < config_severity )); then
            debug_end "$debug" # Next line must be a return/print/exit out of function
        return 0
    fi

    # Call print_log_entry to handle actual logging (to file and console)
    print_log_entry "$timestamp" "$custom_level" "$color" "$lineno" "$message" "$debug"

    debug_end "$debug" # Next line must be a return/print/exit out of function
    return 0
}

# -----------------------------------------------------------------------------
# @brief Log a message with the specified severity level.
# @details This function logs messages at the specified severity level and
#          handles extended details and debug information if provided.
#
# @param $1 Severity level (e.g., DEBUG, INFO, WARNING, ERROR, CRITICAL).
# @param $2 Main log message.
# @param $3 [Optional] Extended details for the log entry.
# @param $4 [Optional] Debug flag. Pass "debug" to enable debug output.
#
# @return None
#
# @example
# log_message_with_severity "ERROR" "This is an error message" "Additional details" "debug"
# -----------------------------------------------------------------------------
log_message_with_severity() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"

    # Exit if the calling function is not one of the allowed ones.
    # shellcheck disable=2076
    if [[ ! "logD logI logW logE logC logX" =~ "${FUNCNAME[1]}" ]]; then
        warn "Invalid calling function: ${FUNCNAME[1]}"
            debug_end "$debug" # Next line must be a return/print/exit out of function
        exit 1
    fi

    # Initialize variables
    local severity="$1"   # Level is always passed as the first argument to log_message_with_severity
    local message=""
    local extended_message=""

    # Process arguments
    if [[ -n "$2" ]]; then
        message="$2"
    else
        warn "Message is required."
            debug_end "$debug" # Next line must be a return/print/exit out of function
        exit 1
    fi

    if [[ -n "$3" ]]; then
        extended_message="$3"
    fi

    # Print debug information if the flag is set
    debug_print "Logging message at severity '$severity' with message='$message'." "$debug"
    debug_print "Extended message: '$extended_message'" "$debug"

    # Log the primary message
    log_message "$severity" "$message" "$debug"

    # Log the extended message if present
    if [[ -n "$extended_message" ]]; then
        logX "$extended_message" "$debug"
    fi

    debug_end "$debug" # Next line must be a return/print/exit out of function
    return 0
}

# -----------------------------------------------------------------------------
# @brief Logging wrapper functions for various severity levels.
# @details These functions provide shorthand access to `log_message_with_severity()`
#          with a predefined severity level. They standardize the logging process
#          by ensuring consistent severity labels and argument handling.
#
# @param $1 [string] The primary log message. Must not be empty.
# @param $2 [optional, string] The extended message for additional details (optional), sent to logX.
# @param $3 [optional, string] The debug flag. If set to "debug", enables debug-level logging.
#
# @global None
#
# @return None
#
# @functions
# - logD(): Logs a message with severity level "DEBUG".
# - logI(): Logs a message with severity level "INFO".
# - logW(): Logs a message with severity level "WARNING".
# - logE(): Logs a message with severity level "ERROR".
# - logC(): Logs a message with severity level "CRITICAL".
# - logX(): Logs a message with severity level "EXTENDED".
#
# @example
#   logD "Debugging application startup."
#   logI "Application initialized successfully."
#   logW "Configuration file is missing a recommended value."
#   logE "Failed to connect to the database."
#   logC "System is out of memory and must shut down."
#   logX "Additional debug information for extended analysis."
# -----------------------------------------------------------------------------
# shellcheck disable=2329
logD() { log_message_with_severity "DEBUG" "$1" "${2:-}" "${3:-}"; }
logI() { log_message_with_severity "INFO" "$1" "${2:-}" "${3:-}"; }
logW() { log_message_with_severity "WARNING" "$1" "${2:-}" "${3:-}"; }
logE() { log_message_with_severity "ERROR" "$1" "${2:-}" "${3:-}"; }
# shellcheck disable=2329
logC() { log_message_with_severity "CRITICAL" "$1" "${2:-}" "${3:-}"; }
logX() { log_message_with_severity "EXTENDED" "$1" "${2:-}" "${3:-}"; }

# -----------------------------------------------------------------------------
# @brief Ensure the log file exists and is writable, with fallback to `/tmp` if necessary.
# @details This function validates the specified log file's directory to ensure it exists and is writable.
#          If the directory is invalid or inaccessible, it attempts to create it. If all else fails,
#          the log file is redirected to `/tmp`. A warning message is logged if fallback is used.
#
# @param $1 [Optional] Debug flag. Pass "debug" to enable debug output.
#
# @global LOG_FILE Path to the log file (modifiable to fallback location).
# @global THIS_SCRIPT The name of the script (used to derive fallback log file name).
#
# @return None
#
# @example
# init_log "debug"  # Ensures log file is created and available for writing with debug output.
# -----------------------------------------------------------------------------
init_log() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"

    local scriptname="${THIS_SCRIPT%%.*}"  # Extract script name without extension
    local homepath log_dir fallback_log

    # Get the home directory of the current user
    homepath=$(
        getent passwd "${SUDO_USER:-$(whoami)}" | {
            IFS=':' read -r _ _ _ _ _ homedir _
            printf "%s" "$homedir"
        }
    )

    # Determine the log file location
    LOG_FILE="${LOG_FILE:-$homepath/$scriptname.log}"

    # Extract the log directory from the log file path
    log_dir="${LOG_FILE%/*}"

    # Check if the log directory exists and is writable
    debug_print "Checking if log directory '$log_dir' exists and is writable." "$debug"

    if [[ -d "$log_dir" && -w "$log_dir" ]]; then
        # Attempt to create the log file
        if ! touch "$LOG_FILE" &>/dev/null; then
            warn "Cannot create log file: $LOG_FILE"
            log_dir="/tmp"
        else
            # Change ownership of the log file if possible
            if [[ -n "${SUDO_USER:-}" && "${REQUIRE_SUDO:-true}" == "true" ]]; then
                chown "$SUDO_USER:$SUDO_USER" "$LOG_FILE" &>/dev/null || warn "Failed to set ownership to SUDO_USER: $SUDO_USER"
            else
                chown "$(whoami):$(whoami)" "$LOG_FILE" &>/dev/null || warn "Failed to set ownership to current user: $(whoami)"
            fi
        fi
    else
        log_dir="/tmp"
    fi

    # Fallback to /tmp if the directory is invalid
    if [[ "$log_dir" == "/tmp" ]]; then
        fallback_log="/tmp/$scriptname.log"
        LOG_FILE="$fallback_log"
        debug_print "Falling back to log file in /tmp: $LOG_FILE" "$debug"
        warn "Falling back to log file in /tmp: $LOG_FILE"
    fi

    # Attempt to create the log file in the fallback location
    if ! touch "$LOG_FILE" &>/dev/null; then
            debug_end "$debug" # Next line must be a return/print/exit out of function
        die 1 "Unable to create log file even in fallback location: $LOG_FILE"
    fi

    # Final debug message after successful log file setup
    debug_print "Log file successfully created at: $LOG_FILE" "$debug"

    readonly LOG_FILE
    export LOG_FILE

    debug_end "$debug" # Next line must be a return/print/exit out of function
    return 0
}

# -----------------------------------------------------------------------------
# @brief Retrieve the terminal color code or attribute.
#
# @details This function uses `tput` to retrieve a terminal color code or attribute
#          (e.g., sgr0 for reset, bold for bold text). If the attribute is unsupported
#          by the terminal, it returns an empty string.
#
# @param $1 The terminal color code or attribute to retrieve.
#
# @return The corresponding terminal value or an empty string if unsupported.
# -----------------------------------------------------------------------------
default_color() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"

    tput "$@" 2>/dev/null || printf "\n"  # Fallback to an empty string on error

    debug_end "$debug" # Next line must be a return/print/exit out of function
    return 0
}

# -----------------------------------------------------------------------------
# @brief Execute and combine complex terminal control sequences.
#
# @details This function executes `tput` commands and other shell commands
#          to create complex terminal control sequences. It supports commands
#          like moving the cursor, clearing lines, and resetting attributes.
#
# @param $@ Commands and arguments to evaluate (supports multiple commands).
#
# @return The resulting terminal control sequence or an empty string if unsupported.
# -----------------------------------------------------------------------------
# shellcheck disable=2329
generate_terminal_sequence() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"

    local result
    # Execute the command and capture its output, suppressing errors.
    result=$("$@" 2>/dev/null || printf "\n")
    printf "%s" "$result"

    debug_end "$debug" # Next line must be a return/print/exit out of function
    return 0
}

# -----------------------------------------------------------------------------
# @brief Initialize terminal colors and text formatting.
# @details This function sets up variables for foreground colors, background colors,
#          and text formatting styles. It checks terminal capabilities and provides
#          fallback values for unsupported or non-interactive environments.
#
# @param $1 [Optional] Debug flag. Pass "debug" to enable debug output.
#
# @return None
#
# @example
# init_colors "debug"  # Initializes terminal colors with debug output.
# -----------------------------------------------------------------------------
init_colors() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"

    # General text attributes
    BOLD=$(default_color bold)
    DIM=$(default_color dim)
    SMSO=$(default_color smso)
    RMSO=$(default_color rmso)
    UNDERLINE=$(default_color smul)
    NO_UNDERLINE=$(default_color rmul)
    BLINK=$(default_color blink)
    NO_BLINK=$(default_color sgr0)
    ITALIC=$(default_color sitm)
    NO_ITALIC=$(default_color ritm)
    MOVE_UP=$(default_color cuu1)
    CLEAR_LINE=$(tput el)

    # Foreground colors
    FGBLK=$(default_color setaf 0)
    FGRED=$(default_color setaf 1)
    FGGRN=$(default_color setaf 2)
    FGYLW=$(default_color setaf 3)
    FGGLD=$(default_color setaf 220)
    FGBLU=$(default_color setaf 4)
    FGMAG=$(default_color setaf 5)
    FGCYN=$(default_color setaf 6)
    FGWHT=$(default_color setaf 7)
    FGRST=$(default_color setaf 9)
    FGRST=$(default_color setaf 39)

    # Background colors
    BGBLK=$(default_color setab 0)
    BGRED=$(default_color setab 1)
    BGGRN=$(default_color setab 2)
    BGYLW=$(default_color setab 3)
    BGGLD=$(default_color setab 220)
    [[ -z "$BGGLD" ]] && BGGLD="$BGYLW"  # Fallback to yellow
    BGBLU=$(default_color setab 4)
    BGMAG=$(default_color setab 5)
    BGCYN=$(default_color setab 6)
    BGWHT=$(default_color setab 7)
    BGRST=$(default_color setab 9)

    # Reset all
    RESET=$(default_color sgr0)



    # Set variables as readonly
    # shellcheck disable=2303
    readonly RESET BOLD SMSO RMSO UNDERLINE NO_UNDERLINE
    readonly BLINK NO_BLINK ITALIC NO_ITALIC MOVE_UP CLEAR_LINE
    readonly FGBLK FGRED FGGRN FGYLW FGBLU FGMAG FGCYN FGWHT FGRST FGGLD
    readonly BGBLK BGRED BGGRN BGYLW BGBLU BGMAG BGCYN BGWHT BGRST

    debug_end "$debug" # Next line must be a return/print/exit out of function
    return 0
}

# -----------------------------------------------------------------------------
# @brief Generate a separator string for terminal output.
# @details Creates heavy or light horizontal rules based on terminal width.
#          Optionally outputs debug information if the debug flag is set.
#
# @param $1 Type of rule: "heavy" or "light".
# @param $2 [Optional] Debug flag. Pass "debug" to enable debug output.
#
# @return The generated rule string or error message if an invalid type is provided.
#
# @example
# generate_separator "heavy"
# -----------------------------------------------------------------------------
generate_separator() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"

    # Normalize separator type to lowercase
    local type="${1,,}"
    local width="${COLUMNS:-80}"  # Default to 80 columns if $COLUMNS is not set

    # Validate separator type
    if [[ "$type" != "heavy" && "$type" != "light" ]]; then
        warn "Invalid separator type: '$1'. Must be 'heavy' or 'light'."
            debug_end "$debug" # Next line must be a return/print/exit out of function
        return 1
    fi

    # Generate the separator based on type
    case "$type" in
        heavy)
            # Generate a heavy separator (═)
            printf '═%.0s' $(seq 1 "$width")
            ;;
        light)
            # Generate a light separator (─)
            printf '─%.0s' $(seq 1 "$width")
            ;;
        *)
            # Handle invalid separator type
            warn "Invalid separator type: $type"
                    debug_end "$debug" # Next line must be a return/print/exit out of function
            return 1
            ;;
    esac

    debug_end "$debug" # Next line must be a return/print/exit out of function
    return 0
}

# -----------------------------------------------------------------------------
# @brief Validate the logging configuration, including LOG_LEVEL.
# @details This function checks whether the current LOG_LEVEL is valid. If LOG_LEVEL is not
#          defined in the `LOG_PROPERTIES` associative array, it defaults to "INFO" and
#          displays a warning message.
#
# @param $1 [Optional] Debug flag. Pass "debug" to enable debug output.
#
# @global LOG_LEVEL The current logging verbosity level.
# @global LOG_PROPERTIES Associative array defining log level properties.
#
# @return void
#
# @example
# validate_log_level "debug"  # Enables debug output
# validate_log_level          # No debug output
# -----------------------------------------------------------------------------
validate_log_level() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"

    # Ensure LOG_LEVEL is a valid key in LOG_PROPERTIES
    if [[ -z "${LOG_PROPERTIES[$LOG_LEVEL]:-}" ]]; then
        # Print error message if LOG_LEVEL is invalid
        warn "Invalid LOG_LEVEL '$LOG_LEVEL'. Defaulting to 'INFO'."
        LOG_LEVEL="INFO"  # Default to "INFO"
    fi

    debug_end "$debug" # Next line must be a return/print/exit out of function
    return 0
}

# -----------------------------------------------------------------------------
# @brief Sets up the logging environment for the script.
#
# This function initializes terminal colors, configures the logging environment,
# defines log properties, and validates both the log level and properties.
# It must be called before any logging-related functions.
#
# @details
# - Initializes terminal colors using `init_colors`.
# - Sets up the log file and directory using `init_log`.
# - Defines global log properties (`LOG_PROPERTIES`), including severity levels, colors, and labels.
# - Validates the configured log level and ensures all required log properties are defined.
#
# @note This function should be called once during script initialization.
#
# @param $1 [Optional] Debug flag. Pass "debug" to enable debug output.
#
# @return void
# -----------------------------------------------------------------------------
setup_log() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"

    # Initialize terminal colors
    init_colors "$debug"

    # Initialize logging environment
    init_log "$debug"

    # Define log properties (severity, colors, and labels)
    declare -gA LOG_PROPERTIES=(
        ["DEBUG"]="DEBUG|${FGCYN}|0"
        ["INFO"]="INFO |${FGGRN}|1"
        ["WARNING"]="WARN |${FGGLD}|2"
        ["ERROR"]="ERROR|${FGMAG}|3"
        ["CRITICAL"]="CRIT |${FGRED}|4"
        ["EXTENDED"]="EXTD |${FGBLU}|0"
    )

    # Debug message for log properties initialization
    if [[ "$debug" == "debug" ]]; then
        printf "[DEBUG] Log properties initialized:\n" >&2

        # Iterate through LOG_PROPERTIES to print each level with its color
        for level in DEBUG INFO WARNING ERROR CRITICAL EXTENDED; do
            IFS="|" read -r custom_level color severity <<< "${LOG_PROPERTIES[$level]}"
            printf "[DEBUG] %s: %b%s%b\n" "$level" "$color" "$custom_level" "$RESET" >&2
        done
    fi

    # Validate the log level and log properties
    validate_log_level "$debug"

    debug_end "$debug" # Next line must be a return/print/exit out of function
    return 0
}

# -----------------------------------------------------------------------------
# @brief Toggle the USE_CONSOLE variable on or off.
# @details This function updates the global USE_CONSOLE variable to either "true" (on)
#          or "false" (off) based on the input argument. It also prints debug messages
#          when the debug flag is passed.
#
# @param $1 The desired state: "on" (to enable console logging) or "off" (to disable console logging).
# @param $2 [Optional] Debug flag. Pass "debug" to enable debug output.
#
# @global USE_CONSOLE The flag to control console logging.
#
# @return 0 on success, 1 on invalid input.
# -----------------------------------------------------------------------------
toggle_console_log() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"

    # Declare local variables
    local state="${1,,}"      # Convert input to lowercase for consistency

    # Validate $state
    if [[ "$state" != "on" && "$state" != "off" ]]; then
        warn "Invalid state: '$state'. Must be 'on' or 'off'."
            debug_end "$debug" # Next line must be a return/print/exit out of function
        return 1
    fi

    # Process the desired state
    case "$state" in
        on)
            USE_CONSOLE="true"
            debug_print "Console logging enabled. USE_CONSOLE='$USE_CONSOLE', CONSOLE_STATE='$CONSOLE_STATE'" "$debug"
            ;;
        off)
            USE_CONSOLE="false"
            debug_print "Console logging disabled. USE_CONSOLE='$USE_CONSOLE', CONSOLE_STATE='$CONSOLE_STATE'" "$debug"
            ;;
        *)
            warn "Invalid argument for toggle_console_log: $state"
                    debug_end "$debug" # Next line must be a return/print/exit out of function
            return 1
            ;;
    esac

    debug_end "$debug" # Next line must be a return/print/exit out of function
    return 0
}

############
### Get Project Parameters Functions
############

# -----------------------------------------------------------------------------
# @brief Retrieve the Git owner or organization name from the remote URL.
# @details Attempts to dynamically fetch the Git repository's organization
#          name from the current Git process. If not available, uses the global
#          `$REPO_ORG` if set. If neither is available, returns "unknown".
#          Provides debugging output when the "debug" argument is passed.
#
# @param $1 [Optional] Pass "debug" to enable verbose debugging output.
#
# @global REPO_ORG If set, uses this as the repository organization.
#
# @return Prints the organization name if available, otherwise "unknown".
# @retval 0 Success: the organization name is printed.
# @retval 1 Failure: prints an error message to standard error if the organization cannot be determined.
# -----------------------------------------------------------------------------
get_repo_org() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"

    local repo_org
    local url

    # Attempt to retrieve organization dynamically from local Git environment
    url=$(git config --get remote.origin.url 2>/dev/null)
    if [[ -n "$url" ]]; then
        # Extract the owner or organization name from the Git URL
        repo_org=$(printf "%s" "$url" | sed -E 's#(git@|https://)([^:/]+)[:/]([^/]+)/.*#\3#')
        debug_print "Retrieved organization from local Git remote URL: $repo_org" "$debug"
    else
        warn "No remote origin URL retrieved."
    fi

    # If the organization is still empty, use $REPO_ORG (if set)
    if [[ -z "$repo_org" && -n "$REPO_ORG" ]]; then
        repo_org="$REPO_ORG"
        debug_print "Using global REPO_ORG: $repo_org" "$debug"
    fi

    # If organization is still empty, return "unknown"
    if [[ -z "$repo_org" ]]; then
        debug_print "Unable to determine organization. Returning 'unknown'." "$debug"
        repo_org="unknown"
    fi

    # Output the determined or fallback organization
    printf "%s\n" "$repo_org"

    debug_end "$debug" # Next line must be a return/print/exit out of function
    return 0
}

# -----------------------------------------------------------------------------
# @brief Retrieve the Git project name from the remote URL.
# @details Attempts to dynamically fetch the Git repository's name from the
#          current Git process. If not available, uses the global `$REPO_NAME`
#          if set. If neither is available, returns "unknown". Provides debugging
#          output when the "debug" argument is passed.
#
# @param $1 [Optional] Pass "debug" to enable verbose debugging output.
#
# @global REPO_NAME If set, uses this as the repository name.
#
# @return Prints the repository name if available, otherwise "unknown".
# @retval 0 Success: the repository name is printed.
# @retval 1 Failure: prints an error message to standard error if the repository name cannot be determined.
# -----------------------------------------------------------------------------
get_repo_name() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"

    local repo_name="${REPO_NAME:-}"  # Use existing $REPO_NAME if set
    local url

    # Attempt to retrieve repository name dynamically from Git
    if [[ -z "$repo_name" ]]; then
        url=$(git config --get remote.origin.url 2>/dev/null)
        if [[ -n "$url" ]]; then
            # Extract the repository name and remove the ".git" suffix if present
            repo_name="${url##*/}"        # Remove everything up to the last `/`
            repo_name="${repo_name%.git}" # Remove the `.git` suffix
            debug_print "Retrieved repository name from remote URL: $repo_name" "$debug"
        fi
    fi

    # Use "unknown" if no repository name could be determined
    if [[ -z "$repo_name" ]]; then
        debug_print "Unable to determine repository name. Returning 'unknown'." "$debug"
        repo_name="unknown"
    fi

    # Output the determined or fallback repository name
    printf "%s\n" "$repo_name"

    debug_end "$debug" # Next line must be a return/print/exit out of function
    return 0
}

# -----------------------------------------------------------------------------
# @brief Convert a Git repository name to title case.
# @details Replaces underscores and hyphens with spaces and converts words to
#          title case.  Provides debugging output when the "debug" argument is
#          passed.
#
# @param $1 The Git repository name (e.g., "my_repo-name").
# @param $2 [Optional] Pass "debug" to enable verbose debugging output.
#
# @return The repository name in title case (e.g., "My Repo Name").
# @retval 0 Success: the converted repository name is printed.
# @retval 1 Failure: prints an error message to standard error.
#
# @throws Exits with an error if the repository name is empty.
# -----------------------------------------------------------------------------
repo_to_title_case() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"

    local repo_name="${1:-}"  # Input repository name
    local title_case  # Variable to hold the formatted name

    # Validate input
    if [[ -z "${repo_name:-}" ]]; then
        warn "Repository name cannot be empty."
            debug_end "$debug" # Next line must be a return/print/exit out of function
        return 1
    fi
    debug_print "Received repository name: $repo_name" "$debug"

    # Replace underscores and hyphens with spaces and convert to title case
    title_case=$(printf "%s" "$repo_name" | tr '_-' ' ' | awk '{for (i=1; i<=NF; i++) $i=toupper(substr($i,1,1)) substr($i,2)}1')

    local retval
    if [[ -n "${title_case:-}" ]]; then
        debug_print "onverted repository name to title case: $title_case" "$debug"
        printf "%s\n" "$title_case"
        retval=0
    else
        warn "Failed to convert repository name to title case."
        retval=1
    fi

    debug_end "$debug" # Next line must be a return/print/exit out of function
    return "$retval"
}

# -----------------------------------------------------------------------------
# @brief Retrieve the current Repo branch name or the branch this was detached from.
# @details Attempts to dynamically fetch the branch name from the current Git process.
#          If not available, uses the global `$REPO_BRANCH` if set. If neither is available,
#          returns "unknown". Provides debugging output when the "debug" argument
#          is passed.
#
# @param $1 [Optional] Pass "debug" to enable verbose debugging output.
#
# @global REPO_BRANCH If set, uses this as the current Git branch name.
#
# @return Prints the branch name if available, otherwise "unknown".
# @retval 0 Success: the branch name is printed.
# @retval 1 Failure: prints an error message to standard error if the branch name cannot
#           be determined.
# -----------------------------------------------------------------------------
get_repo_branch() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"

    local branch="${REPO_BRANCH:-}"  # Use existing $REPO_BRANCH if set
    local detached_from

    # Attempt to retrieve branch name dynamically from Git
    if [[ -z "$branch" ]]; then
        branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
        if [[ -n "$branch" && "$branch" != "HEAD" ]]; then
            debug_print "Retrieved branch name from Git: $branch" "$debug"
        elif [[ "$branch" == "HEAD" ]]; then
            # Handle detached HEAD state: attempt to determine the source
            detached_from=$(git reflog show --pretty='%gs' | grep -oE 'checkout: moving from [^ ]+' | head -n 1 | awk '{print $NF}')
            if [[ -n "$detached_from" ]]; then
                branch="$detached_from"
                debug_print "Detached HEAD state. Detached from branch: $branch" "$debug"
            else
                debug_print "Detached HEAD state. Cannot determine the source branch." "$debug"
                branch="unknown"
            fi
        fi
    fi

    # Use "unknown" if no branch name could be determined
    if [[ -z "$branch" ]]; then
        debug_print "Unable to determine Git branch. Returning 'unknown'." "$debug"
        branch="unknown"
    fi

    # Output the determined or fallback branch name
    printf "%s\n" "$branch"

    debug_end "$debug" # Next line must be a return/print/exit out of function
    return 0
}

# -----------------------------------------------------------------------------
# @brief Get the most recent Git tag.
# @details Attempts to dynamically fetch the most recent Git tag from the current
#          Git process. If not available, uses the global `$GIT_TAG` if set. If
#          neither is available, returns "0.0.1". Provides debugging output when
#          the "debug" argument is passed.
#
# @param $1 [Optional] Pass "debug" to enable verbose debugging output.
#
# @global GIT_TAG If set, uses this as the most recent Git tag.
#
# @return Prints the tag name if available, otherwise "0.0.1".
# @retval 0 Success: the tag name is printed.
# -----------------------------------------------------------------------------
get_last_tag() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"

    local tag

    # Attempt to retrieve the tag dynamically from Git
    tag=$(git describe --tags --abbrev=0 2>/dev/null)
    if [[ -n "$tag" ]]; then
        debug_print "Retrieved tag from Git: $tag" "$debug"
    else
        debug_print "No tag obtained from local repo." "$debug"
        # Try using GIT_TAG if it is set
        tag="${GIT_TAG:-}"
        # Fall back to "0.0.1" if both the local tag and GIT_TAG are unset
        if [[ -z "$tag" ]]; then
            tag="0.0.1"
            debug_print "No local tag and GIT_TAG is unset. Using fallback: $tag" "$debug"
        else
            debug_print "Using pre-assigned GIT_TAG: $tag" "$debug"
        fi
    fi

    # Output the tag
    printf "%s\n" "$tag"

    debug_end "$debug" # Next line must be a return/print/exit out of function
    return 0
}

# -----------------------------------------------------------------------------
# @brief Check if a tag follows semantic versioning.
# @details Validates if a given Git tag follows the semantic versioning format
#          (major.minor.patch). Provides debugging output when the "debug" argument
#          is passed.
#
# @param $1 The Git tag to validate.
# @param $2 [Optional] Pass "debug" to enable verbose debugging output.
#
# @return Prints "true" if the tag follows semantic versioning, otherwise "false".
# @retval 0 Success: the validation result is printed.
# @retval 1 Failure: prints an error message to standard error if no tag is provided.
# -----------------------------------------------------------------------------
is_sem_ver() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"

    local tag="${1:-}"

    # Validate input
    if [[ -z "${tag:-}" ]]; then
        warn "Tag cannot be empty."
            debug_end "$debug" # Next line must be a return/print/exit out of function
        return 1
    fi

    debug_print "Validating tag: $tag" "$debug"

    # Check if the tag follows the semantic versioning format
    if [[ "$tag" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        debug_print "Tag $tag follows semantic versioning." "$debug"
        printf "true\n"
    else
        debug_print "Tag $tag does not follow semantic versioning." "$debug"
        printf "false\n"
    fi

    debug_end "$debug" # Next line must be a return/print/exit out of function
    return 0
}

# -----------------------------------------------------------------------------
# @brief Get the number of commits since the last tag.
# @details Counts commits since the provided Git tag using `git rev-list`. If
#          no tag is found, defaults to `0` commits. Debug messages are sent
#          only to `stderr`.
#
# @param $1 The Git tag to count commits from.
# @param $2 [Optional] Pass "debug" to enable verbose debugging output.
#
# @return The number of commits since the tag, or 0 if the tag does not exist.
# -----------------------------------------------------------------------------
get_num_commits() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"

    local tag="${1:-}"

    if [[ -z "$tag" || "$tag" == "0.0.1" ]]; then
        debug_print "No valid tag provided. Assuming 0 commits." "$debug"
        printf "0\n"
            debug_end "$debug" # Next line must be a return/print/exit out of function
        return 1
    fi

    local commit_count
    commit_count=$(git rev-list --count "${tag}..HEAD" 2>/dev/null || echo 0)

    printf "%s\n" "$commit_count"

    debug_end "$debug" # Next line must be a return/print/exit out of function
    return 0
}

# -----------------------------------------------------------------------------
# @brief Get the short hash of the current Git commit.
# @details Retrieves the short hash of the current Git commit. Provides debugging
#          output when the "debug" argument is passed.
#
# @param $1 [Optional] Pass "debug" to enable verbose debugging output.
#
# @return Prints the short hash of the current Git commit.
# @retval 0 Success: the short hash is printed.
# @retval 1 Failure: prints an error message to standard error if unable to retrieve the hash.
# -----------------------------------------------------------------------------
get_short_hash() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"

    local short_hash
    short_hash=$(git rev-parse --short HEAD 2>/dev/null)
    if [[ -z "$short_hash" ]]; then
        debug_print "No short hash available. Using 'unknown'." "$debug"
        short_hash="unknown"
    else
        debug_print "Short hash of the current commit: $short_hash." "$debug"
    fi

    printf "%s\n" "$short_hash"

    debug_end "$debug" # Next line must be a return/print/exit out of function
    return 0
}

# -----------------------------------------------------------------------------
# @brief Check if there are uncommitted changes in the working directory.
# @details Checks for uncommitted changes in the current Git repository.
#          Provides debugging output when the "debug" argument is passed.
#
# @param $1 [Optional] Pass "debug" to enable verbose debugging output.
#
# @return Prints "true" if there are uncommitted changes, otherwise "false".
# @retval 0 Success: the dirty state is printed.
# @retval 1 Failure: prints an error message to standard error if unable to determine the repository state.
# -----------------------------------------------------------------------------
get_dirty() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"

    local changes

    # Check for uncommitted changes in the repository
    changes=$(git status --porcelain 2>/dev/null)

    if [[ -n "${changes:-}" ]]; then
        printf "true\n"
    else

        printf "false\n"
    fi

    if [[ -n "$changes" ]]; then
        debug_print "Changes detected." "$debug"
    else
        debug_print "No changes detected." "$debug"
    fi

    debug_end "$debug" # Next line must be a return/print/exit out of function
    return 0
}

# -----------------------------------------------------------------------------
# @brief Generate a version string based on the state of the Git repository.
# @details Constructs a semantic version string using the most recent Git tag,
#          current branch name, number of commits since the tag, the short hash
#          of the latest commit, and whether the working directory is dirty.
#          Provides debugging output when the "debug" argument is passed.
#
# @param $1 [Optional] Pass "debug" to enable verbose debugging output.
#
# @return Prints the generated semantic version string.
# @retval 0 Success: the semantic version string is printed.
# @retval 1 Failure: prints an error message to standard error if any required
#         Git information cannot be determined.
# -----------------------------------------------------------------------------
get_sem_ver() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"

    local tag branch_name num_commits short_hash dirty version_string

    # Retrieve the most recent tag
    tag=$(get_last_tag "$debug")
    debug_print "Received tag: $tag from get_last_tag()." "$debug"
    if [[ -z "$tag" || "$tag" == "0.0.1" ]]; then
        debug_print "No semantic version tag found (or version is 0.0.1). Using default: 0.0.1" "$debug"
        version_string="0.0.1"
    else
        version_string="$tag"
    fi

    # Append branch name
    branch_name=$(get_repo_branch "$debug")
    version_string="$version_string-$branch_name"
    debug_print "Appended branch name to version: $branch_name" "$debug"

    # Append number of commits since the last tag
    num_commits=$(get_num_commits "$tag" "$debug")
    if [[ "$num_commits" -gt 0 ]]; then
        version_string="$version_string+$num_commits"
        debug_print "Appended commit count '$num_commits' to version." "$debug"
    fi

    # Append short hash of the current commit
    short_hash=$(get_short_hash "$debug")
    version_string="$version_string.$short_hash"
    debug_print "Appended short hash '$short_hash' to version." "$debug"

    # Check if the repository is dirty
    dirty=$(get_dirty "$debug")
    if [[ "$dirty" == "true" ]]; then
        version_string="$version_string-dirty"
        debug_print "Repository is dirty. Appended '-dirty' to version." "$debug"
    fi

    printf "%s\n" "$version_string"

    debug_end "$debug" # Next line must be a return/print/exit out of function
    return 0
}

# -----------------------------------------------------------------------------
# @brief Configure local or remote mode based on the Git repository context.
# @details Sets relevant variables for local mode if `USE_LOCAL` is `true` and
#          the script is being executed from within a GitHub repository
#          (`IS_REPO` is `true`). Defaults to remote configuration if not
#          in local mode or when the combined check fails.
#
# @param $1 [Optional] Pass "debug" to enable verbose debugging output.
#
# @global USE_LOCAL           Indicates whether local mode is enabled.
# @global IS_REPO      Indicates whether the script resides in a GitHub repository.
# @global THIS_SCRIPT         Name of the current script.
# @global REPO_ORG            Git organization or owner name.
# @global REPO_NAME           Git repository name.
# @global REPO_BRANCH            Current Git branch name.
# @global GIT_TAG             Generated semantic version string.
# @global LOCAL_REPO_DIR    Path to the root of the local repository.
# @global LOCAL_WWW_DIR       Path to the `data` directory in the repository.
# @global LOCAL_SCRIPTS_DIR   Path to the `scripts` directory in the repository.
# @global GIT_RAW             URL for accessing raw files remotely.
# @global GIT_API             URL for accessing the repository API.
#
# @throws Exits with a critical error if the combined check fails in local mode.
#
# @return None
# -----------------------------------------------------------------------------
get_proj_params() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"

    if [[ "$USE_LOCAL" == "true" && "$IS_REPO" == "true" ]]; then
        debug_print "Configuring local mode with GitHub repository context." "$debug"

        # Making sure THIS_SCRIPT is right
        THIS_SCRIPT=$(basename "$0")
        debug_print "THIS_SCRIPT set to: $THIS_SCRIPT" "$debug"

        # Retrieve repository details
        REPO_ORG=$(get_repo_org "${debug}")
        if [[ $? -ne 0 ]]; then
                    debug_end "$debug" # Next line must be a return/print/exit out of function
            die 1 "Failed to retrieve repository organization."
        fi
        debug_print "REPO_ORG set to: $REPO_ORG" "$debug"

        REPO_NAME=$(get_repo_name "${debug}")
        if [[ $? -ne 0 ]]; then
                    debug_end "$debug" # Next line must be a return/print/exit out of function
            die 1 "Failed to retrieve repository name."
        fi
        debug_print "REPO_NAME set to: $REPO_NAME" "$debug"

        REPO_BRANCH=$(get_repo_branch "${debug}")
        if [[ $? -ne 0 ]]; then
                    debug_end "$debug" # Next line must be a return/print/exit out of function
            die 1 "Failed to retrieve respository branch."
        fi
        debug_print "REPO_BRANCH set to: $REPO_BRANCH" "$debug"

        GIT_TAG=$(get_last_tag "${debug}")
        if [[ $? -ne 0 ]]; then
                    debug_end "$debug" # Next line must be a return/print/exit out of function
            die 1 "Failed to retrieve last tag."
        fi
        debug_print "GIT_TAG set to: $GIT_TAG" "$debug"

        SEM_VER=$(get_sem_ver "${debug}")
        if [[ $? -ne 0 ]]; then
                    debug_end "$debug" # Next line must be a return/print/exit out of function
            die 1 "Failed to retrieve semantic version."
        fi
        debug_print "SEM_VER set to: $SEM_VER" "$debug"

        # Get the root directory of the repository
        LOCAL_REPO_DIR=$(git rev-parse --show-toplevel 2>/dev/null)
        if [[ -z "${LOCAL_REPO_DIR:-}" ]]; then
                    debug_end "$debug" # Next line must be a return/print/exit out of function`
            die 1 "Not inside a valid Git repository. Ensure the repository is properly initialized."
        fi
        debug_print "LOCAL_REPO_DIR set to: $LOCAL_REPO_DIR" "$debug"

        # Set local script path based on repository structure
        LOCAL_WWW_DIR="$LOCAL_REPO_DIR/data"
        if [[ -d "${LOCAL_WWW_DIR:-}" ]]; then
                    debug_end "$debug" # Next line must be a return/print/exit out of function`
            die 1 "HTML source directory does not exist."
        fi
        debug_print "LOCAL_WWW_DIR set to: $LOCAL_WWW_DIR" "$debug"

        # Set local script path based on repository structure
        LOCAL_SCRIPTS_DIR="$LOCAL_REPO_DIR/scripts"
        if [[ -d "${LOCAL_WWW_DIR:-}" ]]; then
                    debug_end "$debug" # Next line must be a return/print/exit out of function
            die 1 "Scripts source directory does not exist."
        fi
        debug_print "LOCAL_SCRIPTS_DIR set to: $LOCAL_SCRIPTS_DIR" "$debug"
    else
        # Configure remote access URLs
        debug_print "Configuring remote mode." "$debug"
        if [[ -z "${REPO_ORG:-}" || -z "${REPO_NAME:-}" ]]; then
                    debug_end "$debug" # Next line must be a return/print/exit out of function
            die 1 "Remote mode requires REPO_ORG and REPO_NAME to be set."
        fi

        # Get GitHub URLs
        GIT_RAW="https://raw.githubusercontent.com/$REPO_ORG/$REPO_NAME"
        GIT_API="https://api.github.com/repos/$REPO_ORG/$REPO_NAME"
        GIT_CLONE="https://github.com/$REPO_ORG/$REPO_NAME.git"
        debug_print "GIT_RAW set to: $GIT_RAW" "$debug"
        debug_print "GIT_API set to: $GIT_API" "$debug"
        debug_print "GIT_CLONE set to: $GIT_CLONE" "$debug"
    fi

    # Export global variables for further use
    export THIS_SCRIPT REPO_ORG REPO_NAME REPO_BRANCH GIT_TAG LOCAL_REPO_DIR
    export LOCAL_WWW_DIR LOCAL_SCRIPTS_DIR GIT_RAW GIT_API

    debug_end "$debug" # Next line must be a return/print/exit out of function
    return 0
}


############
### Git Functions
############

# -----------------------------------------------------------------------------
# @brief Downloads a single file from a Git repository's raw URL.
# @details Fetches a file from the raw content URL of the repository and saves
#          it to the specified local directory. Ensures the destination
#          directory exists before downloading.
#
# @param $1 The relative path of the file in the repository.
# @param $2 The local destination directory where the file will be saved.
#
# @global GIT_RAW The base URL for raw content access in the Git repository.
# @global REPO_BRANCH The branch name from which the file will be fetched.
#
# @throws Logs an error and returns non-zero if the file download fails.
#
# @return None. Downloads the file to the specified directory.
#
# @example
# download_file "path/to/file.txt" "/local/dir"
# -----------------------------------------------------------------------------
download_file() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"
    local file_path="$1"
    local dest_dir="$2"

    mkdir -p "$dest_dir"

    local file_name
    file_name=$(basename "$file_path")
    file_name="${file_name//\'/}"

    logI "Downloading from: $GIT_RAW/$REPO_BRANCH/$file_path to $dest_dir/$file_name"

    wget -q -O "$dest_dir/$file_name" "$GIT_RAW/$REPO_BRANCH/$file_path" || {
        warn "Failed to download file: $file_path to $dest_dir/$file_name"
        return 1
    }

    local dest_file="$dest_dir/$file_name"
    mv "$dest_file" "${dest_file//\'/}"
    debug_end "$debug" # Next line must be a return/print/exit out of function
    return
}

# -----------------------------------------------------------------------------
# @brief Clones a GitHub repository to the specified local destination.
# @details This function clones the repository from the provided Git URL to the
#          specified local destination directory.
#
# @global GIT_CLONE The base URL for cloning the GitHub repository.
# @global USER_HOME The home directory of the user, used as the base for storing files.
# @global REPO_NAME The name of the repository to clone.
#
# @throws Logs an error and returns non-zero if the repository cloning fails.
#
# @return None. Clones the repository into the local destination.
#
# @example
# git_clone
# -----------------------------------------------------------------------------
git_clone() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"
    local dest_root="$USER_HOME/$REPO_NAME"
    mkdir -p "$dest_root"

    logI "Cloning repository from $GIT_CLONE to $dest_root"
    git clone "$GIT_CLONE" "$dest_root" || {
        warn "Failed to clone repository: $GIT_CLONE to $dest_root"
        return 1
    }

    logI "Repository cloned successfully to $dest_root"
    debug_end "$debug" # Next line must be a return/print/exit out of function
    return
}

# -----------------------------------------------------------------------------
# @brief Fetches the Git tree of a specified branch from a repository.
# @details Retrieves the SHA of the specified branch and then fetches the
#          complete tree structure of the repository, allowing recursive access
#          to all files and directories.
#
# @global GIT_API The base URL for the GitHub API, pointing to the repository.
# @global REPO_BRANCH The branch name to fetch the tree from.
#
# @throws Prints an error message and exits if the branch SHA cannot be fetched.
#
# @return Outputs the JSON representation of the repository tree.
#
# @example
# fetch_tree
# -----------------------------------------------------------------------------
fetch_tree() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"
    local branch_sha
    branch_sha=$(curl -s "$GIT_API/git/ref/heads/$REPO_BRANCH" | jq -r '.object.sha')

    if [[ -z "$branch_sha" || "$branch_sha" == "null" ]]; then
        warn "Failed to fetch branch SHA for branch: $REPO_BRANCH. Check repository details or API access."
        return 1
    fi

    curl -s "$GIT_API/git/trees/$branch_sha?recursive=1"
    debug_end "$debug" # Next line must be a return/print/exit out of function
    return
}

# -----------------------------------------------------------------------------
# @brief Downloads files from specified directories in a repository.
# @details This function retrieves a repository tree, identifies files within
#          specified directories, and downloads them to the local system.
#
# @param $1 The target directory to update.
#
# @global USER_HOME The home directory of the user, used as the base for storing files.
# @global GIT_DIRS Array of directories in the repository to process.
#
# @throws Exits the script with an error if the repository tree cannot be fetched.
#
# @return Downloads files to the specified directory structure under $USER_HOME/apppop.
#
# @example
# download_files_in_directories
# -----------------------------------------------------------------------------
download_files_in_directories() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"
    local dest_root="$USER_HOME/$REPO_NAME"
    logI "Fetching repository tree."
    local tree=$(fetch_tree)

    if [[ $(printf "%s" "$tree" | jq '.tree | length') -eq 0 ]]; then
        die 1 "Failed to fetch repository tree. Check repository details or ensure it is public."
    fi

    for dir in "${GIT_DIRS[@]}"; do
        logI "Processing directory: $dir"

        local files
        files=$(printf "%s" "$tree" | jq -r --arg TARGET_DIR "$dir/" \
            '.tree[] | select(.type=="blob" and (.path | startswith($TARGET_DIR))) | .path')

        if [[ -z "$files" ]]; then
            logI "No files found in directory: $dir"
            continue
        fi

        local dest_dir="$dest_root/$dir"
        mkdir -p "$dest_dir"

        printf "%s\n" "$files" | while read -r file; do
            logI "Downloading: $file"
            download_file "$file" "$dest_dir"
        done

        logI "Files from $dir downloaded to: $dest_dir"
    done

    debug_end "$debug" # Next line must be a return/print/exit out of function
    logI "Files saved in: $dest_root"
}

############
### Common Install Functions
############

# -----------------------------------------------------------------------------
# @brief Start the script, with optional timeout for non-interactive environments.
# @details Allows users to press a key to proceed, or defaults after 10 seconds.
#          If the debug flag is provided, additional information about the process
#          will be printed.
#
# @param $1 [Optional] Debug flag to enable detailed output (true/false).
#
# @global TERSE Indicates terse mode (skips interactive messages).
# @global REPO_NAME The name of the repository being installed.
#
# @return None
#
# @example
# start_script debug
# -----------------------------------------------------------------------------
start_script() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"

    # Check terse mode
    if [[ "${TERSE:-false}" == "true" ]]; then
        logI "$(repo_to_title_case "${REPO_NAME:-Unknown}") installation beginning."
        debug_print "Skipping interactive message due to terse mode." "$debug"
            debug_end "$debug" # Next line must be a return/print/exit out of function
        return 0
    fi

    # Prompt user for input
    printf "\nStarting installation for: %s.\n" "$(repo_to_title_case "${REPO_NAME:-Unknown}")"
    printf "Press any key to continue or 'Q' to quit (defaulting in 10 seconds).\n"

    # Read a single key with a 10-second timeout
    if ! read -n 1 -sr -t 10 key < /dev/tty; then
        key=""  # Assign a default value on timeout
    fi
    printf "\n"

    # Handle user input
    case "${key}" in
        [Qq])  # Quit
            debug_print "Quit key pressed. Ending installation." "$debug"
            logI "Installation canceled by user."
            exit_script "Script canceled" "$debug"
            ;;
        "")  # Timeout or Enter
            debug_print "No key pressed, proceeding with installation." "$debug"
            ;;
        *)  # Any other key
            debug_print "Key pressed: '$key'. Proceeding with installation." "$debug"
            ;;
    esac

    debug_end "$debug" # Next line must be a return/print/exit out of function
    return 0
}

# -----------------------------------------------------------------------------
# @brief Sets the system timezone interactively or logs if already set.
# @details If the current timezone is not GMT or BST, logs the current date and time,
#          and exits. Otherwise, prompts the user to confirm or reconfigure the timezone.
#          If the debug flag is passed, additional information about the process is logged.
#
# @param $1 [Optional] Debug flag. Pass "debug" to enable detailed output.
#
# @global TERSE Indicates terse mode (skips interactive messages).
#
# @return None Logs the current timezone or adjusts it if necessary.
#
# @example
# set_time debug
# -----------------------------------------------------------------------------
set_time() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"

    # Declare local variables
    local need_set=false
    local current_date tz yn

    # Get the current date and time
    current_date="$(date)"
    tz="$(date +%Z)"

    # Log and return if the timezone is not GMT or BST
    if [ "$tz" != "GMT" ] && [ "$tz" != "BST" ]; then
        need_set=true
        debug_print "Timezone '$tz' is neither GMT nor BST" "$debug"
            debug_end "$debug" # Next line must be a return/print/exit out of function
        return 0
    fi

    # Check if the script is in terse mode
    if [[ "$TERSE" == "true" && "$need_set" == "true" ]]; then
        logW "Timezone detected as $tz, which may need to be updated."
            debug_end "$debug" # Next line must be a return/print/exit out of function
        return 1
    else
        logI "Timezone detected as $tz."
    fi

    # Inform the user about the current date and time
    logI "Timezone detected as $tz, which may need to be updated."

    # Prompt for confirmation or reconfiguration
    while true; do
        read -rp "Is this correct? [y/N]: " yn < /dev/tty
        case "$yn" in
            [Yy]*)
                logI "Timezone confirmed on $current_date"
                debug_print "Timezone confirmed: $current_date" "$debug"
                break
                ;;
            [Nn]* | *)
                dpkg-reconfigure tzdata
                logI "Timezone reconfigured on $current_date"
                debug_print "Timezone reconfigured: $current_date" "$debug"
                break
                ;;
        esac
    done

    debug_end "$debug" # Next line must be a return/print/exit out of function
    return 0
}

# -----------------------------------------------------------------------------
# @brief Execute a new shell operation (departs this script).
# @details Executes or simulates a shell command based on the DRY_RUN flag.
#          Supports optional debugging to trace the execution process.
#
# @param $1 Name of the operation or process (for reference in logs).
# @param $2 The shell command to execute.
# @param $3 Optional debug flag ("debug" to enable debug output).
#
# @global FUNCNAME Used to fetch the current and caller function names.
# @global BASH_LINENO Used to fetch the calling line number.
# @global DRY_RUN When set, simulates command execution instead of running it.
#
# @throws Exits with a non-zero status if the command execution fails.
#
# @return None.
#
# @example
# DRY_RUN=true exec_new_shell "ListFiles" "ls -l" "debug"
# -----------------------------------------------------------------------------
exec_new_shell() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"

    local exec_name="${1:-Unnamed Operation}"
    local exec_process="${2:-true}"

    # Debug information
    debug_print "exec_name: $exec_name" "$debug"
    debug_print " exec_process: $exec_process" "$debug"

    # Simulate command execution if DRY_RUN is enabled
    if [[ -n "$DRY_RUN" ]]; then
        printf "[✔] Simulating: '%s'.\n" "$exec_process"
            debug_end "$debug" # Next line must be a return/print/exit out of function
        exit_script 0 "$debug"
    fi

    # Validate the command
    if [[ "$exec_process" == "true" || "$exec_process" == "" ]]; then
        printf "[✔] Running: '%s'.\n" "$exec_process"
            debug_end "$debug" # Next line must be a return/print/exit out of function
        exec true
    elif ! command -v "${exec_process%% *}" >/dev/null 2>&1; then
        warn "'$exec_process' is not a valid command or executable."
            debug_end "$debug" # Next line must be a return/print/exit out of function
        die 1 "Invalid command: '$exec_process'"
    else
        # Execute the actual command
        printf "[✔] Running: '%s'.\n" "$exec_process"
        debug_print "Executing command: '$exec_process' in function '$func_name()' at line ${LINENO}." "$debug"
        exec $exec_process || die 1 "Command '${exec_process}' failed"
    fi

    debug_end "$debug" # Next line must be a return/print/exit out of function
    return 0
}

# -----------------------------------------------------------------------------
# @brief Executes a command in a separate Bash process.
# @details This function manages the execution of a shell command, handling
#          the display of status messages. It supports dry-run mode, where
#          the command is simulated without execution. The function prints
#          success or failure messages and handles the removal of the "Running"
#          line once the command finishes.
#
# @param exec_name The name of the command or task being executed.
# @param exec_process The command string to be executed.
# @param debug Optional flag to enable debug messages. Set to "debug" to enable.
#
# @return Returns 0 if the command was successful, non-zero otherwise.
#
# @note The function supports dry-run mode, controlled by the DRY_RUN variable.
#       When DRY_RUN is true, the command is only simulated without actual execution.
#
# @example
# exec_command "Test Command" "echo Hello World" "debug"
# -----------------------------------------------------------------------------
exec_command() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"

    local exec_name="$1"
    local exec_process="$2"

    # Debug information
    debug_print "exec_name: $exec_name" "$debug"
    debug_print "exec_process: $exec_process" "$debug"

    # Basic status prefixes
    local running_pre="Running"
    local complete_pre="Complete"
    local failed_pre="Failed"

    # If DRY_RUN is enabled, show that in the prefix
    if [[ "$DRY_RUN" == "true" ]]; then
        running_pre+=" (dry)"
        complete_pre+=" (dry)"
        failed_pre+=" (dry)"
    fi
    running_pre+=":"
    complete_pre+=":"
    failed_pre+=":"

    # 1) Print ephemeral “Running” line
    printf "%b[-]%b %s %s\n" "${FGGLD}" "${RESET}" "$running_pre" "$exec_name"
    # Optionally ensure it shows up (especially if the command is super fast):
    sleep 0.02

    # 2) If DRY_RUN == "true", skip real exec
    if [[ "$DRY_RUN" == "true" ]]; then
        # Move up & clear ephemeral line
        printf "%b%b" "$MOVE_UP" "$CLEAR_LINE"
        printf "%b[✔]%b %s %s.\n" "${FGGRN}" "${RESET}" "$complete_pre" "$exec_name"
            debug_end "$debug" # Next line must be a return/print/exit out of function
        return 0
    fi

    # 3) Actually run the command (stdout/stderr handling is up to you):
    bash -c "$exec_process" &>/dev/null
    local status=$?

    # 4) Move up & clear ephemeral “Running” line
    printf "%b%b" "$MOVE_UP" "$CLEAR_LINE"

    # 5) Print final success/fail
    if [[ $status -eq 0 ]]; then
        printf "%b[✔]%b %s %s.\n" "${FGGRN}" "${RESET}" "$complete_pre" "$exec_name"
    else
        printf "%b[✘]%b %s %s.\n" "${FGRED}" "${RESET}" "$failed_pre" "$exec_name"
        # If specifically “command not found” exit code:
        if [[ $status -eq 127 ]]; then
            warn "Command not found: $exec_process"
        else
            warn "Command failed with status $status: $exec_process"
        fi
    fi

    debug_end "$debug" # Next line must be a return/print/exit out of function
    return $status
}

# -----------------------------------------------------------------------------
# @brief Installs or upgrades all packages in the APT_PACKAGES list.
# @details Updates the package list and resolves broken dependencies before proceeding.
#          Accumulates errors for each failed package and logs a summary at the end.
#          Skips execution if the APT_PACKAGES array is empty.
#
# @param $1 [Optional] Debug flag. Pass "debug" to enable detailed output.
#
# @global APT_PACKAGES List of packages to install or upgrade.
#
# @return 0 if all operations succeed, 1 if any operation fails.
#
# @example
# handle_apt_packages debug
# -----------------------------------------------------------------------------
handle_apt_packages() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"

    # Check if APT_PACKAGES is empty
    if [[ ${#APT_PACKAGES[@]} -eq 0 ]]; then
        logI "No packages specified in APT_PACKAGES. Skipping package handling."
        debug_print "APT_PACKAGES is empty, skipping execution." "$debug"
            debug_end "$debug" # Next line must be a return/print/exit out of function
        return 0
    fi

    local package error_count=0  # Counter for failed operations

    logI "Updating and managing required packages (this may take a few minutes)."

    # Update package list and fix broken installs
    if ! exec_command "Update local package index" "sudo apt-get update -y" "$debug"; then
        warn "Failed to update package list."
        ((error_count++))
    fi
    if ! exec_command "Fixing broken or incomplete package installations" "sudo apt-get install -f -y" "$debug"; then
        warn "Failed to fix broken installs."
        ((error_count++))
    fi

    # Install or upgrade each package in the list
    for package in "${APT_PACKAGES[@]}"; do
        if dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q "install ok installed"; then
            if ! exec_command "Upgrade $package" "sudo apt-get install --only-upgrade -y $package"; then
                warn "Failed to upgrade package: $package."
                ((error_count++))
            fi
        else
            if ! exec_command "Install $package" "sudo apt-get install -y $package"; then
                warn "Failed to install package: $package."
                ((error_count++))
            fi
        fi
    done

    # Log summary of errors
    if ((error_count > 0)); then
        warn "APT package handling completed with $error_count errors."
        debug_print "APT package handling completed with $error_count errors." "$debug"
    else
        logI "APT package handling completed successfully."
        debug_print "APT package handling completed successfully." "$debug"
    fi

    debug_end "$debug" # Next line must be a return/print/exit out of function
    return $error_count
}

# -----------------------------------------------------------------------------
# @brief End the script with optional feedback based on logging configuration.
# @details Provides a clear message to indicate the script completed successfully.
#          If the debug flag is passed, additional debug information will be logged.
#
# @param $1 [Optional] Debug flag. Pass "debug" to enable debug output.
#
# @global REBOOT Indicates if a reboot is required.
# @global USE_CONSOLE Controls whether console output is enabled.
#
# @return None
#
# @example
# finish_script debug
# -----------------------------------------------------------------------------
finish_script() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"

    if [[ "$TERSE" == "true" || "$TERSE" != "true" ]]; then
        logI "Installation complete: $(repo_to_title_case "$REPO_NAME")."
        debug_print "Installation complete message logged." "$debug"
    fi

    # Clear screen (optional if required)
    if [[ "$TERSE" == "true" ]]; then
        # clear
        printf "Installation complete: %s.\n" "$(repo_to_title_case "$REPO_NAME")"
    fi

    debug_end "$debug" # Next line must be a return/print/exit out of function
    return 0
}

# -----------------------------------------------------------------------------
# @brief Exit the script gracefully.
# @details Logs a provided exit message or uses a default message and exits with
#          a status code of 0. If the debug flag is set to "debug," it outputs
#          additional debug information.
#
# @param $1 [Optional] Exit code
# @param $2 [Optional] Message to log before exiting. Defaults to "Exiting."
# @param $2 [Optional] Debug flag. Pass "debug" to enable debug output.
#
# @return None
#
# @example
# exit_script "Finished processing successfully." debug
# -----------------------------------------------------------------------------
exit_script() {
    local debug=$(debug_start "$@")     # Debug declarations, must be first line

    # Local variables
    local exit_status="${1:-}"          # First parameter as exit status
    local message                       # Main error message
    local details                       # Additional details
    local lineno="${BASH_LINENO[0]}"    # Line number where the exit was called
    lineno=$(pad_with_spaces "$lineno") # Pad line number with spaces for consistency

    # Determine exit status and message
    if ! [[ "$exit_status" =~ ^[0-9]+$ ]]; then
        exit_status=1
        message="${1:-}"
        shift
    else
        shift
        message="${1:-Exiting script.}"
        shift
    fi

    local message="${1:-}"
    if [[ -z "$message" ]]; then
        message="Exiting"
    else
        message="$1"
    fi

    message=$(remove_dot "$message")
    printf "[EXIT ] %s at line %s status: (%d).\n" "$message" "$lineno" "$exit_status" # Log the provided or default message

    debug_end "$debug" # Next line must be a return/print/exit out of function
    exit 0
}

############
### Menu Functions Here
############

# -----------------------------------------------------------------------------
# @var MENU_ITEMS
# @brief Stores menu item details.
# @details Keys are unique identifiers for menu items, and values are formatted
#          strings containing display names and the corresponding function to call.
# -----------------------------------------------------------------------------
MENU_ITEMS["option_one"]="Option One"
MENU_ITEMS["option_two"]="Option Two"
MENU_ITEMS["option_three"]="Option Three"
MENU_ITEMS["display_sub_menu"]="Display Sub Menu"
MENU_ITEMS["display_main_menu"]="Display Main Menu"

# -----------------------------------------------------------------------------
# @var MAIN_MENU
# @brief Array defining the main menu options.
# @details Contains keys that correspond to the `MENU_ITEMS` associative array.
#          These keys define the options available in the main menu.
#
# @example
# MAIN_MENU=(
#     "option_one"
#     "option_two"
#     "display_sub_menu"
# )
# -----------------------------------------------------------------------------
MAIN_MENU=(
    "option_one"
    "option_two"
    "display_sub_menu"
)

# -----------------------------------------------------------------------------
# @var SUB_MENU
# @brief Array defining the sub-menu options.
# @details Contains keys that correspond to the `MENU_ITEMS` associative array.
#          These keys define the options available in the sub-menu.
#
# @example
# SUB_MENU=(
#     "option_three"
#     "display_main_menu"
# )
# -----------------------------------------------------------------------------
SUB_MENU=(
    "option_three"
    "display_main_menu"
)

# -----------------------------------------------------------------------------
# @brief Test function one
# @details Executes a sample action for the "Option One" menu item.
# -----------------------------------------------------------------------------
option_one() {
    # Debug declarations
    local debug=$(debug_start "$@")

    # Execute menu action
    printf "\nRunning %s().\n" "$FUNCNAME"
    pause

    # Debug log: function exit
    debug_end "$debug"
}

# -----------------------------------------------------------------------------
# @brief Test function two
# @details Executes a sample action for the "Option Two" menu item.
# -----------------------------------------------------------------------------
option_two() {
    # Debug declarations
    local debug=$(debug_start "$@")

    # Execute menu action
    printf "\nRunning %s().\n" "$FUNCNAME"
    pause

    # Debug log: function exit
    debug_end "$debug"
}

# -----------------------------------------------------------------------------
# @brief Test function three
# @details Executes a sample action for the "Option Three" menu item.
# -----------------------------------------------------------------------------
option_three() {
    # Debug declarations
    local debug=$(debug_start "$@")

    # Execute menu action
    printf "\nRunning %s().\n" "$FUNCNAME"
    pause

    # Debug log: function exit
    debug_end "$debug"
}

# -----------------------------------------------------------------------------
# @brief Displays a menu based on the given menu array.
# @details The menu items are numbered sequentially, and the user is prompted
#          for input to select an option.
#
# @param $1 Array of menu keys to display.
# @param $2 Debug flag for optional debug output.
#
# @global MENU_ITEMS Uses this global array to retrieve menu details.
# @global MENU_HEADER Prints the global menu header.
#
# @throws Prints an error message if an invalid choice is made.
#
# @return Executes the corresponding function for the selected menu item.
# -----------------------------------------------------------------------------
display_menu() {
    # Debug declarations
    local debug=$(debug_start "$@")

    local choice
    local i=1
    local menu_array=("${!1}")  # Array of menu keys to display

    # Display the menu header
    printf "%s\n\n" "$MENU_HEADER"
    printf "Please select an option:\n\n"

    # Display the menu items
    for func in "${menu_array[@]}"; do
        # Fixed-width format for consistent alignment
        printf "%-4d%-30s\n" "$i" "${MENU_ITEMS[$func]}"
        ((i++))
    done
    printf "%-4d%-30s\n" 0 "Exit"

    # Read user choice
    printf "\nEnter your choice: "
    read -n 1 -sr choice < /dev/tty || true
    printf "%s\n" "$choice"

    # Validate input
    if [[ -z "$choice" ]]; then
        printf "No input provided. Please enter a valid choice.\n"
        return
    elif [[ "$choice" =~ ^[0-9]$ ]]; then
        if [[ "$choice" -eq 0 ]]; then
            printf "\nExiting.\n"
            debug_end "$debug"
            exit 0
        elif [[ "$choice" -ge 1 && "$choice" -lt "$i" ]]; then
            local func="${menu_array[choice-1]}"
            "$func" "$debug"
        else
            printf "Invalid choice. Please try again.\n"
        fi
    else
        printf "Invalid input. Please enter a number.\n"
    fi

    # Debug log: function exit
    debug_end "$debug"
}

# -----------------------------------------------------------------------------
# @brief Displays the main menu.
# @details Calls the `display_menu` function with the main menu array.
#
# @param $1 Debug flag for optional debug output.
#
# @return Calls `display_menu` with the main menu array.
# -----------------------------------------------------------------------------
display_main_menu() {
    # Debug declarations
    local debug=$(debug_start "$@")

    # Clear screen
    clear
    # Display the menu
    display_menu MAIN_MENU[@] "$debug"

    # Debug log: function exit
    debug_end "$debug"
}

# -----------------------------------------------------------------------------
# @brief Displays the sub-menu.
# @details Calls the `display_menu` function with the sub-menu array. Loops
#          within the sub-menu until the user chooses to exit.
#
# @param $1 Debug flag for optional debug output.
#
# @return Calls `display_menu` with the sub-menu array in a loop.
# -----------------------------------------------------------------------------
display_sub_menu() {
    # Debug declarations
    local debug=$(debug_start "$@")

    while true; do
        # Clear screen
        clear
        # Display the menu
        display_menu SUB_MENU[@] "$debug"
    done

    # Debug log: function exit
    debug_end "$debug"
}

# -----------------------------------------------------------------------------
# @brief Entry point for the menu.
# @details Initializes debugging if the "debug" flag is passed, starts the
#          main menu loop, and ensures proper debug logging upon exit.
#
# @param $@ Arguments passed to the script. Pass "debug" for debug mode.
#
# @example
# Execute the menu
#   do_menu "$debug"
# -----------------------------------------------------------------------------
do_menu() {
    # Debug declarations
    local debug=$(debug_start "$@")

    # Main script execution starts here
    while true; do
        display_main_menu "$debug"
    done

    # Debug log: function exit
    debug_end "$debug"
}

############
### Arguments Functions
############

# TODO:  Make these extensible

# -----------------------------------------------------------------------------
# @brief Define script options and their properties.
# @details Each option includes its long form, short form, and description.
#
# @global OPTIONS Associative array of script options and their properties.
#
# @return None
# -----------------------------------------------------------------------------
declare -A OPTIONS=(
    ["--dry-run|-d"]="Enable dry-run mode (no actions performed)."
    ["--version|-v"]="Display script version and exit."
    ["--help|-h"]="Show this help message and exit."
    ["--log-file|-f <path>"]="Specify the log file location."
    ["--log-level|-l <level>"]="Set the logging verbosity level (DEBUG, INFO, WARNING, ERROR, CRITICAL)."
    ["--terse|-t"]="Enable terse output mode."
    ["--console|-c"]="Enable console logging."
)

# -----------------------------------------------------------------------------
# @brief Display script usage.
# @details Generates usage dynamically based on the `OPTIONS` associative array.
#          If the debug flag is set to "debug," a simple debug message will be printed.
#
# @param $1 [Optional] Debug flag. Pass "debug" to enable debug output.
#
# @global THIS_SCRIPT The name of the script.
# @global OPTIONS Associative array of script options and their properties.
#
# @return None
#
# @example
# usage debug
# -----------------------------------------------------------------------------
usage() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"

    # Display the script usage
    printf "Usage: %s [options]\n\n" "$THIS_SCRIPT"
    printf "Options:\n"
    for key in "${!OPTIONS[@]}"; do
        printf "  %s: %s\n" "$key" "${OPTIONS[$key]}"
    done

    debug_end "$debug" # Next line must be a return/print/exit out of function
    return 0
}

# -----------------------------------------------------------------------------
# @brief Parse command-line arguments.
# @details Processes the arguments passed to the script. Uses the `OPTIONS` array
#          for validation and handling. Supports debug mode to log the parsing
#          process and resulting variable values.
#
# @param "$@" The command-line arguments passed to the script.
#
# @global DRY_RUN Updates the dry-run status based on input.
# @global LOG_FILE Updates the log file path based on input.
# @global LOG_LEVEL Updates the log verbosity level based on input.
# @global TERSE Enables terse output mode if specified.
# @global USE_CONSOLE Enables console output if specified.
#
# @return None
#
# @example
# parse_args debug --dry-run --log-file mylog.txt
# parse_args --dry-run --log-file mylog.txt debug
# -----------------------------------------------------------------------------
parse_args() {
    local debug=$(start_debug "$@"); eval set -- "$(filter_debug "$@")"

    # Process the arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run|-d)
                DRY_RUN=true
                debug_print "DRY_RUN set to 'true'" "$debug"
                shift
                ;;
            --version|-v)
                print_version "$debug"
                debug_end "$debug" # Next line must be a return/print/exit out of function # Debug log: function exit
                exit 0
                ;;
            --help|-h)
                usage "$debug"
                debug_end "$debug" # Next line must be a return/print/exit out of function # Debug log: function exit
                exit 0
                ;;
            --log-file|-f)
                if [[ -n "$2" && "$2" != -* ]]; then
                    LOG_FILE=$(realpath -m "$2" 2>/dev/null)
                    debug_print "LOG_FILE set to '$LOG_FILE'" "$debug"
                    shift 2 # Shift past the option and its value
                else
                                    printf "Option '%s' requires an argument.\n" "$1"
                    debug_end "$debug" # Next line must be a return/print/exit out of function
                    exit 1
                fi
                ;;
            --log-level|-l)
                if [[ -n "$2" && "$2" != -* ]]; then
                    LOG_LEVEL="$2"
                    debug_print "LOG_LEVEL set to '$LOG_LEVEL'." "$debug"
                    shift 2 # Shift past the option and its value
                else
                    printf "Option '%s' requires an argument.\n" "$1"
                    debug_end "$debug" # Next line must be a return/print/exit out of function
                    exit 1
                fi
                ;;
            --terse|-t)
                TERSE="true"
                debug_print "TERSE set to 'true'" "$debug"
                shift
                ;;
            --console|-c)
                USE_CONSOLE="true"
                debug_print "USE_CONSOLE set to 'true'" "$debug"
                shift
                ;;
            debug)
                shift
                ;;
            *)
                if [[ -n "${1-}" ]]; then
                    printf "[ERROR] Unknown option: '%s'\n" "$1" >&2
                else
                    printf "[ERROR] No option provided.\n" >&2
                fi
                usage "$debug"
                debug_end "$debug" # Next line must be a return/print/exit out of function # Debug log: function exit
                exit 1
                ;;
        esac
    done

    # Debug: Final parsed values
    if [[ "$debug" == "debug" ]]; then
        printf "[DEBUG] Final parsed values:\n" >&2
        printf "\t- DRY_RUN='%s'\n\t- LOG_FILE='%s'\n\t- LOG_LEVEL='%s'\n\t- TERSE='%s'\n\t- USE_CONSOLE='%s'\n" \
            "${DRY_RUN:-false}" "${LOG_FILE:-None}" "${LOG_LEVEL:-None}" "${TERSE:-false}" "${USE_CONSOLE:-false}" >&2
    fi

    debug_end "$debug" # Next line must be a return/print/exit out of function
    return 0
}

############
### App-specific Installer Functions Here
############

############
### Main Functions
############

_main() {
    local debug=$(start_debug "$@"); eval set -- "$(debug_filter "$@")"

    # Check and set up the environment
    handle_execution_context "$debug"  # Get execution context and set environment variables
    get_proj_params "$debug"           # Get project and git parameters
    parse_args "$@"                    # Parse command-line arguments
    enforce_sudo "$debug"              # Ensure proper privileges for script execution
    validate_depends "$debug"          # Ensure required dependencies are installed
    validate_sys_accs "$debug"         # Verify critical system files are accessible
    validate_env_vars "$debug"         # Check for required environment variables
    setup_log "$debug"                 # Setup logging environment
    check_bash "$debug"                # Ensure the script is executed in a Bash shell
    check_sh_ver "$debug"              # Verify the Bash version meets minimum requirements
    check_bitness "$debug"             # Validate system bitness compatibility
    check_release "$debug"             # Check Raspbian OS version compatibility
    check_arch "$debug"                # Validate Raspberry Pi model compatibility
    check_internet "$debug"            # Verify internet connectivity if required

    # Print/display the environment
    print_system "$debug"              # Log system information
    print_version "$debug"             # Log the script version

    # Run installer steps
    start_script "$debug"              # Start the script with instructions
    set_time "$debug"                  # Offer to change timezone if default
    handle_apt_packages "$debug"       # Perform APT maintenance and install/update packages
    finish_script "$debug"             # Finish the script with final instructions

    debug_end "$debug" # Next line must be a return/print/exit out of function
    return 0
}

# -----------------------------------------------------------------------------
# @brief Main function entry point.
# @details This function calls `_main` to initiate the script execution. By
#          calling `main`, we enable the correct reporting of the calling
#          function in Bash, ensuring that the stack trace and function call
#          are handled appropriately during the script execution.
#
# @param "$@" Arguments to be passed to `_main`.
# @return Returns the status code from `_main`.
# -----------------------------------------------------------------------------
main() { _main "$@"; return "$?"; }

debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
main "$@"
debug_end "$debug" # Next line must be a return/print/exit out of function
exit $?

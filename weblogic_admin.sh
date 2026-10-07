```bash
#!/usr/bin/env bash
set -euo pipefail

# Configuration
# =================

DOMAIN_HOME="${DOMAIN_HOME:-/opt/oracle/middleware/user_projects/domains/base_domain}"
SERVER_NAME="${SERVER_NAME:-AdminServer}"

SERVER_HOME="${DOMAIN_HOME}/servers/${SERVER_NAME}"
LOG_DIR="${SERVER_HOME}/logs"
OUT_FILE="${LOG_DIR}/${SERVER_NAME}.out"
PID_FILE="${SERVER_HOME}/${SERVER_NAME}.pid"

START_SCRIPT="${DOMAIN_HOME}/bin/startWebLogic.sh"
STOP_SCRIPT="${DOMAIN_HOME}/bin/stopWebLogic.sh"

START_TIMEOUT=300
STOP_TIMEOUT=60
CHECK_INTERVAL=5


# Logging Functions
# ========================

timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

log_info() {
    echo "[$(timestamp)] INFO: $*"
}

log_warn() {
    echo "[$(timestamp)] WARN: $*" >&2
}

log_error() {
    echo "[$(timestamp)] ERROR: $*" >&2
}

# Validation
# ========================================

validate_environment() {

    log_info "Validating WebLogic environment..."

    if [[ ! -d "$DOMAIN_HOME" ]]; then
        log_error "DOMAIN_HOME does not exist: $DOMAIN_HOME"
        return 1
    fi

    if [[ ! -x "$START_SCRIPT" ]]; then
        log_error "Start script not found or not executable: $START_SCRIPT"
        return 1
    fi

    if [[ ! -x "$STOP_SCRIPT" ]]; then
        log_error "Stop script not found or not executable: $STOP_SCRIPT"
        return 1
    fi

    if [[ -z "${JAVA_HOME:-}" ]]; then
        log_warn "JAVA_HOME is not set."
    else
        log_info "JAVA_HOME=$JAVA_HOME"

        if [[ ! -x "${JAVA_HOME}/bin/java" ]]; then
            log_error "Java executable not found: ${JAVA_HOME}/bin/java"
            return 1
        fi
    fi

    mkdir -p "$LOG_DIR"

    log_info "Environment validation completed."
}

# PID Functions
# ============================================

get_pid_from_file() {

    if [[ ! -f "$PID_FILE" ]]; then
        return 0
    fi

    local pid
    pid=$(cat "$PID_FILE")

    if [[ "$pid" =~ ^[0-9]+$ ]]; then
        echo "$pid"
    fi
}

is_process_running() {

    local pid="$1"

    if kill -0 "$pid" 2>/dev/null; then
        return 0
    fi

    return 1
}

get_running_pid() {

    local pid

    pid=$(get_pid_from_file || true)

    if [[ -n "$pid" ]] && is_process_running "$pid"; then
        echo "$pid"
        return 0
    fi

    return 1
}

# Log Rotation
#===============================

rotate_log() {

    if [[ -f "$OUT_FILE" ]]; then

        local backup_file
        backup_file="${OUT_FILE}.$(date '+%Y%m%d_%H%M%S').bak"

        mv "$OUT_FILE" "$backup_file"

        log_info "Existing log rotated to: $backup_file"
    fi
}

# =============================================================================
# Start WebLogic
# =============================================================================

start_server() {

    validate_environment

    local pid

    pid=$(get_running_pid || true)

    if [[ -n "$pid" ]]; then
        log_warn "${SERVER_NAME} is already running. PID=$pid"
        return 0
    fi

    log_info "Starting ${SERVER_NAME}..."

    rotate_log

    log_info "Startup output: $OUT_FILE"

    nohup "$START_SCRIPT" > "$OUT_FILE" 2>&1 &

    pid=$!

    echo "$pid" > "$PID_FILE"

    log_info "WebLogic startup process launched. PID=$pid"

    local elapsed=0

    while (( elapsed < START_TIMEOUT )); do

        if grep -q "<The server started in RUNNING mode.>" "$OUT_FILE" 2>/dev/null; then

            log_info "SUCCESS: ${SERVER_NAME} is RUNNING."

            local actual_pid
            actual_pid=$(get_running_pid || true)

            if [[ -n "$actual_pid" ]]; then
                log_info "WebLogic PID=$actual_pid"
            fi

            return 0
        fi

        if ! is_process_running "$pid"; then
            log_error "${SERVER_NAME} startup process exited unexpectedly."
            log_error "Check log: $OUT_FILE"
            return 1
        fi

        sleep "$CHECK_INTERVAL"

        elapsed=$((elapsed + CHECK_INTERVAL))

        log_info "Waiting for ${SERVER_NAME} to start... ${elapsed}/${START_TIMEOUT} seconds"

    done

    log_error "${SERVER_NAME} startup timed out after ${START_TIMEOUT} seconds."
    log_error "Check WebLogic log: $OUT_FILE"

    return 1
}

# =============================================================================
# Stop WebLogic
# =============================================================================

stop_server() {

    validate_environment

    local pid

    pid=$(get_running_pid || true)

    if [[ -z "$pid" ]]; then

        log_info "${SERVER_NAME} is not running."

        [[ -f "$PID_FILE" ]] && rm -f "$PID_FILE"

        return 0
    fi

    log_info "Stopping ${SERVER_NAME}. PID=$pid"

    "$STOP_SCRIPT" >/dev/null 2>&1 || true

    local elapsed=0

    while (( elapsed < STOP_TIMEOUT )); do

        if ! is_process_running "$pid"; then

            log_info "SUCCESS: ${SERVER_NAME} stopped gracefully."

            rm -f "$PID_FILE"

            return 0
        fi

        sleep "$CHECK_INTERVAL"

        elapsed=$((elapsed + CHECK_INTERVAL))

    done

    log_warn "Graceful shutdown timed out after ${STOP_TIMEOUT} seconds."

    if is_process_running "$pid"; then

        log_warn "Force stopping ${SERVER_NAME}. PID=$pid"

        kill -9 "$pid" 2>/dev/null || true

        sleep 2

        if ! is_process_running "$pid"; then
            log_info "SUCCESS: ${SERVER_NAME} force stopped."
            rm -f "$PID_FILE"
            return 0
        fi
    fi

    log_error "Unable to stop ${SERVER_NAME}. Manual investigation required."

    return 1
}

# =============================================================================
# Status
# =============================================================================

status_server() {

    local pid

    pid=$(get_running_pid || true)

    if [[ -n "$pid" ]]; then

        log_info "${SERVER_NAME} is RUNNING. PID=$pid"

    else

        log_info "${SERVER_NAME} is STOPPED"

    fi
}

# =============================================================================
# Restart
# =============================================================================

restart_server() {

    log_info "Restarting ${SERVER_NAME}..."

    stop_server

    sleep 2

    start_server
}

# =============================================================================
# Main
# =============================================================================

case "${1:-}" in

    start)
        start_server
        ;;

    stop)
        stop_server
        ;;

    restart)
        restart_server
        ;;

    status)
        status_server
        ;;

    *)
        echo
        echo "Usage: $0 {start|stop|restart|status}"
        echo
        echo "Examples:"
        echo "  $0 start"
        echo "  $0 stop"
        echo "  $0 restart"
        echo "  $0 status"
        echo
        exit 1
        ;;

esac
```

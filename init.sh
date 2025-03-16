#!/bin/bash
# Server installation script

# 调试日志函数
log_debug() {
    echo "[DEBUG] $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

TMP_DIR="\${XDG_RUNTIME_DIR:-"/tmp"}"
log_debug "TMP_DIR set to: $TMP_DIR"

DISTRO_VERSION="${version}"
DISTRO_COMMIT="${commit}"
DISTRO_QUALITY="${quality}"
DISTRO_VSCODIUM_RELEASE="${release ?? ''}"

SERVER_APP_NAME="${serverApplicationName}"
SERVER_INITIAL_EXTENSIONS="${extensions}"
SERVER_LISTEN_FLAG="--port=0"
SERVER_DATA_DIR="$HOME/${serverDataFolderName}"
SERVER_DIR="$SERVER_DATA_DIR/bin/$DISTRO_COMMIT"
SERVER_SCRIPT="$SERVER_DIR/bin/$SERVER_APP_NAME"
SERVER_LOGFILE="$SERVER_DATA_DIR/bin/$DISTRO_COMMIT.log"
SERVER_PIDFILE="$SERVER_DATA_DIR/bin/$DISTRO_COMMIT.pid"
SERVER_TOKENFILE="$SERVER_DATA_DIR/bin/$DISTRO_COMMIT.token"
SERVER_OS=
SERVER_ARCH=
SERVER_CONNECTION_TOKEN=
SERVER_DOWNLOAD_URL=

LISTENING_ON=
OS_RELEASE_ID=
ARCH=
PLATFORM=

# Mimic output from logs of remote-ssh extension
print_install_results_and_exit() {
    echo "${id}: start"
    echo "exitCode==$1=="
    echo "listeningOn==$LISTENING_ON=="
    echo "connectionToken==$SERVER_CONNECTION_TOKEN=="
    echo "logFile==$SERVER_LOGFILE=="
    echo "osReleaseId==$OS_RELEASE_ID=="
    echo "arch==$ARCH=="
    echo "platform==$PLATFORM=="
    echo "tmpDir==$TMP_DIR=="
    ${envVariables.map(envVar => `echo "${envVar}==$${envVar}=="`).join('\n')}
    echo "${id}: end"
    exit 0
}

# Check if platform is supported
log_debug "Detecting platform..."
PLATFORM="$(uname -s)"
log_debug "Detected platform: $PLATFORM"
case $PLATFORM in
    Linux)
        SERVER_OS="linux"
        log_debug "Platform is Linux, setting SERVER_OS to linux"
        ;;
    *)
        log_debug "Unsupported platform detected: $PLATFORM"
        echo "Error platform not supported: $PLATFORM"
        print_install_results_and_exit 1
        ;;
esac

# Check machine architecture
log_debug "Detecting machine architecture..."
ARCH="$(uname -m)"
log_debug "Detected architecture: $ARCH"
case $ARCH in
    x86_64 | amd64)
        SERVER_ARCH="x64"
        log_debug "x64 architecture detected"
        ;;
    armv7l | armv8l)
        SERVER_ARCH="armhf"
        log_debug "ARMv7/ARMv8 architecture detected"
        ;;
    arm64 | aarch64)
        SERVER_ARCH="arm64"
        log_debug "ARM64 architecture detected"
        ;;
    *)
        log_debug "Unsupported architecture detected: $ARCH"
        echo "Error architecture not supported: $ARCH"
        print_install_results_and_exit 1
        ;;
esac

# https://www.freedesktop.org/software/systemd/man/os-release.html
log_debug "Detecting OS release ID..."
OS_RELEASE_ID="$(grep -i '^ID=' /etc/os-release 2>/dev/null | sed 's/^ID=//gi' | sed 's/"//g')"
if [[ -z $OS_RELEASE_ID ]]; then
    log_debug "OS release ID not found in /etc/os-release, trying /usr/lib/os-release"
    OS_RELEASE_ID="$(grep -i '^ID=' /usr/lib/os-release 2>/dev/null | sed 's/^ID=//gi' | sed 's/"//g')"
    if [[ -z $OS_RELEASE_ID ]]; then
        log_debug "OS release ID not found, setting to 'unknown'"
        OS_RELEASE_ID="unknown"
    fi
fi
log_debug "Detected OS release ID: $OS_RELEASE_ID"

# Create installation folder
log_debug "Creating server installation directory: $SERVER_DIR"
if [[ ! -d $SERVER_DIR ]]; then
    mkdir -p $SERVER_DIR
    if (( $? > 0 )); then
        log_debug "Failed to create server install directory: $SERVER_DIR"
        echo "Error creating server install directory"
        print_install_results_and_exit 1
    else
        log_debug "Successfully created server install directory: $SERVER_DIR"
    fi
fi

log_debug "Generating download URL..."
SERVER_DOWNLOAD_URL="$(echo "${serverDownloadUrlTemplate.replace(/\$\{/g, '\\${')}" | sed "s/\\\${quality}/$DISTRO_QUALITY/g" | sed "s/\\\${version}/$DISTRO_VERSION/g" | sed "s/\\\${commit}/$DISTRO_COMMIT/g" | sed "s/\\\${os}/$SERVER_OS/g" | sed "s/\\\${arch}/$SERVER_ARCH/g" | sed "s/\\\${release}/$DISTRO_VSCODIUM_RELEASE/g")"
log_debug "Generated download URL: $SERVER_DOWNLOAD_URL"

# Check if server script is already installed
if [[ ! -f $SERVER_SCRIPT ]]; then
    if [[ "$SERVER_OS" = "dragonfly" ]] || [[ "$SERVER_OS" = "freebsd" ]]; then
        log_debug "Unsupported OS detected: $SERVER_OS"
        echo "Error "$SERVER_OS" needs manual installation of remote extension host"
        print_install_results_and_exit 1
    fi

    log_debug "Entering server directory: $SERVER_DIR"
    pushd $SERVER_DIR > /dev/null

    if [[ ! -z $(which wget) ]]; then
        log_debug "Using wget to download server binary"
        wget --tries=3 --timeout=10 --continue --no-verbose -O vscode-server.tar.gz $SERVER_DOWNLOAD_URL
    elif [[ ! -z $(which curl) ]]; then
        log_debug "Using curl to download server binary"
        curl --retry 3 --connect-timeout 10 --location --show-error --silent --output vscode-server.tar.gz $SERVER_DOWNLOAD_URL
    else
        log_debug "No download tool (wget/curl) found"
        echo "Error no tool to download server binary"
        print_install_results_and_exit 1
    fi

    if (( $? > 0 )); then
        log_debug "Failed to download server binary"
        echo "Error downloading server from $SERVER_DOWNLOAD_URL"
        print_install_results_and_exit 1
    else
        log_debug "Successfully downloaded server binary"
    fi

    log_debug "Extracting server binary..."
    tar -xf vscode-server.tar.gz --strip-components 1
    if (( $? > 0 )); then
        log_debug "Failed to extract server binary"
        echo "Error while extracting server contents"
        print_install_results_and_exit 1
    else
        log_debug "Successfully extracted server binary"
    fi

    if [[ ! -f $SERVER_SCRIPT ]]; then
        log_debug $SERVER_SCRIPT does not exist
        log_debug "Server binary appears to be corrupted"
        echo "Error server contents are corrupted"
        print_install_results_and_exit 1
    fi

    log_debug "Cleaning up downloaded archive"
    rm -f vscode-server.tar.gz

    popd > /dev/null
    log_debug "Returned to previous directory"
else
    log_debug "Server script already exists: $SERVER_SCRIPT"
    echo "Server script already installed in $SERVER_SCRIPT"
fi

log_debug "Checking if server is already running..."
if [[ -f $SERVER_PIDFILE ]]; then
    SERVER_PID="$(cat $SERVER_PIDFILE)"
    SERVER_RUNNING_PROCESS="$(ps -o pid,args -p $SERVER_PID | grep $SERVER_SCRIPT)"
    log_debug "Found server process from PID file: $SERVER_RUNNING_PROCESS"
else
    SERVER_RUNNING_PROCESS="$(ps -o pid,args -A | grep $SERVER_SCRIPT | grep -v grep)"
    log_debug "Found server process from process list: $SERVER_RUNNING_PROCESS"
fi

if [[ -z $SERVER_RUNNING_PROCESS ]]; then
    log_debug "No running server found, starting new instance..."
    if [[ -f $SERVER_LOGFILE ]]; then
        log_debug "Removing old log file: $SERVER_LOGFILE"
        rm $SERVER_LOGFILE
    fi
    if [[ -f $SERVER_TOKENFILE ]]; then
        log_debug "Removing old token file: $SERVER_TOKENFILE"
        rm $SERVER_TOKENFILE
    fi

    log_debug "Creating new token file: $SERVER_TOKENFILE"
    touch $SERVER_TOKENFILE
    chmod 600 $SERVER_TOKENFILE
    SERVER_CONNECTION_TOKEN="${crypto.randomUUID()}"
    echo $SERVER_CONNECTION_TOKEN > $SERVER_TOKENFILE
    log_debug "Generated new connection token: $SERVER_CONNECTION_TOKEN"

    log_debug "Starting server with command: $SERVER_SCRIPT --start-server --host=127.0.0.1 $SERVER_LISTEN_FLAG $SERVER_INITIAL_EXTENSIONS --connection-token-file $SERVER_TOKENFILE --telemetry-level off --use-host-proxy --disable-websocket-compression --without-browser-env-var --enable-remote-auto-shutdown --accept-server-license-terms"
    $SERVER_SCRIPT --start-server --host=127.0.0.1 $SERVER_LISTEN_FLAG $SERVER_INITIAL_EXTENSIONS --connection-token-file $SERVER_TOKENFILE --telemetry-level off --use-host-proxy --disable-websocket-compression --without-browser-env-var --enable-remote-auto-shutdown --accept-server-license-terms &> $SERVER_LOGFILE &
    echo $! > $SERVER_PIDFILE
    log_debug "Server started with PID: $(cat $SERVER_PIDFILE)"
else
    log_debug "Server is already running: $SERVER_SCRIPT"
    echo "Server script is already running $SERVER_SCRIPT"
fi

log_debug "Verifying server connection token..."
if [[ -f $SERVER_TOKENFILE ]]; then
    SERVER_CONNECTION_TOKEN="$(cat $SERVER_TOKENFILE)"
    log_debug "Retrieved connection token: $SERVER_CONNECTION_TOKEN"
else
    log_debug "Token file not found: $SERVER_TOKENFILE"
    echo "Error server token file not found $SERVER_TOKENFILE"
    print_install_results_and_exit 1
fi

log_debug "Checking server startup status..."
if [[ -f $SERVER_LOGFILE ]]; then
    for i in {1..5}; do
        LISTENING_ON="$(cat $SERVER_LOGFILE | grep -E 'Extension host agent listening on .+' | sed 's/Extension host agent listening on //')"
        if [[ -n $LISTENING_ON ]]; then
            log_debug "Server listening on: $LISTENING_ON"
            break
        fi
        log_debug "Waiting for server to start... (attempt $i/5)"
        sleep 0.5
    done

    if [[ -z $LISTENING_ON ]]; then
        log_debug "Server failed to start successfully"
        echo "Error server did not start sucessfully"
        print_install_results_and_exit 1
    fi
else
    log_debug "Server log file not found: $SERVER_LOGFILE"
    echo "Error server log file not found $SERVER_LOGFILE"
    print_install_results_and_exit 1
fi

log_debug "Finalizing server setup..."
if [[ -z $SERVER_RUNNING_PROCESS ]]; then
    log_debug "Outputting installation results..."
    echo "${id}: start"
    echo "exitCode==0=="
    echo "listeningOn==$LISTENING_ON=="
    echo "connectionToken==$SERVER_CONNECTION_TOKEN=="
    echo "logFile==$SERVER_LOGFILE=="
    echo "osReleaseId==$OS_RELEASE_ID=="
    echo "arch==$ARCH=="
    echo "platform==$PLATFORM=="
    echo "tmpDir==$TMP_DIR=="
    ${envVariables.map(envVar => `echo "${envVar}==$${envVar}=="`).join('\n')}
    echo "${id}: end"

    log_debug "Server installation completed successfully"
    echo "${id}: Server installation script done"

    SERVER_PID="$(cat $SERVER_PIDFILE)"
    log_debug "Monitoring server process with PID: $SERVER_PID"
    SERVER_RUNNING_PROCESS="$(ps -o pid,args -p $SERVER_PID | grep $SERVER_SCRIPT)"
    while [[ -n $SERVER_RUNNING_PROCESS ]]; do
        log_debug "Server still running, checking again in 300 seconds..."
        sleep 300;
        SERVER_RUNNING_PROCESS="$(ps -o pid,args -p $SERVER_PID | grep $SERVER_SCRIPT)"
    done
    log_debug "Server process has stopped"
else
    log_debug "Server was already running, exiting with success"
    print_install_results_and_exit 0
fi
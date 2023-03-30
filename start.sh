#!/bin/bash

set -e

usage() {
  cat <<EOU
Usage:
  start.sh [--port <input>] [--hostname <hostname>]

Options:
  -p, --port <port>              The HTTP server port. Defaults to 8080.
  -h, --hostname <hostname>      The hostname that should be used for the origin
                                 server. Defaults to localhost.
  --help                         Show this help message

EOU
}

# Get the path to this script so we can find utils relative to this script
SOURCE=${BASH_SOURCE[0]}
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR=$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)
  SOURCE=$(readlink "$SOURCE")
  [[ $SOURCE != /* ]] && SOURCE=$DIR/$SOURCE # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DIR=$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)

PORT=8080
HOSTNAME="localhost"

while [[ $# -gt 0 ]]; do
  case $1 in
    -p|--port)
      PORT="$2"
      shift
      shift
      ;;
    -h|--hostname)
      HOSTNAME="$2"
      shift
      shift
      ;;
    --help)
      usage
      exit 0;
      ;;
    -*|--*)
      echo "Unknown option $1"
      exit 1
      ;;
  esac
done


_term() {
  echo "Cleanup..."
  pkill -P $$
  exit 1
}

trap _term SIGTERM
trap _term SIGKILL
trap _term SIGINT
trap _term EXIT

echo "Starting the webserver";
${DIR}/http-origin/bin/http-server -d ${DIR}/media -p ${PORT} &
server_process=$!
# Wait a moment to make sure the server is up and running
sleep 1

if ps -p $server_process >&-; then
    echo "Webserver started"
else
    echo "Failed to start webserver"
    exit 1
fi


for SOURCE in `ls ${DIR}/content/live-*`
do
  name=${SOURCE##*/}
  name="${name%.*}"
  echo "Creating source stream ${name} from ${SOURCE}"
  ${DIR}/dash-stream/dash-stream.sh -i ${SOURCE} \
    --ott \
    --origin http://${HOSTNAME}:${PORT}/${name}/manifest.mpd \
    --time-server http://${HOSTNAME}:${PORT}/time &
  child=$!
  sleep 1
  if ps -p $child >&-; then
      echo "Stream ${name} started"
  else
      echo "Failed to start stream ${name}"
      exit 1
  fi

done

wait "$server_process"

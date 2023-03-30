#!/bin/bash
# This script uses ffplay to play a udp multicast stream created with the `source-stream.sh` script

# Error out early in case anything does not work as expected
set -e

usage() {
  cat <<EOU
Usage:
  play-stream.sh [--port <port>] [--ip <ip>]

Options:
  -p, --port <port>  The UDP port for the multicast input. Defaults to 1234.
  --ip <ip>          The IP address used for the multicast input. Defaults to 233.0.0.1
  --help             Show this help message
EOU
}

# Setup defaults and parse arguments
PORT=1234
IP="233.0.0.1"

# Parse the command line args
while [[ $# -gt 0 ]]; do
  case $1 in
    -p|--port)
      PORT="$2"
      shift # past argument
      shift # past value
      ;;
    --ip)
      IP="$2"
      shift # past argument
      shift # past value
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

echo "Play ${IP}:${PORT}"
echo ""
echo ""

ffplay -nostats -flags low_delay -probesize 32 \
  -fflags nobuffer+fastseek+flush_packets -analyzeduration 0 -sync ext \
  "udp://@${IP}:${PORT}?pkt_size=1316"
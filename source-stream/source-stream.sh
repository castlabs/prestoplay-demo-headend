#!/bin/bash
# This script uses FFMPEG (you need version 5!) to create a multicast IPTV stream over udp.

# Error out early in case anything does not work as expected
set -e

usage() {
  cat <<EOU
Usage:
  source-stream.sh [--port <port>] [--ip <ip>] [--input <input>] [--preset <preset>]
                   [--tune <tune>] [--profile <profile>] [--bitrate <bitrate>]

Options:
  -i, --input <input>  The input args passed to ffmpeg, defaults to testsrc
  -p, --port <port>    The UDP port for the multicast output. Defaults to 1234.
  --preset <preset>    The ffmpeg preset that will be applied to encoding. Defaults to ultrafast
  --ip <ip>            The IP address used for the multicast output. Defaults to 233.0.0.1
  --tune <tune>        The ffmpeg tune option, i.e. zerolatency. Defaults to no tune.
  --profile <profile>  The encoding profile. Defaults to high.
  --bitrate <bitrate>  The target bitrate. Defaults to 4M.
  --encoder <encoder>  The encoder that will be used. Defaults to "auto" and selects hardware encoders if possible
  --help               Show this help message
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


# Setup defaults and parse arguments
PORT=1234
IP="233.0.0.1"
SIZE=1920x1080
PRESET=ultrafast
RATE=30
GOP=10
BITRATE=4M
TEXT_PARAMS="fontcolor=white:fontsize=40:fontfile=${DIR}/../utils/RobotoMono-Regular.ttf:box=1:boxborderw=10:boxcolor=black@0.5:line_spacing=20:rate=${RATE}:x=0:y=200:textfile=${DIR}/overlay.txt"
INPUT=
TUNE=
PROFILE=high
META_FILTER="metadata=mode=add:key=title:value"
ENCODER=auto
ACCELERATOR=

# Parse the command line args
POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
  case $1 in
    -p|--port)
      PORT="$2"
      shift # past argument
      shift # past value
      ;;
    -i|--input)
      INPUT="$2"
      shift # past argument
      shift # past value
      ;;
    --ip)
      IP="$2"
      shift # past argument
      shift # past value
      ;;
    --profile)
      PROFILE="$2"
      shift # past argument
      shift # past value
      ;;
    --bitrate)
      BITRATE="$2"
      shift # past argument
      shift # past value
      ;;
    --tune)
      TUNE="$2"
      shift # past argument
      shift # past value
      ;;
    --preset)
      PRESET="$2"
      shift # past argument
      shift # past value
      ;;
    --encoder)
      ENCODER="$2"
      shift # past argument
      shift # past value
      ;;
    --help)
      usage
      exit 0;
      ;;
#    --default)
#      DEFAULT=YES
#      shift # past argument
#      ;;
    -*|--*)
      echo "Unknown option $1"
      exit 1
      ;;
#    *)
#      POSITIONAL_ARGS+=("$1") # save positional arg
#      shift # past argument
#      ;;
  esac
done
set -- "${POSITIONAL_ARGS[@]}" # restore positional parameters

if [ -z "${INPUT}" ]
then
  INPUT="-f lavfi -i testsrc=size=${SIZE}:rate=${RATE}"
else
  INPUT="-i ${INPUT}"
fi

if [ -n "${TUNE}" ]
then
  TUNE="-tune ${TUNE}"
fi

# echo "Use HW Accelerator: videotoolbox"

if [ "$(uname)" == "Darwin" ]; then
  ACCELERATOR="-hwaccel videotoolbox"
  if [ "auto" = "${ENCODER}" ]; then
    ENCODER="h264_videotoolbox"
  fi
fi
if [ "auto" = "${ENCODER}" ]; then
  ENCODER="libx264"
fi

echo "Creating source stream and casting to ${IP}:${PORT}"
echo "Input      : ${INPUT}"
echo "Size       : ${SIZE}"
echo "Framerate  : ${RATE}"
echo "GOP Size   : ${GOP}"
echo "Bitrate    : ${BITRATE}"
echo "Script Dir : ${DIR}"
echo "Tune       : ${TUNE}"
echo "Profile    : ${PROFILE}"
echo "Preset     : ${PRESET}"
echo "Accelerator: ${ACCELERATOR}"
echo "Encoder    : ${ENCODER}"
echo ""
echo ""

#-bsf:v h264_mp4toannexb
# pkt_size=1316&
  #-level ${LEVEL} \

ffmpeg -hide_banner -y -threads 2 -re -fflags +genpts -stream_loop -1 \
  ${ACCELERATOR} \
  ${INPUT} \
  -r ${RATE} \
  -g ${GOP} -keyint_min ${GOP} -sc_threshold 0 -bf 0 \
  -preset ${PRESET} ${TUNE} \
  -pix_fmt yuv420p \
  -vcodec ${ENCODER} \
  -profile ${PROFILE} \
  -b:v ${BITRATE} \
  -c:a aac -b:a 2K \
  -vf "${META_FILTER}=1080p,scale=1920:1080,setsar=1:1,drawtext=${TEXT_PARAMS}" \
  -f mpegts -max_interleave_delta 0 -flush_packets 1 "udp://@${IP}:${PORT}?broadcast=1&ttl=1"


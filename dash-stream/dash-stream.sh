#!/bin/bash
# Script that reads input from a mpegts multicast source and creates a
# low latency dash stream that is pushed to an origin server
#

# error out early
set -e

usage() {
  cat <<EOU
Usage:
  dash-stream.sh [--input <input>] [--ott] [--time-server <time-server>] [--gop <gop>] [--origin <origin>]
                 [--segment-duration <segment-duration>] [--preset <preset>] [--tune <tune>]
                 [--window-size <segments>] [--encoder <encoder>] [--renditions <renditions>]
                 [--fragment-duration <duration>]

Options:
  -i, --input <input>            The address used to read the input stream. Defaults to 233.0.0.1:1234.
  --ott                          Use input as a looping input. You need to set input to a ts input file that will be looped.
  --time-server <time-server>    The URL that is added as a UTCTimeElement to the DASH manifest. Defaults to http://localhost:8080/time
  --gop <gop>                    The gop size in frames. Defaults to 60.
  --preset <preset>              The ffmpeg preset that will be applied to encoding. Defaults to veryfast
  --segment-duration <duration>  Segment duration in seconds. Defaults to 2.
  --origin <origin>              The URL to the origin server. Specify the URL to the manifest here. Defaults to http://localhost:8080/live-1/manifest.mpd
  --tune <tune>                  The ffmpeg tune option, i.e. zerolatency. Defaults to no tune.
  --windows-size <segments>      The maximum number of segments to keep in the manifest. Defaults to 60
  --encoder <encoder>            Set the encoder. Defaults to libx264. Set this to auto to auto detect hardware, i.e. videotoolbox encoder on mac.
  --renditions <renditions>      Specify the renditions that should be encoded. This takes a string in
                                 the form <resolution>:<bitrate>:<profile>,[<resolution>:<bitrate>:<profile>]. For
                                 example 480:1M:main,1080:4M:high will create two renditions, 480p@1Mbit and 1080p@4Mbit.
                                 Default: 1080:4M:high
  --fragment-duration <dur>      Fragment/Chunk duration in seconds. Set this to 0 to disable fragmentation.
                                 Default: 0.06
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


if [ -z "${LOCAL_IP}" ]
then
  LOCAL_IP=localhost
fi

# Setup defaults and parse arguments
SEGMENT_DURATION=2
GOP=60
RATE=30
ORIGIN="http://localhost:8080/live-1/manifest.mpd"
INPUT="233.0.0.1:1234"
PRESET=veryfast
#TIME_SERVER="https://time.akamai.com/?iso"
TIME_SERVER="http://${LOCAL_IP}:8080/time"
TUNE=
TEXT_PARAMS="fontcolor=white:fontsize=40:fontfile=${DIR}/../utils/RobotoMono-Regular.ttf:box=1:boxborderw=10:boxcolor=black@0.5:line_spacing=20:rate=${RATE}:x=(w-tw-0):y=200:textfile=${DIR}/overlay.txt"
META_FILTER="metadata=mode=add:key=title:value"
WINDOWS_SIZE=60
OTT=
ACCELERATOR=
ENCODER=auto
SOURCE_RENDITIONS="1080:4M:high"
FRAGMENTATION=

# Parse the command line args
while [[ $# -gt 0 ]]; do
  case $1 in
    -i|--input)
      INPUT="$2"
      shift # past argument
      shift # past value
      ;;
    --time-server)
      TIME_SERVER="$2"
      shift # past argument
      shift # past value
      ;;
    --window-size)
      WINDOWS_SIZE="$2"
      shift # past argument
      shift # past value
      ;;
    --gop)
      GOP="$2"
      shift # past argument
      shift # past value
      ;;
    --segment-duration)
      SEGMENT_DURATION="$2"
      shift # past argument
      shift # past value
      ;;
    --encoder)
      ENCODER="$2"
      shift # past argument
      shift # past value
      ;;
    --fragment-duration)
      FRAGMENTATION="$2"
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
    --renditions)
      SOURCE_RENDITIONS="$2"
      shift # past argument
      shift # past value
      ;;
    --origin)
      ORIGIN="$2"
      shift # past argument
      shift # past value
      ;;
    --help)
      usage
      exit 0;
      ;;
   --ott)
     OTT=YES
     shift # past argument
     ;;
    -*|--*)
      echo "Unknown option $1"
      exit 1
      ;;
  esac
done


if [ -z "${FRAGMENTATION}" ]; then
  FRAGMENTATION="-frag_duration 0.06 -frag_type duration"
else
  if [ "${FRAGMENTATION}" != "0" ]; then
    FRAGMENTATION="-frag_duration ${FRAGMENTATION} -frag_type duration"
  else
    FRAGMENTATION=""
  fi
fi

if [ -n "${TUNE}" ]
then
  TUNE="-tune ${TUNE}"
fi

IPTV_INPUT="-probesize 32 -analyzeduration 0 -fflags nobuffer+fastseek+flush_packets -f mpegts -i udp://${INPUT}?pkt_size=1316&overrun_nonfatal=1&fifo_size=50000000"
OTT_INPUT="-fflags +genpts -stream_loop -1 -i ${INPUT}"
SOURCE=$IPTV_INPUT

if [ -n "${OTT}" ]
then
  SOURCE=$OTT_INPUT
fi

echo "Start DASH Stream"

if [ "$(uname)" == "Darwin" ]; then
  ACCELERATOR="-hwaccel videotoolbox"
  if [ "auto" = "${ENCODER}" ]; then
    ENCODER="h264_videotoolbox"
  fi
  echo "Use HW Accelerator: videotoolbox"
fi
if [ "auto" = "${ENCODER}" ]; then
  ENCODER="libx264"
fi

echo "Source       : ${SOURCE}"
echo "Encoder      : ${ENCODER}"
echo "Fragmentation: ${FRAGMENTATION}"

rend=(${SOURCE_RENDITIONS//,/ })
counter=0
for RENDITION in ${rend[@]}; do
  r=(${RENDITION//:/ })
  RES=${r[0]}
  BITRATE=${r[1]}
  PROF=$([ -z "${r[2]}" ] && echo "main" || echo "${r[2]}")
  echo "Adding rendition ${counter}: ${RES}p with ${BITRATE} and Profile ${PROF}"
  NEXT="-map 0:v:0 -b:v:${counter} ${BITRATE} -c:v:${counter} ${ENCODER} -minrate:v:${counter} ${BITRATE} -maxrate:v:${counter} ${BITRATE} -profile:v:${counter} ${PROF} -filter:v:${counter} ${META_FILTER}=${RES}p,drawtext=${TEXT_PARAMS},scale=-2:${RES}"
  RENDITIONS="${RENDITIONS} ${NEXT}"
  counter=$(( counter + 1 ))
done

ffmpeg -y -hide_banner -an -re \
 ${ACCELERATOR} \
 ${SOURCE} \
 -preset ${PRESET} ${TUNE} -r ${RATE} \
 -bf 0 -sc_threshold 0 -g ${GOP} -keyint_min ${GOP} -pix_fmt yuv420p \
 ${RENDITIONS} \
 -use_timeline 0 \
 -use_template 1 \
 -seg_duration ${SEGMENT_DURATION} \
 -remove_at_exit 1 \
 -index_correction 1 \
 -streaming 1 \
 ${FRAGMENTATION} \
 -window_size ${WINDOWS_SIZE} \
 -extra_window_size 2 \
 -utc_timing_url ${TIME_SERVER} \
 -adaptation_sets "id=0,streams=v" \
 -ldash 1 \
 -method PUT -chunked_post 1 -multiple_requests 1 \
 -f dash ${ORIGIN}

# Create live test streams

This repository contains scripts and tools to create IPTV and DASH low latency streams.

**Note** if you run things locally you need to have **ffmpeg >= 5** installed.

## Requirements

This repo and the scripts in it are geared towards running on a Mac where we have access to
hardware acceleration and can assume that some basic tools are available. Before you can start
you need to make sure that the following tools are installed and available in `PATH`:

* `ffmpeg` -- `brew install ffmpeg` should do the trick
* 

## Components

The repo contains the following components and tools that are relevant for the 
setup:

 * [http-origin](./http-origin) contains sources for an http origin server. This is 
   required to stream a DASH ultra low latency stream with cmaf chunked transfer. 
   The origin server can also be used for time syncing and makes sure that segments
   can be streamed while they are still being generated by the encoder.
 * [source-stream](./source-stream) Contains a [script](./source-stream/source-stream.sh)
   that creates a test stream and pushes it as mpegts over multicast UDP to the specified
   target IP:PORT. This is the source stream for the dash packager and needs to be executed
   first. You can also run this standalone if you do not need the corresponding dash stream.
 * [dash-stream](./dash-stream) Contains a [script](./dash-stream/dash-stream.sh)
   that creates a dash low latency stream from a [source-stream](./source-stream) and pushes
   the results to the [http-origin](./http-origin).

## Very basic usage

Assuming the http origin server is compiled and ready to go (you need a golang SDK installed
or used docker otherwise), you can get started with three shells running in parallel:

1) `./http-origin/bin/http-server` Runs the origin server. This will be available on http://localhost:8080 by default
2) `./source-stream/source-stream.sh` Runs the source stream generator. You should have an mpegts multicast stream available on udp://233.0.0.1:1234 now. You can use `./source-stream/play-stream.sh` to check and confirm that.
3) `./dash-stream/dash-stream.sh` Runs the dash transcode from the UDP stream on udp://233.0.0.1:1234 and pushes to the origin server. You should have a dash stream available now on http://localhost:8080/live-1/manifest.mpd and you can quickly verify this using `ffplay http://localhost:8080/live-1/manifest.mpd`.

## Docker and Docker Compose setup

The repository contains a multi-layer docker file that can be used to create
each of the components as a docker container.

There is also a docker compose setup in the root folder that you can run 
everything with one command. This will create a localhost deployment. Note 
though that you might need to pass the timeserver URL to the dash-stream if
you plan to use the stream outside of localhost.

**Note** also that so far it seems that the UDP multicast is not leaving the docker 
containers. If you need to expose the multicast streams directly, do not use a docker
setup but run the scripts directly on the host (except the origin server, that can still
run in a container).

### Time Server URL

The default time server URL is localhost and uses the origin server. If you need to access
the stream from a remote device, make sure that you specify the local IP address that will
expose the origin server when building the compose stack, i.e.:

```
$> docker-compose -f compose-ott-only.yml build --build-arg LOCAL_IP=192.168.242.106
```

The above will build the stack and will use http://192.168.242.106:8080/time as the time endpoint 
referenced in the manifest.

### Run the stacks

There are two stacks contained in the repo

 * [compose-ott-only.yml](./compose-ott-only.yml) will create two DASH live streams expose on port 8080
   on the host. The manifests are:
   * http://localhost:8080/live-1/manifest.mpd
   * http://localhost:8080/live-2/manifest.mpd
 * [compose-iptv-ott.yml](./compose-iptv-ott.yml) will create two DASH live streams expose on port 8080
   on the host and in addition expose IPTV multicast streams. The manifest URLs are the same as above.
   **Note** that there are severe limitations with the multicast delivery and if you need to access
   the multicast output directly, you might want to consider just running the HTTP server and run the source
   and dash component scripts directly.

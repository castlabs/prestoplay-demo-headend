# HTTP Origin Server

This folder contains a http server written in go that can be used
as an origin server for dash and HLS streams. 

The encoder/packager can push to this server to expose streams and the server is able to handle streamed
responses where we can push data out while a file is still being transmitted.

The server, by default, starts on port 8080 and writes data to a `./data` folder
in the current working directory. These settings can be changed through command line
parameters.

The server exposes two end points:

 * `/time` responds with the current server time in ISO format and can be used for 
   time syncs in dash manifests, i.e. `UTCTimeElement` entries
 * `/` is a catch-all end point where data can be pushed to, i.e. you can create 
   a new live stream by pushing to say `http://localhost:8080/live-1/manifest.mpd`

## Build

Assuming you have go installed and configured, run:

```shell
make
```

to build both Mac and Linux binaries of the server.

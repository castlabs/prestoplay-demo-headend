FROM golang:bullseye as http-server
COPY http-origin/go.mod .
COPY http-origin/go.sum .
COPY http-origin/http_server.go src/http_server.go
RUN unset GOPATH && go build -o bin/http_server src/http_server.go
COPY media ./media
EXPOSE 8080
ENTRYPOINT ["./bin/http_server"]

FROM ubuntu:22.04 as ffmpeg
RUN apt update -y && apt install -y ffmpeg
RUN mkdir /utils
COPY utils/RobotoMono-Regular.ttf /utils

FROM ffmpeg as ll-source
COPY source-stream/source-stream.sh .
COPY source-stream/overlay.txt .
COPY content/* ./content/
EXPOSE 1234/udp
EXPOSE 1201/udp
EXPOSE 1202/udp
EXPOSE 1203/udp
ENTRYPOINT ["./source-stream.sh"]

FROM ffmpeg as ll-dash
COPY content/* ./content/
ARG LOCAL_IP=localhost
ENV LOCAL_IP=${LOCAL_IP}
COPY dash-stream/dash-stream.sh .
COPY dash-stream/overlay.txt .
ENTRYPOINT ["./dash-stream.sh"]


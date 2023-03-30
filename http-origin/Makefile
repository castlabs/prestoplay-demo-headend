all: http-server http-server-lx

http-server:
	go build -o bin/http-server http_server.go

http-server-lx:
	GOOS=linux GOARCH=amd64 go build -o bin/http-server-lx http_server.go

clean:
	@rm -rf bin/
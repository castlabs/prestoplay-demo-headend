package main

import (
	"bytes"
	"flag"
	"fmt"
	"github.com/djherbis/stream"
	"github.com/juju/ratelimit"
	"github.com/gorilla/mux"
	"io"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

// Lock the stream map
var streamsLock = sync.RWMutex{}

// we store the path->stream map here to find files that are currently
// being uploaded
var streamMap = make(map[string]*stream.Stream)
var baseDir = ""
var rateLimitKbit = 0

func main() {
	port := flag.Int("p", 8080, "Server port. Defaults to 8080")
	sslPort := flag.Int("s", 8081, "Server SSL port. Defaults to 8081")
	rateLimit := flag.Int("l", 0, "Enable rate limit for live streams. Specified in KB/s (not Kbit!).")
	rootDir := flag.String("d", "data", "The base folder where content will be stored. Defaults to ./data")
	keyFile := flag.String("K", "", "The SSL key")
	certFile := flag.String("C", "", "The SSL cert")
	flag.Parse()

	if rootDir == nil {
		log.Fatalf("An empty base directory is not permitted!")
		return
	}
	baseDir = *rootDir
	rateLimitKbit = *rateLimit

	// create the data directory if needed
	err := os.MkdirAll(baseDir, 0770)
	if err != nil {
		log.Fatalf("Unableo to create base folder: %v", err)
		return
	}
	log.Printf("Created data folder: %s", baseDir)
	if rateLimitKbit > 0 {
		log.Printf("Rate Limit: %d Kbit", rateLimitKbit)
	} else {
		log.Printf("Rate Limit: No Limit")
		rateLimitKbit = 1000000
	}

	// set up the handler.
	r := mux.NewRouter().StrictSlash(false)

	// /time responds to get request with the current server time in ISO. This
	// can be used for instance in DASH as an end-point for UTCTiming in a manifest
	r.HandleFunc("/time", isoTimeResponse)

	// takedown handler proxy to work around some CORS issues
	takedownRouter := r.PathPrefix("/takedown").Subrouter()
	takedownRouter.PathPrefix("/").HandlerFunc(handleCslRequest)

	// The catch all handler deals with POST and PUT requests that push data and
	// with GET requests to get the data out again
	r.PathPrefix("/").HandlerFunc(routeRequest)

	if *keyFile != "" {

		//  Start HTTP
		go func() {
			log.Printf("Starting server on port %d", *port)
			err = http.ListenAndServe(fmt.Sprintf(":%d", *port), r)
			if err != nil {
				log.Fatalf("unable to start server: %v", err)
			}
		}()
		
		log.Printf("Starting SSL server on port %d", *sslPort)
		err = http.ListenAndServeTLS(fmt.Sprintf(":%d", *sslPort), *certFile, *keyFile, r)
		if err != nil {
			log.Fatalf("unable to start server: %v", err)
		}
	} else {
		log.Printf("Starting server on port %d", *port)
		err = http.ListenAndServe(fmt.Sprintf(":%d", *port), r)
		if err != nil {
			log.Fatalf("unable to start server: %v", err)
		}
	}
}

// Very naive cors implementation that just does permit all
func enableCors(writer http.ResponseWriter) {
	writer.Header().Set("Access-Control-Allow-Origin", "*")
	writer.Header().Set("Access-Control-Allow-Methods", "*")
	writer.Header().Set("Access-Control-Allow-Headers", "*")
}

// Always responds with UTC time in ISO format (RFC3339)
func isoTimeResponse(writer http.ResponseWriter, request *http.Request) {
	enableCors(writer)
	writer.WriteHeader(http.StatusOK)
	timeString := time.Now().UTC().Format(time.RFC3339)
	log.Printf("TIME Request %s", timeString)
	_, err := writer.Write([]byte(timeString))
	if err != nil {
		log.Printf("error while writing time: %v", err)
	}
}

func handleCslRequest(res http.ResponseWriter, req *http.Request) {
	enableCors(res)
	if req.Method != http.MethodPost {
		res.WriteHeader(http.StatusOK)
		return
	}

	path := req.URL.Path
	path = strings.TrimPrefix(path, "/takedown/")
	targetUrl := fmt.Sprintf("https://fe.staging.drmtoday.com/frontend/apis/csl/v1/%s", path)

	sourceData, err := ioutil.ReadAll(req.Body)
	if err != nil {
		log.Printf("Error: %v", err)
		res.WriteHeader(http.StatusInternalServerError)
		return
	}

	resp, err := http.Post(targetUrl, "application/json", bytes.NewReader(sourceData))
	if err != nil {
		log.Printf("Error: %v", err)
		res.WriteHeader(http.StatusInternalServerError)
		return
	}
	//We Read the response body on the line below.
	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		log.Printf("Error: %v", err)
		res.WriteHeader(http.StatusInternalServerError)
		return
	}
	//Convert the body to type string
	res.WriteHeader(resp.StatusCode)
	res.Write(body)
}

func routeRequest(writer http.ResponseWriter, request *http.Request) {
	enableCors(writer)

	fileName := filepath.Join(baseDir, request.URL.Path)

	if strings.HasSuffix(fileName, ".css") {
		writer.Header().Set("Content-Type", "text/css")
	}
	if strings.HasSuffix(fileName, ".js") {
		writer.Header().Set("Content-Type", "text/javascript")
	}

	if request.Method == http.MethodPut || request.Method == http.MethodPost {
		parentDirectory := filepath.Dir(fileName)
		log.Printf("PUSH %s to %s in %s", request.RequestURI, fileName, parentDirectory)

		// create the parent folder
		err := os.MkdirAll(parentDirectory, 0770)
		if err != nil {
			writer.WriteHeader(http.StatusInternalServerError)
			log.Printf("error while creating parent directory: %v", err)
			return
		}

		// create the stream for the new file
		w, err := stream.New(fileName)
		if err != nil {
			writer.WriteHeader(http.StatusInternalServerError)
			log.Printf("error while creating file %v", err)
			return
		}

		// make sure we sync access to the streams map
		// and put the new stream in
		streamsLock.Lock()
		streamMap[fileName] = w
		streamsLock.Unlock()

		// When we are getting out of here we need no make sure that we
		// close and remove the stream. At this point we have all the data
		// that we will get and we will serve from disc
		defer func() {
			log.Printf("Closing file and removing in-memory entry for %s", fileName)
			_ = w.Close()
			streamsLock.Lock()
			streamMap[fileName] = nil
			streamsLock.Unlock()
		}()

		// start writing the data to the stream
		_, err = io.Copy(w, request.Body)
		if err != nil {
			log.Printf("Error while reading data %v", err)
		}
	} else if request.Method == http.MethodDelete {
		// Handle delete requests and make sure that we
		// remove files from disk and close any active stream if this
		// is an ongoing request
		if _, err := os.Stat(fileName); err == nil {
			log.Printf("DELETE %s", fileName)

			// cleanup the in-memory streams
			streamsLock.Lock()
			inMemoryFile := streamMap[fileName]
			if inMemoryFile != nil {
				_ = inMemoryFile.Close()
				streamMap[fileName] = nil
			}
			streamsLock.Unlock()

			// Remove the file from disc
			err = os.Remove(fileName)
			if err != nil {
				log.Printf("File %s could not be removed: %v", fileName, err)
			}
		}
	} else if request.Method == http.MethodGet {
		log.Printf("GET request for %s", fileName)

		streamsLock.Lock()
		inMemoryFile := streamMap[fileName]
		streamsLock.Unlock()

		// Bucket adding n KB every second, holding max 100KB
		bucket := ratelimit.NewBucketWithRate(float64(rateLimitKbit*1024), 100*1024)
		// Either serve the file from the in-memory stream (if this is still
		// an ongoing upload) or serve it from filesystem
		if inMemoryFile != nil {
			log.Printf("GET response from in-memory reader for %s", fileName)
			reader, err := inMemoryFile.NextReader()
			if err != nil {
				log.Printf("Error while creating stream from in-memory file: %v", err)
				return
			}

			if rateLimitKbit > 0 {
				_, err = io.Copy(writer, ratelimit.Reader(reader, bucket))
			} else {
				_, err = io.Copy(writer, reader)
			}
			if err != nil {
				log.Printf("Error while writing in-memory data for file %s: %v", fileName, err)
			}
		} else {
			log.Printf("GET response from file reader for %s", fileName)
			handle, err := os.Open(fileName)
			if err != nil {
				writer.WriteHeader(http.StatusNotFound)
				return
			}

			fileInfo, err := handle.Stat()
			if err != nil {
				writer.WriteHeader(http.StatusNotFound)
				return
			}

			// IsDir is short for fileInfo.Mode().IsDir()
			if fileInfo.IsDir() {
				if !strings.HasSuffix(request.RequestURI, "/") {
					http.Redirect(writer, request, request.RequestURI + "/", 301)
					return
				}
				// file is a directory
				handle.Close()
				fileName = filepath.Join(fileName, "index.html")
				handle, err = os.Open(fileName)
				if err != nil {
					writer.WriteHeader(http.StatusNotFound)
					return
				}
			} 
			if strings.HasSuffix(fileName, ".m4s") || strings.HasSuffix(fileName, ".mp4") {
				writer.Header().Set("Cache-Control", "max-age=3600")
			}
			if rateLimitKbit > 0 && rateLimitKbit != 1000000 {
				_, err = io.Copy(writer, ratelimit.Reader(handle, bucket))
			} else {
				_, err = io.Copy(writer, handle)
			}

			if err != nil {
				log.Printf("Error while reading file data for file %s: %v", fileName, err)
			}
			_ = handle.Close()
		}
	}
}

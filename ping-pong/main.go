package main

import (
	"fmt"
	"net/http"
	"os"
	"strconv"
	"sync"
)

func main() {
	server()
}

func server() {
	port := os.Getenv("PORT")
	fmt.Printf("Server started on port %s\n", port)
	port = ":" + port
	count := 0
	var mutex sync.Mutex

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		mutex.Lock()
		defer mutex.Unlock()
		path := os.Getenv("FILEPATH")
		fmt.Printf("Writing to '%s'\n", path)
		tmp := path + ".tmp"
		if err := os.WriteFile(tmp, []byte(strconv.Itoa(count)), 0644); err != nil {
			http.Error(w, "Atomic write-to-disk failed!", http.StatusInternalServerError)
			return
		}
		if err := os.Rename(tmp, path); err != nil {
			http.Error(w, "Atomic write-to-disk failed!", http.StatusInternalServerError)
			return
		}
		fmt.Fprintf(w, "pong %d", count)

		count++
	})
	http.ListenAndServe(port, nil)
}

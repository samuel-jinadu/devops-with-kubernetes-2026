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

	http.HandleFunc("/count", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(strconv.Itoa(count)))
	})

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		mutex.Lock()
		defer mutex.Unlock()
		fmt.Fprintf(w, "pong %d", count)
		count++
	})
	http.ListenAndServe(port, nil)
}

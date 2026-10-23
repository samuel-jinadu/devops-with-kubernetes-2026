package main

import (
	"fmt"
	"net/http"
	"os"
)

func main() {
	server()
}

func server() {
	port := os.Getenv("PORT")
	fmt.Printf("Server started on port %s\n", port)
	port = ":" + port
	count := 0

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "pong %d", count)
		count++
	})
	http.ListenAndServe(port, nil)
}

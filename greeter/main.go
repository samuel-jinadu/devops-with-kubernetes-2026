package main

import (
	"fmt"
	"net/http"
	"os"
)

func main() {
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		greeting := os.Getenv("GREETING")
		if greeting == "" {
			greeting = "Hello from default"
		}
		fmt.Fprintf(w, "%s", greeting)
	})
	fmt.Println("Greeter started on port 8080")
	http.ListenAndServe(":8080", nil)
}

package main

import (
	"fmt"
	"net/http"
	"os"
)

func main() {
	port := os.Getenv("PORT")
	fmt.Printf("Server started on port %s\n", port)
	port = ":" + port
	http.ListenAndServe(port, nil)
}

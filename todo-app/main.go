package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
	"embed"
	"io/fs"
)

//go:embed static
var staticFS embed.FS

func main() {
	port := os.Getenv("PORT")
	fmt.Printf("Server started on port %s\n", port)
	port = ":" + port

	sub, err := fs.Sub(staticFS, "static")
	if err != nil {
		log.Fatal(err)
	}

	http.Handle("/", http.FileServer(http.FS(sub)))

	log.Fatal(http.ListenAndServe(port, nil))
}

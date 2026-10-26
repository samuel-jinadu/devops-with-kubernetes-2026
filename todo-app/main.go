package main

import (
	"embed"
	"fmt"
	"html/template"
	"io"
	"log"
	"net/http"
	"os"
	"time"
)

//go:embed static
var staticFS embed.FS

type Todo struct {
	Title string
}

type PageData struct {
	Todos []Todo
	Now   time.Time
	Image string
}

func main() {
	port := os.Getenv("PORT")
	fmt.Printf("Server started on port %s\n", port)
	port = ":" + port

	http.Handle("/files/", http.StripPrefix("/files/", http.FileServer(http.Dir("/files"))))

	tmpl := template.Must(template.ParseFS(staticFS, "static/index.html"))

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		data := PageData{
			Todos: []Todo{
				{Title: "Learn Go templates"},
				{Title: "Add some CSS"},
				{Title: "Ship it"},
			},
			Now:   time.Now(),
			Image: os.Getenv("IMAGEPATH"),
		}

		if err := tmpl.Execute(w, data); err != nil {
			log.Println(err)
			http.Error(w, "template error", http.StatusInternalServerError)
		}
	})

	// http.Handle("/", http.FileServer(http.FS(sub)))
	go acquireImageLoop()
	log.Fatal(http.ListenAndServe(port, nil))

}

func acquireImageLoop() {
	for {
		resp, err := http.Get("https://picsum.photos/400/300")
		if err != nil || resp.StatusCode != 200 {
			log.Printf("There was an issue getting the hero image: %v\n", err)
			time.Sleep(10 * time.Minute)
			continue
		}

		filepath := os.Getenv("IMAGEPATH")

		file, err := os.Create(filepath)
		if err != nil {
			log.Printf("There was an issue writing the hero image to disk: %v\n", err)
			time.Sleep(10 * time.Minute)
			continue
		}
		bytesWritten, err := io.Copy(file, resp.Body)
		file.Close()      // Good practice to close the file!
		resp.Body.Close() // Close the network connection immediately
		if err != nil {
			log.Printf("There was an issue writing the hero image to disk: %v\n", err)
			time.Sleep(10 * time.Minute)
			continue
		}
		log.Printf("%d bytes written to disk at %s", bytesWritten, filepath)
		time.Sleep(10 * time.Minute)
	}
}

package main

import (
	"embed"
	"encoding/json"
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

type PageData struct {
	Todos   []string
	Now     time.Time
	Image   string
	PostURL string
}

func main() {
	port := os.Getenv("PORT")
	fmt.Printf("Server started on port %s\n", port)
	port = ":" + port

	http.Handle("/files/", http.StripPrefix("/files/", http.FileServer(http.Dir("/files"))))

	tmpl := template.Must(template.ParseFS(staticFS, "static/index.html"))

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		var todos []string

		resp, err := http.Get(os.Getenv("TODOSURL"))
		if err != nil {
			fmt.Printf("An error occurred when trying to get todos: %v\n", err)
			return
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			fmt.Printf("unexpected status: %s\n", resp.Status)
			return
		}

		if err := json.NewDecoder(resp.Body).Decode(&todos); err != nil {
			fmt.Printf("error decoding todos: %v\n", err)
			return
		}
		data := PageData{
			Todos:   todos,
			Now:     time.Now(),
			Image:   os.Getenv("IMAGEPATH"),
			PostURL: os.Getenv("POSTURL"),
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
	filepath := os.Getenv("IMAGEPATH")
	if fileinfo, err := os.Stat(filepath); err == nil {
		if elapsed := time.Since(fileinfo.ModTime()); elapsed < 10*time.Minute {
			time.Sleep(10*time.Minute - elapsed)
		}
	}
	for {
		resp, err := http.Get("https://picsum.photos/400/300")
		if err != nil || resp.StatusCode != 200 {
			log.Printf("There was an issue getting the hero image: %v\n", err)
			time.Sleep(10 * time.Minute)
			continue
		}

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

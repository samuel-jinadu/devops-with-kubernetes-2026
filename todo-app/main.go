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
	"strconv"
	"time"
)

//go:embed static
var staticFS embed.FS

type PageData struct {
	Todos   []string
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

	// Parse refresh interval (minutes) from env, default to 10 on error/empty.
	refreshMins, err := strconv.Atoi(os.Getenv("IMAGEREFRESHINTERVAL_MINS"))
	if err != nil || refreshMins <= 0 {
		log.Printf("IMAGEREFRESHINTERVAL_MINS invalid or unset (%q); defaulting to 10 minutes",
			os.Getenv("IMAGEREFRESHINTERVAL_MINS"))
		refreshMins = 10
	}
	refreshInterval := time.Duration(refreshMins) * time.Minute

	if fileinfo, err := os.Stat(filepath); err == nil {
		if elapsed := time.Since(fileinfo.ModTime()); elapsed < refreshInterval {
			time.Sleep(refreshInterval - elapsed)
		}
	}
	for {
		resp, err := http.Get(os.Getenv("RANDOMPIC_URL"))
		if err != nil || resp.StatusCode != 200 {
			log.Printf("There was an issue getting the hero image: %v\n", err)
			resp.Body.Close()
			time.Sleep(refreshInterval)
			continue
		}

		file, err := os.Create(filepath)
		if err != nil {
			log.Printf("There was an issue writing the hero image to disk: %v\n", err)
			resp.Body.Close()
			time.Sleep(refreshInterval)
			continue
		}
		bytesWritten, err := io.Copy(file, resp.Body)
		file.Close()      // Good practice to close the file!
		resp.Body.Close() // Close the network connection immediately
		if err != nil {
			log.Printf("There was an issue writing the hero image to disk: %v\n", err)
			time.Sleep(refreshInterval)
			continue
		}
		log.Printf("%d bytes written to disk at %s", bytesWritten, filepath)
		time.Sleep(refreshInterval)
	}
}

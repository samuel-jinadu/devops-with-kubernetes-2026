package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"uuid"
)

type UUIDResponse struct {
	StartingUUID string `json:"starting_uuid"`
	CurrentUUID  string `json:"current_uuid"`
}

func main() {
	port := os.Getenv("PORT")
	fmt.Printf("Server started on port %s\n", port)
	port = ":" + port
	startingUUID := uuid.New()
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		currentUUID := uuid.New()
		// fmt.Fprint(w, "Starting string:", startingUUID.String(), "Current string:", currentUUID.String(), "\n")
		json.NewEncoder(w).Encode(UUIDResponse{
			StartingUUID: startingUUID.String(),
			CurrentUUID:  currentUUID.String(),
		})
	})
	http.ListenAndServe(port, nil)
}

package main

import (
	"fmt"
	"time"
	"uuid"
)

func main() {
	payload := uuid.New()
	for {
		fmt.Printf("%s: %s\n", time.Now().UTC().String(), payload.String())
		time.Sleep(5 * time.Second)
	}

}

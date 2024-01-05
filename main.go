package main

import (
	"context"
	"fmt"
	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/sod-auctions/auctions-db"
	"github.com/sod-auctions/blizzard-client"
	"log"
	"os"
	"strconv"
)

var database *auctions_db.Database
var client *blizzard_client.BlizzardClient

func init() {
	log.SetFlags(0)
	var err error
	database, err = auctions_db.NewDatabase(os.Getenv("DB_CONNECTION_STRING"))
	if err != nil {
		fmt.Errorf("error connecting to database: %v\n", err)
		os.Exit(1)
	}

	client = blizzard_client.NewBlizzardClient(os.Getenv("BLIZZARD_CLIENT_ID"), os.Getenv("BLIZZARD_CLIENT_SECRET"))
}

func handler(ctx context.Context, event events.SQSEvent) error {
	for _, record := range event.Records {
		fmt.Printf("Retrieving data for item id: %s\n", record.Body)
		itemId, err := strconv.Atoi(record.Body)
		if err != nil {
			return fmt.Errorf("could not parse item id from message %s, %v", record.Body, err)
		}

		item, err := client.GetItem(int32(itemId))
		if err != nil {
			return fmt.Errorf("error while retrieving item data: %v", err)
		}

		mediaUrl, err := client.GetItemMedia(int32(itemId))
		if err != nil {
			return fmt.Errorf("error while fetching item media: %v", err)
		}

		dbItem := auctions_db.Item{
			Id:            item.Id,
			Name:          item.Name,
			MediaURL:      mediaUrl,
			Rarity:        item.Quality,
			Level:         item.Level,
			RequiredLevel: item.RequiredLevel,
			PurchasePrice: item.PurchasePrice,
			SellPrice:     item.SellPrice,
		}

		fmt.Printf("Inserting item: %v\n", dbItem)
		err = database.UpsertItem(&dbItem)
		if err != nil {
			return fmt.Errorf("error inserting item to db: %v", err)
		}
	}
	return nil
}

func main() {
	lambda.Start(handler)
}

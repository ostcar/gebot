package model

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"sort"
	"sync"
	"time"
)

type database interface {
	Reader() (io.ReadCloser, error)
	Append([]byte) error
}

// Model holds the data in memory and saves them to disk.
type Model struct {
	mu sync.RWMutex
	db database

	now func() time.Time

	lastID int

	// map from id to cent.
	gebote map[int]int
}

// New load the db from file.
func New(db database) (*Model, error) {
	dbReader, err := db.Reader()
	if err != nil {
		return nil, fmt.Errorf("open database: %w", err)
	}
	defer dbReader.Close()

	model, err := loadDatabase(dbReader)
	if err != nil {
		return nil, fmt.Errorf("loading database: %w", err)
	}

	model.db = db
	model.now = time.Now

	return model, nil
}

func loadDatabase(r io.Reader) (*Model, error) {
	db := Model{gebote: make(map[int]int)}

	scanner := bufio.NewScanner(r)
	for scanner.Scan() {
		line := bytes.TrimSpace(scanner.Bytes())
		if len(line) == 0 {
			continue
		}

		var typer struct {
			Type    string          `json:"type"`
			Time    string          `json:"time"`
			Payload json.RawMessage `json:"payload"`
		}
		if err := json.Unmarshal(line, &typer); err != nil {
			return nil, fmt.Errorf("decoding event: %w", err)
		}

		event := getEvent(typer.Type)
		if event == nil {
			return nil, fmt.Errorf("unknown event `%s`, payload `%s`", typer.Type, typer.Payload)
		}

		if err := json.Unmarshal(typer.Payload, &event); err != nil {
			return nil, fmt.Errorf("loading event `%s`: %w", typer.Type, err)
		}

		eventTime, err := time.Parse(timeFormat, typer.Time)
		if err != nil {
			return nil, fmt.Errorf("event `%s` has invalid time %s: %w", typer.Type, typer.Time, err)
		}

		if err = event.execute(&db, eventTime); err != nil {
			return nil, fmt.Errorf("executing event `%s`: %w", typer.Type, err)
		}
	}
	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("scanning events: %w", err)
	}

	return &db, nil
}

func (m *Model) writeEvent(e Event) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	if err := e.validate(m); err != nil {
		return fmt.Errorf("validating event: %w", err)
	}

	now := m.now().UTC()
	event := struct {
		Time    string `json:"time"`
		Type    string `json:"type"`
		Payload Event  `json:"payload"`
	}{
		now.Format(timeFormat),
		e.Name(),
		e,
	}

	bs, err := json.Marshal(event)
	if err != nil {
		return fmt.Errorf("encoding event: %w", err)
	}

	if err := m.db.Append(bs); err != nil {
		return fmt.Errorf("writing event to db: `%s`: %w", bs, err)
	}

	if err := e.execute(m, now); err != nil {
		return fmt.Errorf("executing event: %w", err)
	}

	return nil
}

func (m *Model) nextID() int {
	// TODO: This is not concurent save. There has probybly be a field model.maxID
	m.mu.Lock()
	defer m.mu.Unlock()

	nextID := 1
	for id := range m.gebote {
		if nextID <= id {
			nextID = id + 1
		}
	}
	return nextID
}

// Gebot adds a gebot.
func (m *Model) Gebot(cent int) (int, error) {
	log.Printf("Gebot event")
	id := m.nextID()
	if err := m.writeEvent(eventGebot{ID: id, Cent: cent}); err != nil {
		return 0, fmt.Errorf("writing event: %w", err)
	}
	return id, nil
}

// Delete removes an existing gebot.
func (m *Model) Delete(id int) error {
	log.Printf("delete event for %d", id)
	if err := m.writeEvent(eventDelete{ID: id}); err != nil {
		return fmt.Errorf("writing event: %w", err)
	}
	return nil
}

// Gebot is an id and cent.
type Gebot struct {
	ID   int `json:"id"`
	Cent int `json:"cent"`
}

// List returns all periodes.
func (m *Model) List() []Gebot {
	m.mu.RLock()
	defer m.mu.RUnlock()

	gebote := make([]Gebot, 0, len(m.gebote))
	for id, cent := range m.gebote {
		gebote = append(gebote, Gebot{id, cent})
	}
	sort.Slice(gebote, func(i, j int) bool {
		return gebote[i].ID < gebote[j].ID
	})
	return gebote
}

package model

import (
	"fmt"
	"time"
)

func getEvent(eventType string) Event {
	switch eventType {
	case eventGebot{}.Name():
		return &eventGebot{}

	case eventDelete{}.Name():
		return &eventDelete{}

	case eventReset{}.Name():
		return &eventReset{}

	default:
		return nil
	}
}

// Event is one change of the model.
//
// An implementation of an Event has to be able to be encoded to json.
type Event interface {
	validate(db *Model) error
	execute(db *Model, time time.Time) error
	Name() string
}

type eventGebot struct {
	ID   int `json:"id"`
	Cent int `json:"cent"`
}

func (e eventGebot) String() string {
	return fmt.Sprintf("Gebot %d cent", e.Cent)
}

func (e eventGebot) Name() string {
	return "gebot"
}

func (e eventGebot) validate(model *Model) error {
	if e.Cent <= 0 {
		return validationError{"Gebot muss größer als 0 sein."}
	}

	if _, ok := model.gebote[e.ID]; ok {
		return validationError{"Gebot mit id gibt es schon."}
	}
	return nil
}

func (e eventGebot) execute(model *Model, time time.Time) error {
	model.gebote[e.ID] = e.Cent
	return nil
}

type eventDelete struct {
	ID int `json:"id"`
}

func (e eventDelete) String() string {
	return fmt.Sprintf("Delete gebot %d", e.ID)
}

func (e eventDelete) Name() string {
	return "delete"
}

func (e eventDelete) validate(model *Model) error {
	if _, ok := model.gebote[e.ID]; !ok {
		return validationError{"Gebot mit id gibt es schon."}
	}
	return nil
}

func (e eventDelete) execute(model *Model, time time.Time) error {
	delete(model.gebote, e.ID)
	return nil
}

type eventReset struct{}

func (e eventReset) String() string {
	return "Reset"
}

func (e eventReset) Name() string {
	return "reset"
}

func (e eventReset) validate(model *Model) error {
	return nil
}

func (e eventReset) execute(model *Model, time time.Time) error {
	model.gebote = make(map[int]int)
	return nil
}

type validationError struct {
	msg string
}

func (e validationError) Error() string {
	return e.msg
}

func (e validationError) forClient() string {
	return "Ungültige Daten: " + e.msg
}

package main

import (
	"fmt"
	"strings"
)

// Stack is a generic stack.
type Stack[T any] struct {
	items []T
}

type Shape interface {
	Area() float64
}

const (
	Pi    = 3.14159
	Limit = 1 << 10
)

func (s *Stack[T]) Push(v T) { s.items = append(s.items, v) }

func divide(a, b float64) (float64, error) {
	if b == 0 {
		return 0, fmt.Errorf("divide %v by zero", a)
	}
	return a / b, nil
}

func main() {
	var raw = `raw string
with newline \n`
	s := &Stack[int]{}
	s.Push(1)
	ch := make(chan int, 3)
	go func() { ch <- 42 }()
	select {
	case v := <-ch:
		fmt.Println("got", v, 'x', "tab\t")
	default:
	}
	for i, r := range strings.Split("a,b", ",") {
		defer fmt.Println(i, r)
	}
	_ = raw
}

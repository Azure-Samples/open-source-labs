// Command password prints a random password and its bcrypt hash, for the Dex
// static password this lab configures.
//
// The character mix matches what the lab used before: 32 characters made of 12
// letters, 10 digits and 10 symbols, sampled without replacement so no
// character repeats, then shuffled. Randomness comes from crypto/rand.
package main

import (
	"crypto/rand"
	"fmt"
	"math/big"
	"os"

	"golang.org/x/crypto/bcrypt"
)

const (
	letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
	digits  = "0123456789"
	symbols = "~!@#$%^&*()_+`-={}|[]\\:\"<>?,./"

	letterCount = 12
	digitCount  = 10
	symbolCount = 10

	bcryptCost = 12
)

// take draws n distinct runes from pool without replacement.
func take(pool []rune, n int) ([]rune, []rune, error) {
	out := make([]rune, 0, n)
	for i := 0; i < n; i++ {
		idx, err := rand.Int(rand.Reader, big.NewInt(int64(len(pool))))
		if err != nil {
			return nil, nil, err
		}
		j := idx.Int64()
		out = append(out, pool[j])
		pool = append(pool[:j], pool[j+1:]...)
	}
	return out, pool, nil
}

func generate() (string, error) {
	var picked []rune
	for _, set := range []struct {
		pool  string
		count int
	}{
		{letters, letterCount},
		{digits, digitCount},
		{symbols, symbolCount},
	} {
		got, _, err := take([]rune(set.pool), set.count)
		if err != nil {
			return "", err
		}
		picked = append(picked, got...)
	}

	// Shuffle by drawing the whole set without replacement again, so the three
	// character classes are not left grouped in order.
	shuffled, _, err := take(picked, len(picked))
	if err != nil {
		return "", err
	}
	return string(shuffled), nil
}

func main() {
	password, err := generate()
	if err != nil {
		fmt.Fprintf(os.Stderr, "password: %v\n", err)
		os.Exit(1)
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcryptCost)
	if err != nil {
		fmt.Fprintf(os.Stderr, "password: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("Password: %s\nHash: %s\n", password, hash)
}

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
	"regexp"

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

var bcryptPattern = regexp.MustCompile(`^\$2[aby]\$[0-9]{2}\$[./A-Za-z0-9]{53}$`)

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

func validateBcryptHash(hash string) error {
	if !bcryptPattern.MatchString(hash) {
		return fmt.Errorf("expected a 60-character bcrypt hash")
	}
	cost, err := bcrypt.Cost([]byte(hash))
	if err != nil {
		return fmt.Errorf("invalid bcrypt hash: %w", err)
	}
	if cost != bcryptCost {
		return fmt.Errorf("bcrypt cost is %d, want %d", cost, bcryptCost)
	}
	return nil
}

func main() {
	if len(os.Args) == 3 && os.Args[1] == "--validate-hash" {
		if err := validateBcryptHash(os.Args[2]); err != nil {
			fmt.Fprintf(os.Stderr, "password: refusing invalid Dex password hash: %v\n", err)
			os.Exit(1)
		}
		return
	}
	machineOutput := len(os.Args) == 2 && os.Args[1] == "--machine"
	if len(os.Args) != 1 && !machineOutput {
		fmt.Fprintln(os.Stderr, "usage: password [--machine | --validate-hash HASH]")
		os.Exit(2)
	}

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

	if machineOutput {
		fmt.Printf("%s\n%s\n", password, hash)
		return
	}
	fmt.Printf("Password: %s\nHash: %s\n", password, hash)
}

package main

import (
	"strings"
	"testing"

	"golang.org/x/crypto/bcrypt"
)

func TestGenerate(t *testing.T) {
	for i := 0; i < 100; i++ {
		password, err := generate()
		if err != nil {
			t.Fatalf("generate password %d: %v", i, err)
		}

		runes := []rune(password)
		if len(runes) != letterCount+digitCount+symbolCount {
			t.Fatalf("password %d has %d characters, want 32", i, len(runes))
		}

		seen := make(map[rune]struct{}, len(runes))
		counts := map[string]int{"letters": 0, "digits": 0, "symbols": 0}
		for _, character := range runes {
			if _, exists := seen[character]; exists {
				t.Fatalf("password %d repeats character %q", i, character)
			}
			seen[character] = struct{}{}

			switch {
			case strings.ContainsRune(letters, character):
				counts["letters"]++
			case strings.ContainsRune(digits, character):
				counts["digits"]++
			case strings.ContainsRune(symbols, character):
				counts["symbols"]++
			default:
				t.Fatalf("password %d contains unexpected character %q", i, character)
			}
		}

		if counts["letters"] != letterCount ||
			counts["digits"] != digitCount ||
			counts["symbols"] != symbolCount {
			t.Fatalf(
				"password %d has letters=%d digits=%d symbols=%d, want %d/%d/%d",
				i,
				counts["letters"],
				counts["digits"],
				counts["symbols"],
				letterCount,
				digitCount,
				symbolCount,
			)
		}

		hash, err := bcrypt.GenerateFromPassword([]byte(password), bcryptCost)
		if err != nil {
			t.Fatalf("hash password %d: %v", i, err)
		}
		cost, err := bcrypt.Cost(hash)
		if err != nil {
			t.Fatalf("read bcrypt cost %d: %v", i, err)
		}
		if cost != bcryptCost {
			t.Fatalf("password %d has bcrypt cost %d, want %d", i, cost, bcryptCost)
		}
		if err := bcrypt.CompareHashAndPassword(hash, []byte(password)); err != nil {
			t.Fatalf("verify password %d: %v", i, err)
		}
	}
}

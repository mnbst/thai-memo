package main

import (
	"context"
	"strings"
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/embeddings"
)

func TestFixedShot(t *testing.T) {
	shots := []embeddings.Shot{
		{ID: "ub_04", Text: "known"},
		{ID: "ub_05", Text: "known too"},
	}

	got, err := fixedShot("ub_05").FindBestDramaShot(context.Background(), "", shots)
	if err != nil {
		t.Fatalf("known ID returned error: %v", err)
	}
	if got != "ub_05" {
		t.Fatalf("got %q, want ub_05", got)
	}

	got, err = fixedShot("ub_99").FindBestDramaShot(context.Background(), "", shots)
	if err == nil || !strings.Contains(err.Error(), "ub_99") {
		t.Fatalf("unknown ID error = %v, want error containing ub_99", err)
	}
	if got != "" {
		t.Fatalf("unknown ID returned %q, want empty", got)
	}
}

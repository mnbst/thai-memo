package corpustrans

import "testing"

func TestValidateEN(t *testing.T) {
	ng := []string{
		"You go home question particle.",
		"Return this one classifier.",
		"He/she go home.",
		"I go บ้าน.",
		"I go home",
	}
	for _, s := range ng {
		if err := validateEN(s); err == nil {
			t.Errorf("通ってはいけない: %q", s)
		}
	}
	ok := []string{
		"I do not think that you like me.",
		"Do you watch movie every Sunday?",
		"You splash water hard!",
	}
	for _, s := range ok {
		if err := validateEN(s); err != nil {
			t.Errorf("通るべき: %q → %v", s, err)
		}
	}
}

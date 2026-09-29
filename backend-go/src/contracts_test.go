package main

import (
	"os"
	"regexp"
	"testing"
)

// dartEventsPath é o arquivo Dart que declara o mesmo contrato de eventos.
const dartEventsPath = "../../packages/drawly_core/lib/src/contracts/socket_events.dart"

// TestEventContractMatchesDart garante que os nomes de evento declarados no Go
// e no Dart são exatamente os mesmos.
//
// É o teste que impede a classe de bug mais silenciosa do projeto: um lado
// renomeia um evento, o outro não, e a mensagem simplesmente nunca chega —
// sem erro de compilação, sem exceção em runtime.
func TestEventContractMatchesDart(t *testing.T) {
	source, err := os.ReadFile(dartEventsPath)
	if err != nil {
		t.Fatalf("não foi possível ler o contrato Dart em %s: %v", dartEventsPath, err)
	}

	// Captura o valor de cada `static const nome = 'valor';`
	pattern := regexp.MustCompile(`static const \w+ = '([^']+)';`)
	matches := pattern.FindAllStringSubmatch(string(source), -1)

	dartEvents := make(map[string]bool, len(matches))
	for _, match := range matches {
		dartEvents[match[1]] = true
	}

	if len(dartEvents) == 0 {
		t.Fatal("nenhum evento encontrado no contrato Dart — regex desatualizada?")
	}

	goEvents := make(map[string]bool, len(AllEvents))
	for _, event := range AllEvents {
		goEvents[event] = true
	}

	for event := range goEvents {
		if !dartEvents[event] {
			t.Errorf("evento %q existe no Go mas não no Dart", event)
		}
	}
	for event := range dartEvents {
		if !goEvents[event] {
			t.Errorf("evento %q existe no Dart mas não no Go", event)
		}
	}
}

// TestAllEventsHasNoDuplicates protege contra copiar/colar uma entrada em
// AllEvents e esquecer de trocar a constante.
func TestAllEventsHasNoDuplicates(t *testing.T) {
	seen := make(map[string]bool, len(AllEvents))
	for _, event := range AllEvents {
		if seen[event] {
			t.Errorf("evento duplicado em AllEvents: %q", event)
		}
		seen[event] = true
	}
}

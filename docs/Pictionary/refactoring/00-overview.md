# Refatoração Drawly — Visão Geral

> Documento vivo. Atualize o status ao concluir cada fase.

## Diagnóstico em uma frase

O projeto tem boas ideias de separação (3 packages, backend próprio, golden tests), mas
**nenhuma delas era executável**: na data da auditoria, o app não resolvia dependências,
os 13 arquivos de teste do Go nunca compilaram, e a suíte inteira do `drawing_board`
falhava no compilador. Cobertura real efetiva: **próxima de zero**.

A causa raiz não é falta de estrutura — é **falta de inversão de dependência no limite de
I/O**. `SocketManager` é um singleton que abre socket para `localhost:5555` no construtor,
e cada widget o chama diretamente. Isso torna quase tudo intestável, e o que é intestável
apodrece.

## Princípio que guia o plano

```
destravar build → criar seams → cobrir com testes → só então refatorar
```

Refatorar antes de ter cobertura é apostar que nada quebra. Com 12k linhas e regra de jogo
distribuída entre cliente e servidor, essa aposta se perde.

## Fases

| Fase | Objetivo | Doc | Status |
|---|---|---|---|
| 0 | Destravar build e suítes | [02-fase-0-destravar.md](02-fase-0-destravar.md) | ✅ concluída |
| 1 | Seams de testabilidade (mínimos, cirúrgicos) | [03-fase-1-seams.md](03-fase-1-seams.md) | ✅ concluída |
| 2 | Cobertura alta sobre o que existe hoje | [04-fase-2-cobertura.md](04-fase-2-cobertura.md) | 🔄 em andamento |
| 3 | Refatoração arquitetural (Dart) | [05-fase-3-arquitetura-dart.md](05-fase-3-arquitetura-dart.md) | ⏳ |
| 4 | Refatoração arquitetural (Go) | [06-fase-4-arquitetura-go.md](06-fase-4-arquitetura-go.md) | ⏳ |
| 5 | Higiene contínua (CI, config, release) | [07-fase-5-higiene.md](07-fase-5-higiene.md) | 🔄 em andamento |

Detalhe dos problemas encontrados: [01-achados.md](01-achados.md).
Desenho do estado final: [08-arquitetura-alvo.md](08-arquitetura-alvo.md).
Plano do sistema de desenho (protocolo, modelo, render): [10-sistema-de-desenho.md](10-sistema-de-desenho.md); etapas seguintes em [11-desenho-etapas-seguintes.md](11-desenho-etapas-seguintes.md),
ciclo do turno em [12-ciclo-do-turno.md](12-ciclo-do-turno.md) e operação/custo em [13-operacao-e-custo.md](13-operacao-e-custo.md).
**Onde estamos agora: [09-estado-atual.md](09-estado-atual.md).**

## Regras de execução

1. **Uma fase por vez.** Não começar a 3 com a 2 incompleta.
2. **Commit pequeno**, no formato do [CLAUDE.md](../../../CLAUDE.md) §9.
3. **Todo refactor da fase 3+ é precedido por teste** que trava o comportamento atual.
4. Se um teste da fase 2 documenta um comportamento **errado**, o teste registra o
   comportamento atual com um `// BUG(#n):` apontando para o achado, e a correção vira
   um commit `fix:` separado. Não corrigir bug e refatorar no mesmo passo.

## Escopo explicitamente fora (YAGNI)

Descartados de propósito, para não inflar um projeto solo:

- Injeção de dependência por container (`get_it`, `injectable`) — construtor resolve.
- Code generation (`freezed`, `json_serializable`) — o volume de DTOs não justifica
  a complexidade de build. Reavaliar se passar de ~25 DTOs.
- Gerenciador de estado externo (bloc/riverpod) — `ChangeNotifier`/`ValueNotifier` já
  cobrem o caso e o app não tem estado global complexo.
- Monorepo tooling (melos) — 3 packages e um script bash bastam.
- Event sourcing / CQRS no backend — o jogo é efêmero e cabe em memória.

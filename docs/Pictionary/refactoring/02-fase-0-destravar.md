# Fase 0 — Destravar build e suítes

**Status: ✅ concluída**

Objetivo: sair de "nada compila" para "todas as suítes rodam". Nenhuma mudança de
comportamento de produto além do necessário para compilar.

## Ações executadas

| # | Ação | Achado | Efeito |
|---|---|---|---|
| 1 | Remover dependência `fluo` (path inexistente) do `pubspec.yaml` raiz | B1 | `flutter pub get` volta a resolver |
| 2 | Mover `backend-go/tests/*_test.go` → `backend-go/src/` | B2 | 13 arquivos de teste passam a compilar e rodar |
| 3 | Extrair `disconnectParticipant(io, clientID string)` de `handleParticipantDisconnect` | B2 | permite testar desconexão sem construir `*socket.Socket` (campo `id` é não exportado) |
| 4 | Tornar a tolerância de reconexão injetável (`disconnectGraceDelay`) | B2 | teste deixa de depender de `sleep(6s)` |
| 5 | Trocar `font_awesome_flutter` por `Icons.*` (6 ícones) e remover a dependência | B3 | suíte do `drawing_board` compila; −1 dependência, −1 fonte no bundle |
| 6 | Remover `file_picker`, `file_saver`, `image_picker`, `universal_html`, `url_launcher` de `drawing_board` | H5 | dependências declaradas e nunca importadas |
| 7 | Deletar os 4 arquivos `*copy*.dart` | B4 | −365 linhas mortas |
| 8 | Corrigir `const` inválido em `polygon_utils_test.dart` | B3 | arquivo voltou a compilar no Dart atual |

### Mapeamento de ícones (ação 5)

| Antes | Depois |
|---|---|
| `FontAwesomeIcons.pencil` | `Icons.edit_outlined` |
| `FontAwesomeIcons.square` | `Icons.crop_square` |
| `FontAwesomeIcons.circle` | `Icons.circle_outlined` |
| `FontAwesomeIcons.bucket` | `Icons.format_color_fill` |
| `FontAwesomeIcons.eraser` | `Icons.auto_fix_normal` |
| `FontAwesomeIcons.ruler` | `Icons.straighten` |

Nenhum golden cobre a sidebar (os goldens são só do `DrawingCanvas`), então a troca é
visualmente segura do ponto de vista da suíte.

## Resultado

| Suíte | Antes | Depois |
|---|---|---|
| `backend-go` | não compilava | ✅ verde |
| `drawly_design_system` | ✅ 2 testes | ✅ 2 testes |
| `drawing_board` | não compilava (8 arquivos) | compila; goldens de gesto falham por R9 |
| app (`test/`) | `pub get` falhava | resolve |

## Pendência herdada para a fase 2

Os goldens de gesto continuam vermelhos, e **isso está correto**: eles documentam um
comportamento que o código não entrega mais (achado R9 — o traço em progresso não é
pintado). Não serão regerados com `--update-goldens` para "ficar verde"; serão
reescritos na fase 2 para semear `rxAllStrokes`, que é a fonte real do render.

Comparação salva em `packages/drawing_board/test/presentation/widgets/failures/`
mostra claramente: `*_masterImage.png` tem a figura, `*_testImage.png` tem canvas vazio.

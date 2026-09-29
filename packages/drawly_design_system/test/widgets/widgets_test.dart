import 'package:drawly_design_system/drawly_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('DrawlyContainer', () {
    testWidgets('renderiza o filho', (tester) async {
      await tester.pumpWidget(
        _wrap(const DrawlyContainer(child: Text('conteúdo'))),
      );

      expect(find.text('conteúdo'), findsOneWidget);
    });

    testWidgets('usa branco quando nenhuma cor é informada', (tester) async {
      await tester.pumpWidget(_wrap(const DrawlyContainer()));

      final decoration = tester
          .widget<Container>(find.byType(Container))
          .decoration! as BoxDecoration;

      expect(decoration.color, Colors.white);
    });

    testWidgets('respeita a cor e a borda informadas', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const DrawlyContainer(
            color: AppColors.greenAccent,
            borderColor: AppColors.redAccent,
          ),
        ),
      );

      final decoration = tester
          .widget<Container>(find.byType(Container))
          .decoration! as BoxDecoration;

      expect(decoration.color, AppColors.greenAccent);
      expect(decoration.border, isNotNull);
    });

    testWidgets('aplica largura e altura', (tester) async {
      await tester.pumpWidget(
        _wrap(const DrawlyContainer(width: 120, height: 80)),
      );

      // getSize incluiria a margem que o DrawlyContainer aplica; a asserção é
      // sobre as dimensões pedidas, não sobre a caixa externa.
      final container = tester.widget<Container>(find.byType(Container));

      expect(container.constraints?.maxWidth, 120);
      expect(container.constraints?.maxHeight, 80);
    });
  });

  group('DrawlyTitleContainer', () {
    testWidgets('exibe o texto', (tester) async {
      await tester.pumpWidget(
        _wrap(const DrawlyTitleContainer(text: 'Vez de Kevin')),
      );

      expect(find.text('Vez de Kevin'), findsOneWidget);
    });

    testWidgets('usa branco sobre azul por padrão', (tester) async {
      await tester.pumpWidget(_wrap(const DrawlyTitleContainer(text: 'x')));

      expect(
        tester.widget<Text>(find.text('x')).style!.color,
        Colors.white,
      );
    });

    testWidgets('aceita cores customizadas', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const DrawlyTitleContainer(
            text: 'x',
            textColor: AppColors.black,
            color: AppColors.yellowAccent,
          ),
        ),
      );

      expect(
        tester.widget<Text>(find.text('x')).style!.color,
        AppColors.black,
      );
    });
  });

  group('DrawlyChatTextField', () {
    testWidgets('aceita digitação', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _wrap(
          DrawlyChatTextField(
            controller: controller,
            leftIcon: Icons.question_answer,
            rightIcon: Icons.send,
            onRightIconPressed: () {},
            disabled: false,
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'olá');

      expect(controller.text, 'olá');
    });

    testWidgets('dispara o callback do ícone da direita', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      var pressionado = false;

      await tester.pumpWidget(
        _wrap(
          DrawlyChatTextField(
            controller: controller,
            leftIcon: Icons.question_answer,
            rightIcon: Icons.send,
            onRightIconPressed: () => pressionado = true,
            disabled: false,
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.send));

      expect(pressionado, isTrue);
    });

    testWidgets('desabilitado não aceita digitação', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _wrap(
          DrawlyChatTextField(
            controller: controller,
            leftIcon: Icons.question_answer,
            rightIcon: Icons.send,
            onRightIconPressed: () {},
            disabled: true,
          ),
        ),
      );

      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    });
  });

  group('DrawlyBarGrid', () {
    testWidgets('renderiza todos os filhos', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const DrawlyBarGrid(
            children: [Text('a'), Text('b'), Text('c')],
          ),
        ),
      );

      expect(find.text('a'), findsOneWidget);
      expect(find.text('b'), findsOneWidget);
      expect(find.text('c'), findsOneWidget);
    });

    testWidgets('aceita lista vazia', (tester) async {
      await tester.pumpWidget(_wrap(const DrawlyBarGrid(children: [])));

      expect(tester.takeException(), isNull);
    });
  });

  group('DrawlyBackFilter', () {
    testWidgets('renderiza o filho por cima do desfoque', (tester) async {
      await tester.pumpWidget(
        _wrap(const DrawlyBackFilter(child: Text('sobreposto'))),
      );

      expect(find.text('sobreposto'), findsOneWidget);
      expect(find.byType(BackdropFilter), findsOneWidget);
    });
  });

  group('DrawlyResponsiveFading', () {
    testWidgets('renderiza o filho', (tester) async {
      await tester.pumpWidget(
        _wrap(const DrawlyResponsiveFading(child: Text('esmaecido'))),
      );
      await tester.pump();

      expect(find.text('esmaecido'), findsOneWidget);
    });
  });

  group('AppColors', () {
    test('a paleta de destaque tem quatro cores distintas', () {
      expect(AppColors.accentColors, hasLength(4));
      expect(AppColors.accentColors.toSet(), hasLength(4));
    });

    test('transparente é de fato transparente', () {
      expect(AppColors.transparent.a, 0);
    });
  });

  group('lightTheme', () {
    testWidgets('é aplicável a um MaterialApp', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: lightTheme,
          home: const Scaffold(body: Text('tema')),
        ),
      );

      expect(find.text('tema'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

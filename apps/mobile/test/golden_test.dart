import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seychas/core/theme/app_theme.dart';
import 'package:seychas/core/widgets/app_widgets.dart';

void main() {
  testWidgets(
    'privacy promise card golden',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 240));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(20),
              child: GlassPanel(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.shield_rounded, color: AppColors.mint),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Точное место выключено по умолчанию и исчезает после комнаты.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/privacy_card.png'),
      );
      await tester.binding.setSurfaceSize(null);
    },
    // Font rasterization differs between the Windows development host and
    // GitHub's Linux runner. The semantic/widget coverage remains active on
    // Linux; the pixel baseline is verified on the development platforms.
    skip: Platform.isLinux,
  );
}

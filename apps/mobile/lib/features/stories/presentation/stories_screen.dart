import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

class StoriesScreen extends StatelessWidget {
  const StoriesScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Истории')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.mint, width: 3),
              ),
              alignment: Alignment.topRight,
              child: const CircleAvatar(
                radius: 4,
                backgroundColor: AppColors.mint,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Истории близких — следующий этап',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            const Text(
              'Здесь не показаны фиктивные публикации: доступ, срок жизни и просмотры будут подключены вместе с защищённым API.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ),
  );
}

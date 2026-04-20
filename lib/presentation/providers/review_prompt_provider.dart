import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/review_prompt_service.dart';

final reviewPromptServiceProvider = Provider<ReviewPromptService>((ref) {
  return ReviewPromptService();
});

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../users/state/users_providers.dart';
import '../data/posts_api.dart';

final postsApiProvider = Provider<PostsApi>((ref) {
  return PostsApi(ref.watch(apiClientProvider).dio);
});

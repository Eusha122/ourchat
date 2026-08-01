import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../users/state/users_providers.dart';
import '../data/albums_api.dart';

final albumsApiProvider = Provider<AlbumsApi>((ref) {
  return AlbumsApi(ref.watch(apiClientProvider).dio);
});

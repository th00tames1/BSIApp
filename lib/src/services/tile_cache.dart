import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

/// Serves map tiles through cached_network_image so tiles fetched once are
/// kept on disk and remain visible offline (현장에서 네트워크가 끊겨도 이미 본
/// 영역은 표시됨). New/unseen tiles still need a connection.
class CachedTileProvider extends TileProvider {
  CachedTileProvider({super.headers});

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return CachedNetworkImageProvider(
      getTileUrl(coordinates, options),
      headers: headers,
    );
  }
}

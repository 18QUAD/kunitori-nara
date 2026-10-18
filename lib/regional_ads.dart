import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'game.dart';

String? advertisingCity(
  Game game, {
  String? selectedTown,
  String? selectedCity,
  String? selectedPrefecture,
}) {
  return game.tipsCityFor(
    selectedTown: selectedTown,
    selectedCity: selectedCity,
    selectedPrefecture: selectedPrefecture,
  );
}

class RegionalAd {
  const RegionalAd({
    required this.cityId,
    required this.category,
    required this.name,
    required this.advertiser,
    required this.url,
    this.imageUrl,
  });

  final String cityId, category, name, advertiser;
  final Uri url;
  final Uri? imageUrl;

  String get service => category == 'hotel' ? '楽天トラベル' : '楽天市場';
  String get label => switch (category) {
    'hotel' => '宿泊',
    'furusato' => 'ふるさと納税',
    _ => '地元企業',
  };

  static RegionalAd? parse(dynamic value, String cityId) {
    if (value is! Map || value['cityId'] != cityId) return null;
    final category = value['category'];
    final name = value['name'];
    final advertiser = value['advertiser'];
    final url = Uri.tryParse(value['url']?.toString() ?? '');
    if (!['product', 'furusato', 'hotel'].contains(category) ||
        name is! String ||
        name.trim().isEmpty ||
        advertiser is! String ||
        advertiser.trim().isEmpty ||
        url == null ||
        url.scheme != 'https' ||
        url.host != 'hb.afl.rakuten.co.jp' ||
        url.userInfo.isNotEmpty) {
      return null;
    }
    final image = Uri.tryParse(value['imageUrl']?.toString() ?? '');
    final safeImage =
        image != null &&
        image.scheme == 'https' &&
        image.userInfo.isEmpty &&
        (image.host == 'thumbnail.image.rakuten.co.jp' ||
            image.host == 'image.rakuten.co.jp' ||
            image.host == 'img.travel.rakuten.co.jp');
    return RegionalAd(
      cityId: cityId,
      category: category as String,
      name: name,
      advertiser: advertiser,
      url: url,
      imageUrl: safeImage ? image : null,
    );
  }
}

class RegionalAdBatch {
  const RegionalAdBatch(this.ads, this.expiresAt);
  final List<RegionalAd> ads;
  final DateTime expiresAt;
}

class RegionalAdRepository {
  RegionalAdRepository(this.endpoint, {http.Client? client})
    : _client = client ?? http.Client();
  final Uri? endpoint;
  final http.Client _client;
  final _cache = <String, RegionalAdBatch>{};
  final _pending = <String, Future<RegionalAdBatch>>{};

  static Future<RegionalAdRepository> configured() async {
    try {
      final config =
          jsonDecode(
                await rootBundle.loadString(
                  'assets/data/affiliate_config.json',
                ),
              )
              as Map<String, dynamic>;
      const override = String.fromEnvironment('REGIONAL_ADS_ENDPOINT');
      final value = override.isEmpty ? config['endpoint'] as String : override;
      final uri = Uri.tryParse(value);
      return RegionalAdRepository(
        uri != null && uri.scheme == 'https' && uri.host.isNotEmpty
            ? uri
            : null,
      );
    } catch (_) {
      return RegionalAdRepository(null);
    }
  }

  Future<RegionalAdBatch> load(String cityId) {
    _cache.removeWhere((_, value) => !DateTime.now().isBefore(value.expiresAt));
    final cached = _cache.remove(cityId);
    if (cached != null && DateTime.now().isBefore(cached.expiresAt)) {
      _cache[cityId] = cached;
      return Future.value(cached);
    }
    return _pending.putIfAbsent(
      cityId,
      () => _fetch(cityId).whenComplete(() {
        _pending.remove(cityId);
        while (_cache.length > 3) {
          _cache.remove(_cache.keys.first);
        }
      }),
    );
  }

  Future<RegionalAdBatch> _fetch(String cityId) async {
    final now = DateTime.now();
    final empty = RegionalAdBatch(
      const [],
      now.add(const Duration(minutes: 5)),
    );
    if (endpoint == null ||
        !RegExp(r'^(?:0[1-9]|[1-3]\d|4[0-7])\d{3}$').hasMatch(cityId)) {
      return empty;
    }
    try {
      final uri = endpoint!.replace(
        queryParameters: {...endpoint!.queryParameters, 'city': cityId},
      );
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 45));
      if (response.statusCode != 200) return _cache[cityId] = empty;
      final data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (data['cityId'] != cityId) return _cache[cityId] = empty;
      final expires = DateTime.parse(data['expiresAt'] as String);
      if (!expires.isAfter(now) ||
          expires.isAfter(now.add(const Duration(hours: 1, minutes: 1)))) {
        return _cache[cityId] = empty;
      }
      final ads =
          (data['ads'] as List)
              .map((v) => RegionalAd.parse(v, cityId))
              .whereType<RegionalAd>()
              .take(9)
              .toList();
      return _cache[cityId] = RegionalAdBatch(ads, expires);
    } catch (_) {
      return _cache[cityId] = empty;
    }
  }

  void dispose() => _client.close();
}

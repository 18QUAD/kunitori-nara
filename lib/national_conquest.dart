import 'game.dart';
import 'municipal_office.dart';

const nationalOfficeSource =
    'https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-P05-v3_0.html';

/// Extend the existing five-question conquest rules using the resident census
/// metadata. No detailed geometry or external quiz download is required.
void enableNationalConquest(Atlas atlas, Map<String, String> prefectures) {
  for (final city in atlas.cities.entries.where(
    (c) => !c.key.startsWith('29'),
  )) {
    final towns = atlas.byCity[city.key]!;
    final marker = atlas.mapOffices[city.key]!;
    var largest = towns.first;
    var population = 0;
    for (final town in towns) {
      population += town.population;
      if (town.population > largest.population ||
          (town.population == largest.population &&
              town.id.compareTo(largest.id) < 0)) {
        largest = town;
      }
    }
    // Three island municipalities have headquarters outside their territory.
    // Keep their real markers intact; use the most populated game town as an
    // explicitly named conquest hub instead of inventing an office location.
    final hub = marker.townId ?? largest.id;
    atlas.officeTownIds[city.key] = hub;
    atlas.offices[city.key] = MunicipalOffice(
      city.key,
      marker.name,
      atlas.membersByTown[hub]!.first.id,
      marker.address,
      nationalOfficeSource,
      marker.point.x,
      marker.point.y,
      isCityOffice: marker.isCity,
      usesConquestHub: marker.townId == null,
    );
    final prefecture = prefectures[city.key.substring(0, 2)]!;
    final maxNames =
        towns
            .where((t) => t.population == largest.population)
            .map((t) => t.name)
            .toSet();
    final largestDecoys = <String>{};
    for (final name in [
      ...towns
          .where((t) => t.population < largest.population)
          .map((t) => t.name),
      ...atlas.cities.values.take(12),
    ]) {
      if (!maxNames.contains(name)) largestDecoys.add(name);
      if (largestDecoys.length == 3) break;
    }
    final location = atlas.towns[hub]!.name;
    final locationDecoys = <String>{};
    for (final name in [
      ...towns.map((t) => t.name),
      ...atlas.cities.values.take(12),
    ]) {
      if (name != location) locationDecoys.add(name);
      if (locationDecoys.length == 3) break;
    }
    // Old placeholder IDs can already occur in reading history.
    atlas.additionalFactIds.addAll(atlas.facts[city.key]!.map((f) => f.id));
    atlas.facts[city.key] = [
      LocalFact(
        '${city.key}:conquest:count',
        city.key,
        '地理',
        '${city.value}の攻略対象は${towns.length}町です。全領土を獲得すると制圧クイズに挑戦できます。',
        '${city.value}の攻略対象は何町？',
        '${towns.length}町',
        _numericDecoys(towns.length, '町'),
        Atlas.censusSource,
      ),
      LocalFact(
        '${city.key}:conquest:population',
        city.key,
        '統計',
        '${city.value}の収録地域の人口合計は${number(population)}人。2020年国勢調査に基づきます。',
        '${city.value}の収録地域の人口合計は？',
        '${number(population)}人',
        _numericDecoys(population, '人'),
        Atlas.censusSource,
      ),
      LocalFact(
        '${city.key}:conquest:largest',
        city.key,
        '地域',
        '${city.value}で収録人口が最も多い町${maxNames.length > 1 ? 'の一つ' : ''}は${largest.name}（${number(largest.population)}人）です。',
        '${city.value}で収録人口が最も多い町${maxNames.length > 1 ? 'の一つ' : ''}は？',
        largest.name,
        largestDecoys.toList(),
        Atlas.censusSource,
      ),
      LocalFact(
        '${city.key}:conquest:prefecture',
        city.key,
        '地理',
        '${city.value}がある都道府県は$prefectureです。',
        '${city.value}がある都道府県は？',
        prefecture,
        prefectures.values.where((p) => p != prefecture).take(3).toList(),
        Atlas.censusSource,
      ),
      LocalFact(
        '${city.key}:conquest:office',
        city.key,
        '制圧クイズ',
        marker.townId == null
            ? '${marker.name}は区域外にあるため、$locationを制圧拠点にします。'
            : '${marker.name}がある町は$location。全領土獲得後、ここから制圧クイズに挑戦できます。',
        '${city.value}の制圧クイズに挑戦する町は？',
        location,
        locationDecoys.toList(),
        nationalOfficeSource,
      ),
    ];
  }
}

List<String> _numericDecoys(int answer, String unit) =>
    {
      for (final n in [
        answer ~/ 2,
        answer * 2,
        answer * 3,
        answer + 1,
        answer + 2,
        answer + 3,
      ])
        if (n != answer) '${number(n)}$unit',
    }.take(3).toList();

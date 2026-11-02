import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/national_atlas.dart';
void main() {
 TestWidgetsFlutterBinding.ensureInitialized();
 test('export exact game graph and separate legacy migration records', () async {
 final n=await NationalAtlas.loadUnpackedForBuild();final a=n.atlas;
 final raw=jsonDecode(File('assets/data/japan.json').readAsStringSync()) as Map<String,dynamic>;
 final needed=<String>{...a.mapOffices.values.map((o)=>o.townId).whereType<String>(),...a.offices.values.map((o)=>o.sourceTownId)};
 final office=jsonDecode(File('assets/data/japan_offices.json').readAsStringSync());
 for(final o in office['offices']) {if(o['sourceTownId']!=null)needed.add(o['sourceTownId']);}
 final data={'schema':1,'cities':a.cities,'prefectures':raw['prefectures'],
 'towns':[for(final t in a.towns.values)[t.id,t.name,t.cityId,t.population,t.area,t.neighbors.toList()]],
 'officeAliases':{for(final id in needed)if(a.sourceToTown[id]!=null)id:a.sourceToTown[id]},
 };
 File('assets/data/compact/index.json').writeAsStringSync(jsonEncode(data));
 final legacy=<String,List<List<Object?>>>{};
 for(final t in a.sourceTowns.values) {legacy.putIfAbsent(t.id.substring(0,2),()=>[]).add([t.id,a.sourceToTown[t.id],t.population]);}
 for(final e in legacy.entries)File('assets/data/compact/legacy/${e.key}.json').writeAsStringSync(jsonEncode(e.value));
 print('prepared towns ${a.towns.length}, sources ${a.sourceTowns.length}');
 },timeout:const Timeout(Duration(minutes:3)));
}

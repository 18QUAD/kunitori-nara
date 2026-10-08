import 'dart:math';

class MunicipalOffice {
  const MunicipalOffice(
    this.cityId,
    this.name,
    this.sourceTownId,
    this.address,
    this.officialUrl,
    this.longitude,
    this.latitude,
  );
  final String cityId, name, sourceTownId, address, officialUrl;
  final double longitude, latitude;
  bool get isCity => cityId.startsWith('292');
  Point<double> get point => Point(longitude, latitude);
}

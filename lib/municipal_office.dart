import 'dart:math';

class MunicipalOffice {
  const MunicipalOffice(
    this.cityId,
    this.name,
    this.sourceTownId,
    this.address,
    this.officialUrl,
    this.longitude,
    this.latitude, {
    bool? isCityOffice,
    this.usesConquestHub = false,
  }) : _isCityOffice = isCityOffice;
  final String cityId, name, sourceTownId, address, officialUrl;
  final double longitude, latitude;
  final bool? _isCityOffice;
  final bool usesConquestHub;
  bool get isCity => _isCityOffice ?? cityId.startsWith('292');
  Point<double> get point => Point(longitude, latitude);
}

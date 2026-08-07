import 'package:latlong2/latlong.dart';

enum SearchCategory {
  hospital,
  police,
  pharmacy,
  fireStation,
  atm,
  restaurant,
  cafe,
  mall,
  petrolPump,
  busStand,
  railwayStation,
  school,
  college,
  university,
  bank,
  hotel,
  park,
  safeArea,
  womenHelp,
  general,
}

class SearchResult {
  final String id;
  final String name;
  final String address;
  final LatLng position;
  final double? distance;
  final SearchCategory category;
  final String icon;
  final int? safetyScore;

  const SearchResult({
    required this.id,
    required this.name,
    required this.address,
    required this.position,
    this.distance,
    this.category = SearchCategory.general,
    this.icon = '📍',
    this.safetyScore,
  });

  SearchResult copyWith({double? distance}) {
    return SearchResult(
      id: id,
      name: name,
      address: address,
      position: position,
      distance: distance ?? this.distance,
      category: category,
      icon: icon,
      safetyScore: safetyScore,
    );
  }

  String get displayDistance {
    if (distance == null) return '';
    if (distance! < 1000) return '${distance!.round()} m';
    final km = distance! / 1000;
    return '${km.toStringAsFixed(1)} km';
  }

  factory SearchResult.fromGeoapify(Map<String, dynamic> json) {
    final properties = json['properties'] as Map<String, dynamic>;
    final lon = (properties['lon'] as num).toDouble();
    final lat = (properties['lat'] as num).toDouble();
    final name = properties['name'] as String? ?? 'Unknown';
    final address = properties['formatted'] as String? ?? '';
    final id = properties['place_id'] as String? ??
        'geo_${lat}_$lon'.replaceAll('.', '_');

    final geoapifyCategories = (properties['categories'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    final category = _detectCategoryFromGeoapify(geoapifyCategories);

    return SearchResult(
      id: id,
      name: name,
      address: address,
      position: LatLng(lat, lon),
      category: category,
      icon: categoryIcon(category),
    );
  }

  static SearchCategory _detectCategoryFromGeoapify(List<String> cats) {
    final joined = cats.join(' ');
    if (joined.contains('police')) return SearchCategory.police;
    if (joined.contains('hospital') || joined.contains('clinic') || joined.contains('doctors')) return SearchCategory.hospital;
    if (joined.contains('pharmacy') || joined.contains('chemist')) return SearchCategory.pharmacy;
    if (joined.contains('fire_station') || joined.contains('fire')) return SearchCategory.fireStation;
    if (joined.contains('atm') || (joined.contains('bank') && !joined.contains('bench'))) return SearchCategory.atm;
    if (joined.contains('restaurant') || joined.contains('fast_food')) return SearchCategory.restaurant;
    if (joined.contains('cafe') || joined.contains('bar')) return SearchCategory.cafe;
    if (joined.contains('mall') || joined.contains('supermarket')) return SearchCategory.mall;
    if (joined.contains('fuel')) return SearchCategory.petrolPump;
    if (joined.contains('bus_station')) return SearchCategory.busStand;
    if (joined.contains('railway')) return SearchCategory.railwayStation;
    if (joined.contains('school')) return SearchCategory.school;
    if (joined.contains('college')) return SearchCategory.college;
    if (joined.contains('university')) return SearchCategory.university;
    if (joined.contains('hotel') || joined.contains('hostel')) return SearchCategory.hotel;
    if (joined.contains('park') || joined.contains('playground')) return SearchCategory.park;
    if (joined.contains('social_facility')) return SearchCategory.womenHelp;
    return SearchCategory.general;
  }

  /// Returns null if the element has no valid coordinates (lat=0/lon=0
  /// or missing entirely). This prevents displaying garbage results at (0,0).
  static SearchResult? fromOverpass({
    required Map<String, dynamic> element,
    required SearchCategory category,
  }) {
    final tags = element['tags'] as Map<String, dynamic>? ?? {};
    final name = tags['name'] as String? ??
        tags['name:en'] as String? ??
        'Unknown';
    final lat = (element['lat'] as num?)?.toDouble();
    final lon = (element['lon'] as num?)?.toDouble();
    final centerLat = (element['center'] as Map<String, dynamic>?)?['lat'] as num?;
    final centerLon = (element['center'] as Map<String, dynamic>?)?['lon'] as num?;
    final finalLat = lat ?? centerLat?.toDouble();
    final finalLon = lon ?? centerLon?.toDouble();

    if (finalLat == null || finalLon == null) return null;
    if (finalLat == 0 && finalLon == 0) return null;

    final street = tags['addr:street'] as String?;
    final city = tags['addr:city'] as String?;
    final parts = <String>[
      ?street,
      ?city,
    ];
    final address = parts.join(', ');

    return SearchResult(
      id: 'osm_${element['id']}',
      name: name,
      address: address,
      position: LatLng(finalLat, finalLon),
      category: category,
      icon: categoryIcon(category),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'address': address,
        'lat': position.latitude,
        'lng': position.longitude,
        'category': category.name,
        'icon': icon,
      };

  factory SearchResult.fromMap(Map<String, dynamic> map) {
    final categoryName = map['category'] as String? ?? 'general';
    final category = SearchCategory.values.firstWhere(
      (c) => c.name == categoryName,
      orElse: () => SearchCategory.general,
    );
    return SearchResult(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? 'Unknown',
      address: map['address'] as String? ?? '',
      position: LatLng(
        (map['lat'] as num).toDouble(),
        (map['lng'] as num).toDouble(),
      ),
      category: category,
      icon: map['icon'] as String? ?? categoryIcon(category),
    );
  }

  static String categoryIcon(SearchCategory category) {
    return switch (category) {
      SearchCategory.hospital => '🏥',
      SearchCategory.police => '🚔',
      SearchCategory.pharmacy => '💊',
      SearchCategory.fireStation => '🚒',
      SearchCategory.atm => '🏧',
      SearchCategory.restaurant => '🍽️',
      SearchCategory.cafe => '☕',
      SearchCategory.mall => '🛍️',
      SearchCategory.petrolPump => '⛽',
      SearchCategory.busStand => '🚌',
      SearchCategory.railwayStation => '🚉',
      SearchCategory.school => '🏫',
      SearchCategory.college => '🎓',
      SearchCategory.university => '🎓',
      SearchCategory.bank => '🏦',
      SearchCategory.hotel => '🏨',
      SearchCategory.park => '🌳',
      SearchCategory.safeArea => '🛡',
      SearchCategory.womenHelp => '🚺',
      SearchCategory.general => '📍',
    };
  }

  static String categoryName(SearchCategory category) {
    return switch (category) {
      SearchCategory.hospital => 'Hospital',
      SearchCategory.police => 'Police Station',
      SearchCategory.pharmacy => 'Pharmacy',
      SearchCategory.fireStation => 'Fire Station',
      SearchCategory.atm => 'ATM',
      SearchCategory.restaurant => 'Restaurant',
      SearchCategory.cafe => 'Cafe',
      SearchCategory.mall => 'Mall',
      SearchCategory.petrolPump => 'Petrol Pump',
      SearchCategory.busStand => 'Bus Stand',
      SearchCategory.railwayStation => 'Railway Station',
      SearchCategory.school => 'School',
      SearchCategory.college => 'College',
      SearchCategory.university => 'University',
      SearchCategory.bank => 'Bank',
      SearchCategory.hotel => 'Hotel',
      SearchCategory.park => 'Park',
      SearchCategory.safeArea => 'Safe Areas',
      SearchCategory.womenHelp => 'Women Help',
      SearchCategory.general => 'Place',
    };
  }

  static bool isGenericName(String name) {
    final lower = name.toLowerCase().trim();
    const generics = {
      'police station',
      'hospital',
      'pharmacy',
      'medical',
      'clinic',
      'doctor',
      'health center',
      'health centre',
      'medical center',
      'medical centre',
      'first aid',
      'nursing home',
    };
    if (generics.contains(lower)) return true;
    // Also match "police station" with extra whitespace or minor variants
    if (RegExp(r'^police\s+station$').hasMatch(lower)) return true;
    return false;
  }
}

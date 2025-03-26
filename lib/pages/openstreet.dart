import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';
import 'package:http/http.dart' as http;

class OpenStreet extends StatefulWidget {
  const OpenStreet({super.key});

  @override
  State<OpenStreet> createState() => _OpenStreetState();
}

class _OpenStreetState extends State<OpenStreet> {
  static const String mapboxAccessToken =
      'pk.eyJ1IjoieWJ1ZW5vMTYiLCJhIjoiY204bjA4azh1MXFqcTJqbXVnamFvdHd1cCJ9.VIYLZ5OeG74e_s21d4sOyw';
  static const String mapboxGeocodingUrl =
      'https://api.mapbox.com/geocoding/v5/mapbox.places';

  @override
  void initState() {
    _initializeLocation();
    super.initState();
  }

  final MapController _mapController = MapController();
  final Location _location = Location();
  final TextEditingController _locationController = TextEditingController();
  bool isLoading = true;
  LatLng? _currentLocation;
  List<LatLng> _waypoints = [];
  List<LatLng> _route = [];
  List<Map<String, dynamic>> _suggestions = [];
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<bool> _checkRequestPermissions() async {
    bool serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _location.requestService();
      if (!serviceEnabled) return false;
    }
    PermissionStatus permissionGranted = await _location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await _location.requestPermission();
      if (permissionGranted != PermissionStatus.granted) return false;
    }
    return true;
  }

  Future<void> _initializeLocation() async {
    if (!await _checkRequestPermissions()) return;

    _location.onLocationChanged.listen((LocationData locationData) {
      if (locationData.latitude != null && locationData.longitude != null) {
        setState(() {
          _currentLocation =
              LatLng(locationData.latitude!, locationData.longitude!);
          isLoading = false;
        });
      }
    });
  }

  Future<void> _fetchSuggestions(String query) async {
    if (query.isEmpty) {
      setState(() {
        _suggestions = [];
      });
      return;
    }

    final url = Uri.parse('$mapboxGeocodingUrl/$query.json'
        '?access_token=$mapboxAccessToken'
        '&language=pt'
        '&country=br'
        '&proximity=${_currentLocation?.longitude ?? 0},${_currentLocation?.latitude ?? 0}'
        '&limit=5'
        '&autocomplete=true'
        '&types=address,place,postcode,neighborhood');

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _suggestions = List<Map<String, dynamic>>.from(data['features']);
        });
      }
    } catch (e) {
      errorMessage('Erro ao buscar sugestões');
    }
  }

  String _getPlaceName(Map<String, dynamic> feature) {
    return feature['place_name'] ?? '';
  }

  Future<void> _addWaypoint(Map<String, dynamic> feature) async {
    final coordinates = feature['geometry']['coordinates'];
    final newWaypoint = LatLng(coordinates[1], coordinates[0]);

    setState(() {
      _waypoints.add(newWaypoint);
      _suggestions = [];
    });

    await _fetchRoute();
  }

  Future<void> _fetchRoute() async {
    if (_currentLocation == null || _waypoints.isEmpty) return;

    final waypointsString =
        _waypoints.map((wp) => '${wp.longitude},${wp.latitude}').join(';');
    final url = Uri.parse("http://router.project-osrm.org/route/v1/driving/"
        '${_currentLocation!.longitude},${_currentLocation!.latitude};'
        '$waypointsString'
        '?overview=full&geometries=polyline');

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final geometry = data['routes'][0]['geometry'];
        _decodedPolyLine(geometry);
      }
    } catch (e) {
      errorMessage('Falha ao calcular rota');
    }
  }

  void _decodedPolyLine(String encodedPolyline) {
    PolylinePoints polylinePoints = PolylinePoints();
    List<PointLatLng> decodedPoints =
        polylinePoints.decodePolyline(encodedPolyline);

    setState(() {
      _route = decodedPoints
          .map((point) => LatLng(point.latitude, point.longitude))
          .toList();
    });
  }

  void _removeWaypoint(int index) {
    setState(() {
      _waypoints.removeAt(index);
    });
    _fetchRoute();
  }

  Future<void> _userCurrentLocation() async {
    if (_currentLocation == null) return;
    _mapController.move(_currentLocation!, 15);
  }

  void errorMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Rota com Paradas'),
        actions: [
          if (_waypoints.isNotEmpty)
            IconButton(
              icon: Icon(Icons.clear_all),
              onPressed: () {
                setState(() {
                  _waypoints.clear();
                  _route.clear();
                });
              },
            ),
        ],
      ),
      body: Stack(
        children: [
          isLoading
              ? Center(child: CircularProgressIndicator())
              : FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _currentLocation ?? LatLng(0, 0),
                    initialZoom: 15,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    ),
                    CurrentLocationLayer(
                      style: LocationMarkerStyle(
                        marker: DefaultLocationMarker(
                          child: Icon(Icons.location_pin, color: Colors.blue),
                        ),
                      ),
                    ),
                    MarkerLayer(
                      markers: _waypoints.asMap().entries.map((entry) {
                        final index = entry.key;
                        final waypoint = entry.value;
                        return Marker(
                          point: waypoint,
                          width: 40,
                          height: 40,
                          child: Column(
                            children: [
                              Text('${index + 1}',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              Icon(Icons.location_pin,
                                  color: Colors.red, size: 30),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                    if (_route.isNotEmpty)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: _route,
                            strokeWidth: 5,
                            color: Colors.blue,
                          )
                        ],
                      ),
                  ],
                ),
          Positioned(
            top: 10,
            left: 10,
            right: 10,
            child: Column(
              children: [
                TextField(
                  controller: _locationController,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    hintText: 'Adicionar parada...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onChanged: (value) {
                    if (_debounce?.isActive ?? false) _debounce?.cancel();
                    _debounce = Timer(Duration(milliseconds: 500), () {
                      _fetchSuggestions(value);
                    });
                  },
                ),
                if (_suggestions.isNotEmpty)
                  Container(
                    height: 200,
                    margin: EdgeInsets.only(top: 5),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 5,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ListView.builder(
                      itemCount: _suggestions.length,
                      itemBuilder: (context, index) {
                        final suggestion = _suggestions[index];
                        return ListTile(
                          title: Text(_getPlaceName(suggestion)),
                          onTap: () {
                            _addWaypoint(suggestion);
                            _locationController.clear();
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          if (_waypoints.isNotEmpty)
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: Container(
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 5,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Paradas:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(height: 5),
                    Container(
                      height: 100,
                      child: ListView.builder(
                        itemCount: _waypoints.length,
                        itemBuilder: (context, index) {
                          return ListTile(
                            leading: CircleAvatar(
                              child: Text('${index + 1}'),
                            ),
                            title: Text('Parada ${index + 1}'),
                            trailing: IconButton(
                              icon: Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _removeWaypoint(index),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _userCurrentLocation,
        child: Icon(Icons.my_location),
      ),
    );
  }
}

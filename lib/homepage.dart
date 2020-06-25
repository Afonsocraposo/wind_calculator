import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:math' as math;
import 'package:geolocator/geolocator.dart';
import 'package:flutter/services.dart';
import 'sharedPref.dart';

class HomePage extends StatefulWidget {
  const HomePage();

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _hasPermissions = false;
  Geolocator geolocator = Geolocator();
  LocationOptions locationOptions =
      LocationOptions(accuracy: LocationAccuracy.best, distanceFilter: 10);
  StreamSubscription<Position> positionStream;
  StreamSubscription<double> headingStream;

  Position lastPosition = Position(latitude: 0, longitude: 0);
  Position position = Position(latitude: 0, longitude: 0);
  double heading = 0;
  double track = 0;
  double groundSpeed = 0;
  int airSpeed = 0;
  double windDirection = 0;
  double windSpeed = 0;
  double magneticVariation = 3;

  TextEditingController _airSpeedController = TextEditingController(text: "0");
  TextEditingController _headingController = TextEditingController(text: "0");
  TextEditingController _varController = TextEditingController(text: "0");

  bool _overrideHeading = false;
  bool _editingHeading = false;

  @override
  void initState() {
    super.initState();
    _fetchPermissionStatus();
    _startGeolocator();
    _startCompass();
    SharedPref.read("magneticVariation").then((value) {
      if (value != null && mounted) {
        setState(() {
          _varController.text = value.toString();
          magneticVariation = value;
        });
      }
    });
  }

  _startCompass() {
    headingStream = FlutterCompass.events.listen((double data) {
      if (data != null && !_overrideHeading) {
        setState(() {
          heading = data * math.pi / 180;
          if (!_editingHeading)
            _headingController.text = data.round().toString();
        });
      }
    });
  }

  _startGeolocator() async {
    lastPosition = await Geolocator()
        .getLastKnownPosition(desiredAccuracy: LocationAccuracy.best);
    positionStream = geolocator
        .getPositionStream(locationOptions)
        .listen((Position position) {
      if (position != null) {
        setState(() {
          lastPosition = this.position;
          this.position = position;
          track = (position.heading + magneticVariation) * math.pi / 180;
          groundSpeed = position.speed * 3600 / 1852;
        });
      }
    });
  }

  double _getWindDirection() {
    windDirection = track +
        math.atan2(
            math.sin(heading - track),
            math.sqrt(1 - math.pow(math.sin(heading - track), 2)) -
                (groundSpeed / airSpeed));
    return windDirection;
  }

  double _getWindSpeed() {
    return airSpeed *
        (math.sin(heading - track) / math.sin(windDirection - track));
  }

  double _rad2deg(double rad) => (rad * 180 / math.pi + 360) % 360;
  double _deg2rad(int deg) => (deg % 360) * math.pi / 180;

  String _deg2dms(double dd, {bool lat = true}) {
    int d = dd.toInt();
    int m = ((dd - d) * 60).toInt();
    int s = ((dd - d - m / 60) * 3600).toInt();
    String c;
    if (lat) {
      if (dd >= 0) {
        c = "N";
      } else {
        c = "S";
      }
    } else {
      if (dd >= 0) {
        c = "E";
      } else {
        c = "W";
      }
    }
    return "${d.abs()}º ${m.abs()}' ${s.abs()}\" $c";
  }

  @override
  void dispose() {
    positionStream?.cancel();
    headingStream?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    windDirection = _getWindDirection();
    windSpeed = _getWindSpeed();
    if (windDirection.isNaN) windDirection = 0;
    if (windSpeed.isNaN) windSpeed = 0;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        actions: <Widget>[
          IconButton(
              onPressed: _setVar,
              icon: Icon(Icons.settings),
              color: Colors.white)
        ],
      ),
      body: SafeArea(
        child: Builder(builder: (context) {
          if (_hasPermissions) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _buildStats(),
                Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: _buildCompass(),
                  ),
                ),
                _buildCoords()
              ],
            );
          } else {
            return _buildPermissionSheet();
          }
        }),
      ),
    );
  }

  _setVar() {
    showDialog(
        context: context,
        builder: (BuildContext parentContext) {
          bool west = magneticVariation < 0;
          return StatefulBuilder(builder: (context, setCurrentState) {
            return CupertinoAlertDialog(
              title: const Text("Magnetic Vatiation"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      FlatButton(
                        color: west ? Colors.blueAccent : Colors.white,
                        onPressed: () => setCurrentState(() => west = true),
                        shape: CircleBorder(),
                        child: Text(
                          "W",
                          style: TextStyle(
                              color: west ? Colors.white : Colors.black),
                        ),
                      ),
                      FlatButton(
                        color: !west ? Colors.blueAccent : Colors.white,
                        onPressed: () => setCurrentState(() => west = false),
                        shape: CircleBorder(),
                        child: Text(
                          "E",
                          style: TextStyle(
                              color: !west ? Colors.white : Colors.black),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(
                    width: 54,
                    child: CupertinoTextField(
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(5),
                      ],
                      textAlign: TextAlign.center,
                      onTap: () {
                        _varController.clear();
                      },
                      maxLengthEnforced: true,
                      keyboardType: TextInputType.phone,
                      controller: _varController,
                    ),
                  ),
                ],
              ),
              actions: <Widget>[
                CupertinoDialogAction(
                  isDestructiveAction: true,
                  child: Text("Cancel"),
                  onPressed: () {
                    Navigator.of(context).pop("Discard");
                  },
                ),
                CupertinoDialogAction(
                  isDefaultAction: true,
                  child: Text("Save"),
                  onPressed: () {
                    double value = (double.tryParse(_varController.text) ?? 0) *
                        (west ? 1 : -1);
                    SharedPref.save("magneticVariation", value);
                    setState(() => this.magneticVariation = value);
                    Navigator.of(context).pop("Discard");
                  },
                ),
              ],
            );
          });
        });
  }

  Widget _buildCoords() {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 32),
      child: Row(
        children: <Widget>[
          Text("LAT",
              style:
                  TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              "${_deg2dms(15 + position?.latitude ?? 0)}",
              textAlign: TextAlign.end,
              style:
                  TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
            ),
          ),
          Expanded(child: Container()),
          Text("LON",
              style:
                  TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              "${_deg2dms(-32 + position?.longitude - 32 ?? 0, lat: false)}",
              textAlign: TextAlign.end,
              style:
                  TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
            ),
          ),
        ],
      ),
    );
  }

  _buildWind() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              _rad2deg(windDirection).round().toString().padLeft(3, '0') + "º",
              style: TextStyle(
                  color: Colors.green,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
            ),
            Text(
              "/",
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
            ),
            Text(
              "${windSpeed.round()}",
              style: TextStyle(
                  color: Colors.green,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
            ),
          ],
        ),
        Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Transform.rotate(
            angle: windDirection - heading,
            child: Icon(Icons.arrow_upward, color: Colors.white, size: 32),
          ),
        ),
      ],
    );
  }

  Widget _buildStats() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                "GS",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(
                width: 54,
                child: Text(
                  "${groundSpeed.round()}",
                  textAlign: TextAlign.end,
                  style: TextStyle(
                      color: Colors.green,
                      fontSize: 24,
                      fontWeight: FontWeight.bold),
                ),
              ),
              SizedBox(width: 32),
              Text(
                "TAS ",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(
                width: 54,
                child: TextField(
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(3),
                  ],
                  onTap: () {
                    _airSpeedController.clear();
                  },
                  maxLengthEnforced: true,
                  textAlign: TextAlign.end,
                  keyboardType: TextInputType.phone,
                  controller: _airSpeedController,
                  onSubmitted: (value) {
                    if (value.isNotEmpty) {
                      setState(() {
                        airSpeed = int.tryParse(value) ?? 0;
                      });
                    } else {
                      _airSpeedController.text = "$airSpeed";
                    }
                  },
                  style: TextStyle(
                      color: Colors.green,
                      fontSize: 24,
                      fontWeight: FontWeight.bold),
                  decoration: InputDecoration.collapsed(hintText: "Test"),
                ),
              ),
            ],
          ),
          _buildWind(),
        ],
      ),
    );
  }

  Widget _buildCompass() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            Text(
              "HDG",
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(
              width: 54,
              child: TextField(
                inputFormatters: [
                  LengthLimitingTextInputFormatter(3),
                ],
                onTap: () {
                  setState(() {
                    _editingHeading = true;
                  });
                  _headingController.clear();
                },
                maxLengthEnforced: true,
                textAlign: TextAlign.end,
                keyboardType: TextInputType.phone,
                controller: _headingController,
                onSubmitted: (value) {
                  setState(() {
                    if (value.isNotEmpty) {
                      _headingController.text = value.padLeft(3, "0");
                      _overrideHeading = true;
                      heading = _deg2rad(int.tryParse(value)) ?? 0;
                    } else {
                      _overrideHeading = false;
                      _headingController.text =
                          _rad2deg(heading).round().toString();
                    }
                    _editingHeading = false;
                  });
                },
                style: TextStyle(
                    color: _overrideHeading ? Colors.yellow : Colors.green,
                    fontSize: 24,
                    fontWeight: FontWeight.bold),
                decoration: InputDecoration.collapsed(hintText: "Test"),
              ),
            ),
            SizedBox(width: 16)
          ],
        ),
        SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: 32,
              child: Text(
                "TRK",
                style: TextStyle(color: Colors.green),
              ),
            ),
            Container(
              padding: EdgeInsets.only(left: 4, bottom: 4, right: 4),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: Colors.white,
                    width: 3.0,
                  ),
                  bottom: BorderSide(
                    color: Colors.white,
                    width: 3.0,
                  ),
                  right: BorderSide(
                    color: Colors.white,
                    width: 3.0,
                  ),
                ),
              ),
              child: Text(_rad2deg(track).round().toString().padLeft(3, "0"),
                  style: TextStyle(color: Colors.white, fontSize: 20)),
            ),
            SizedBox(
              width: 32,
            ),
          ],
        ),
        AspectRatio(
          aspectRatio: 1.5,
          child: Stack(
            fit: StackFit.passthrough,
            alignment: Alignment.topCenter,
            overflow: Overflow.visible,
            children: <Widget>[
              ClipRect(
                child: Transform.scale(
                  scale: 2.5,
                  alignment: Alignment.topCenter,
                  child: Transform.rotate(
                    angle: ((heading ?? 0) * -1),
                    child: Stack(fit: StackFit.passthrough, children: <Widget>[
                      Padding(
                        padding: EdgeInsets.all(8),
                        child: Image.asset("assets/bearing.png",
                            fit: BoxFit.fitHeight),
                      ),
                      Transform.rotate(
                        angle: track,
                        child: Container(
                            alignment: Alignment.topCenter,
                            //margin: EdgeInsets.only(top: 20),
                            child: Icon(Icons.change_history,
                                color: Colors.green, size: 16)),
                      ),
                    ]),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                child: Container(color: Colors.yellow, width: 4, height: 16),
              ),
              Positioned(
                bottom: 16,
                child: Icon(
                  Icons.airplanemode_active,
                  color: Colors.white,
                  size: 64,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPermissionSheet() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text('Location Permission Required'),
          RaisedButton(
            child: Text('Request Permissions'),
            onPressed: () {
              Permission.locationWhenInUse.request().then((ignored) {
                _fetchPermissionStatus();
              });
            },
          ),
        ],
      ),
    );
  }

  void _fetchPermissionStatus() {
    Permission.locationWhenInUse.isGranted.then((status) {
      if (mounted) {
        setState(() => _hasPermissions = status);
      }
    });
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_blue/flutter_blue.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Red Dragon',
      theme: ThemeData(
        primarySwatch: Colors.teal,
      ),
      home: MyHomePage(title: 'Red Dragon'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key, this.title}) : super(key: key);

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<MyHomePage> {
  FlutterBlue flutterBlue = FlutterBlue.instance;
  BluetoothDevice blueFruit;

  bool connected = false;
  bool doorUnlocked = false;
  
  /// State
  BluetoothState state = BluetoothState.unknown;
  List<BluetoothService> services;
  
  /// Device
  BluetoothDevice device;
  bool get isConnected => (device != null);
  StreamSubscription deviceConnection;
  StreamSubscription deviceStateSubscription;

  //nRF52 hardcoded values
  Guid BLEService_UUID = Guid("6e400001-b5a3-f393-e0a9-e50e24dcca9e");
  Guid BLE_Characteristic_uuid_Tx = Guid("6e400002-b5a3-f393-e0a9-e50e24dcca9e");
  Guid BLE_Characteristic_uuid_Rx = Guid("6e400003-b5a3-f393-e0a9-e50e24dcca9e");
  int MaxCharacters = 20;
  
  Map<Guid, StreamSubscription> valueChangedSubscriptions = {};
  BluetoothDeviceState deviceState = BluetoothDeviceState.disconnected;


  String connectionStatus = "";
  String lockStatusImgPath = "images/lock.png";
  String lockBtnText = "Unlock";

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitDown,
      DeviceOrientation.portraitUp,
    ]);

    // Immediately get the state of FlutterBlue
    flutterBlue.state.then((s) {
      setState(() {
        state = s;
      });
    });

    _setConnectionStatus();
  }

  _connect(BluetoothDevice d) async {
    device = d;
    // Connect to device
    deviceConnection = flutterBlue
        .connect(device, timeout: const Duration(seconds: 4))
        .listen(
          null,
          onDone: _disconnect,
        );

    // Update the connection state immediately
    device.state.then((s) {
      setState(() {
        deviceState = s;
      });
    });

    // Subscribe to connection changes
    deviceStateSubscription = device.onStateChanged().listen((s) {
      setState(() {
        deviceState = s;
      });
      if (s == BluetoothDeviceState.connected) {
        setState(() {
            _setConnectionStatus();
        });

        device.discoverServices().then((s) {
          setState(() {
            services = s;
          });
        });
      }
    });
  }

  void _toggleconnect() async{
    flutterBlue.scan().listen((scanResult) {
      if(scanResult.device.name == "Red Dragon" || scanResult.device.name == "Bluefruit52"){
        BluetoothDevice device = scanResult.device;
        _connect(device);    
      }
    });
  }

  void _togglelock(){
    doorUnlocked = !doorUnlocked;

    if(deviceState == BluetoothDeviceState.connected){
      if(doorUnlocked) {
        _writeCharacteristic(BluetoothCharacteristic (uuid: BLE_Characteristic_uuid_Tx,
          serviceUuid: BLEService_UUID), "unlock\n"); 
      }
      else{
        _writeCharacteristic(BluetoothCharacteristic (uuid: BLE_Characteristic_uuid_Tx, 
        serviceUuid: BLEService_UUID), "lock\n"); 
      }
    }
  }

  void _disconnect(){
    if(deviceConnection != null){
      deviceConnection.cancel().then((_){
        setState(() {
          deviceState = BluetoothDeviceState.disconnected;
          _setConnectionStatus();          
        });
      });      
    }
  }

  void _setConnectionStatus(){
    if(deviceState==BluetoothDeviceState.connected){
      connectionStatus = "Connected to Red Dragon".toUpperCase();  
    }
    else{
      connectionStatus = "Red Dragon not connected".toUpperCase();  
    }
  }

  _readCharacteristic(BluetoothCharacteristic c) async {
    await device.readCharacteristic(c);
    setState(() {});
  }

  _writeCharacteristic(BluetoothCharacteristic c, String msg) async {
    await device.writeCharacteristic(c, utf8.encode(msg),
        type: CharacteristicWriteType.withResponse);
    setState(() {
      doorUnlocked ? lockStatusImgPath = "images/unlock.png": lockStatusImgPath = "images/lock.png";
      doorUnlocked ? lockBtnText = "Lock": lockBtnText = "Unlock";
    });
  }

  _readDescriptor(BluetoothDescriptor d) async {
    await device.readDescriptor(d);
    setState(() {});
  }

  _writeDescriptor(BluetoothDescriptor d) async {
    await device.writeDescriptor(d, [0x12, 0x34]);
    setState(() {});
  }

  _setNotification(BluetoothCharacteristic c) async {
    if (c.isNotifying) {
      await device.setNotifyValue(c, false);
      // Cancel subscription
      valueChangedSubscriptions[c.uuid]?.cancel();
      valueChangedSubscriptions.remove(c.uuid);
    } else {
      await device.setNotifyValue(c, true);
      // ignore: cancel_subscriptions
      final sub = device.onValueChanged(c).listen((d) {
        setState(() {
          print('onValueChanged $d');
        });
      });
      // Add to map
      valueChangedSubscriptions[c.uuid] = sub;
    }
    setState(() {});
  }

  _refreshDeviceState(BluetoothDevice d) async {
    var state = await d.state;
    setState(() {
      deviceState = state;
      print('State refreshed: $deviceState');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[  
            Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.center,
              
              children: <Widget>[
                new Container(
                  width: 80.0,
                  height: 80.0,
                  margin: const EdgeInsets.all(10.0),
                  alignment: Alignment.center,
                  child: new Image.asset(
                    lockStatusImgPath,
                    fit: BoxFit.cover,
                  ),
                ),
                
                new Container(
                  width: 180.0,
                  height: 100.0,
                  padding: EdgeInsets.all(5),
                  child: FittedBox(
                    fit: BoxFit.contain,
                    alignment: Alignment.center,
                    child: OutlineButton(                    
                      child: Text(lockBtnText, style:TextStyle(fontSize: 12)),
                      borderSide: deviceState==BluetoothDeviceState.connected ? BorderSide(color: Colors.teal) : BorderSide(color: Color.fromARGB(255, 177, 4, 25)) ,
                      shape: new RoundedRectangleBorder(borderRadius: new BorderRadius.circular(20.0)),
                      onPressed: _togglelock,
                    ),
                  )
                ),
              ],
            ),
            
            new Container(
              width: 200.0,
              height: 80.0,
              padding: const EdgeInsets.all(15.0),
              child: FittedBox(
                fit: BoxFit.contain,
                alignment: Alignment.center,
                child: OutlineButton(
                  child: const Text('Disconnect'),
                  borderSide: BorderSide(color: Colors.blueGrey),
                  onPressed: _disconnect,
                ),
              )
            ),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Container(
                  width: 150,
                  height: 60,
                  padding: EdgeInsets.only(top: 10.5),
                  child: Text(
                    '$connectionStatus',
                    style: TextStyle(
                      fontSize: 18,
                      color: deviceState==BluetoothDeviceState.connected ? Color.fromARGB(200, 57, 204, 204) : Color.fromARGB(255, 177, 4, 25),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                
                Container(
                  width: 60,
                  height: 60,
                  child: FloatingActionButton(
                    onPressed: _toggleconnect,
                    child: Icon(Icons.bluetooth),
                    backgroundColor: deviceState==BluetoothDeviceState.connected ? Color.fromARGB(200, 57, 204, 204) : Color.fromARGB(255, 177, 4, 25),
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                  )
                ),
              ], 
            )
          ],
                                        
        ),
      ),
    );
  }
}

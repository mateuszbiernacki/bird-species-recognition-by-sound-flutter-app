import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:collection';

void main() {
  runApp(const MyApp());
}

const uriFittingModel = 'https://python-fitting-model-dplabwnjcq-lm.a.run.app';

enum RecordStatus {
  beforeRecording('Record'),
  duringRecording('Recording'),
  afterRecording('Fit record'),
  fittingModel('Sending record'),
  afterFitting('New record');

  const RecordStatus(this.buttonLabel);
  final String buttonLabel;
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a blue toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.redAccent),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Bird\'s specie recognition '),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  var status = RecordStatus.beforeRecording;
  var resultsFromNeuralNet = <String, Float>{};
  FlutterSoundRecorder? soundRecorder = FlutterSoundRecorder();
  var soundPlayer = FlutterSoundPlayer();
  var buffer = BytesBuilder();
  StreamSubscription? subscription;
  SplayTreeMap<String, dynamic>? results;
  String stringResults = 'No results yet';

  void _handleRecordButtonClicking() {
    setState(() {
      switch (status) {
        case RecordStatus.beforeRecording:
          startRecording(10);
          status = RecordStatus.duringRecording;
          break;
        case RecordStatus.duringRecording:
          // do nothing
          break;
        case RecordStatus.afterRecording:
          _fitModel();
          status = RecordStatus.fittingModel;
          break;
        case RecordStatus.fittingModel:
          // do nothing
          break;
        case RecordStatus.afterFitting:
          _restartRecordingProces();
          break;
      }
    });
  }

  void _fitModel() async {
    var recordBytes = buffer.toBytes();
    buffer = BytesBuilder();
    Uint8List wavBuffer = await flutterSoundHelper.pcmToWaveBuffer(
        inputBuffer: recordBytes, numChannels: 1, sampleRate: 22050);
    http.post(Uri.parse(uriFittingModel), body: wavBuffer).then((response) {
      if (response.statusCode == 200) {
        // Sukces - otrzymano odpowiedź
        print('Odpowiedź: ${response.body}');

        setState(() {
          status = RecordStatus.afterFitting;
          var unsortedResults = json.decode(response.body);
          results = SplayTreeMap.from(
              unsortedResults,
              (key1, key2) =>
                  unsortedResults[key2].compareTo(unsortedResults[key1]));
          final buffer = StringBuffer('');
          for (String spec in results!.keys) {
            buffer.write(spec.replaceFirst(RegExp('_'), ' '));
            buffer.write(' - ');
            var value = results![spec];
            if (value is double) {
              var valueString = (value * 100).toStringAsFixed(2);
              buffer.write('$valueString%\n');
            }
          }
          stringResults = buffer.toString();
        });
      } else {
        // Błąd - otrzymano kod inny niż 200
        print('Błąd: ${response.statusCode}');
        _restartRecordingProces();
      }
    }).catchError((error) {
      // Błąd połączenia lub inny błąd
      print('Błąd: $error');
      _restartRecordingProces();
    });
  }

  void _restartRecordingProces() {
    setState(() {
      status = RecordStatus.beforeRecording;
      buffer = BytesBuilder();
      soundRecorder!.stopRecorder();
      soundRecorder!.closeRecorder();
      soundPlayer.stopPlayer();
      soundPlayer.closePlayer();
    });
  }

  void _handleTimeout() async {
    await soundRecorder!.stopRecorder();
    await soundRecorder!.closeRecorder();
    if (subscription != null) {
      await subscription!.cancel();
      subscription = null;
    }
    setState(() {
      status = RecordStatus.afterRecording;
    });
  }

  Future<void> startRecording(int seconds) async {
    var timeout = Duration(seconds: seconds);
    if (buffer.isNotEmpty) {
      buffer = BytesBuilder();
    }
    PermissionStatus status = await Permission.microphone.request();
    await soundRecorder!.openRecorder();
    var recordingDataController = StreamController<Food>();
    subscription = recordingDataController.stream.listen((food) {
      if (food is FoodData) {
        buffer.add(food.data!);
      }
    });
    if (status != PermissionStatus.granted) {
      throw RecordingPermissionException("Microphone permission not granted");
    } else {
      await soundRecorder!.startRecorder(
        toStream: recordingDataController.sink,
        codec: Codec.pcm16,
        numChannels: 1,
        sampleRate: 22050,
      );
    }
    Timer(timeout, _handleTimeout);
  }

  void stopRecording() async {
    await soundRecorder!.stopRecorder();
    await soundRecorder!.closeRecorder();
    if (subscription != null) {
      await subscription!.cancel();
      subscription = null;
    }
  }

  void playLastRecord() async {
    if (!soundPlayer.isOpen()) {
      soundPlayer.openPlayer();
    }

    soundPlayer.startPlayer(
        fromDataBuffer: buffer.toBytes(),
        codec: Codec.pcm16,
        sampleRate: 22050,
        numChannels: 1,
        whenFinished: () {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.headlineMedium!.copyWith(
      fontWeight: FontWeight.bold,
      color: theme.colorScheme.onPrimary,
    );
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // TRY THIS: Try changing the color here to a specific color (to
        // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      shape: const CircleBorder(),
                      elevation: 10,
                      fixedSize: const ui.Size(200, 200)),
                  onPressed: () {
                    _handleRecordButtonClicking();
                  },
                  child: Text(
                    status.buttonLabel,
                    style: style,
                    textAlign: TextAlign.center,
                  )),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.onSecondary),
                    onPressed: () {
                      playLastRecord();
                    },
                    child: const Text(
                      'Play',
                      style: TextStyle(color: Colors.blueGrey),
                    )),
                const SizedBox(
                  width: 20,
                ),
                ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.onSecondary),
                    onPressed: () {
                      _restartRecordingProces();
                    },
                    child: const Text(
                      'Reset',
                      style: TextStyle(color: Colors.blueGrey),
                    )),
              ],
            ),
            const SizedBox(
              height: 20,
            ),
            Text(stringResults),
          ],
        ),
      ),
    );
  }
}

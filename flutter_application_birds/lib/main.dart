import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:collection';
import 'package:file_picker/file_picker.dart';
import 'package:wav/wav.dart';
import 'package:logger/logger.dart';

void main() {
  runApp(const BirdsApp());
}

const uriFittingModel = 'https://python-fitting-model-dplabwnjcq-lm.a.run.app';
// const uriFittingModel = "http://10.0.2.2:8080/";

enum RecordStatus {
  beforeRecording('Record'),
  duringRecording('Recording'),
  pickingFile('');

  const RecordStatus(this.buttonLabel);
  final String buttonLabel;
}

class BirdsApp extends StatelessWidget {
  const BirdsApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.redAccent),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Bird species recognition '),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  var status = RecordStatus.beforeRecording;
  var recordingInTheRow = 0;
  var resultsFromNeuralNet = <String, double>{};
  FlutterSoundRecorder? soundRecorder =
      FlutterSoundRecorder(logLevel: Level.nothing);
  var soundPlayer = FlutterSoundPlayer(logLevel: Level.nothing);
  var buffer = BytesBuilder();
  StreamSubscription? subscription;
  SplayTreeMap<String, dynamic>? results;
  var _buttonIcon = Icon(Icons.circle);
  List<List<String>> tableWithResults = [
    ['\n', ''],
    ['\n', ''],
    ['\n', ''],
    ['\n', ''],
    ['\n', ''],
  ];

  int sr = 22050;
  int chanells = 1;

  void _handleRecordButtonClicking() {
    setState(() {
      switch (status) {
        case RecordStatus.beforeRecording:
          _buttonIcon = Icon(Icons.stop_rounded);
          tableWithResults = [
            ['\n', ''],
            ['\n', ''],
            ['\n', ''],
            ['\n', ''],
            ['\n', ''],
          ];
          startRecording();
          status = RecordStatus.duringRecording;
          break;
        case RecordStatus.duringRecording:
          _restartRecordingProces();

          setState(() {
            _buttonIcon = Icon(Icons.circle);
          });
          break;
        case RecordStatus.pickingFile:
          // do nothing
          break;
      }
    });
  }

  void _fitModel() async {
    var recordBytes = buffer.toBytes();
    buffer = BytesBuilder();
    Uint8List wavBuffer = await flutterSoundHelper.pcmToWaveBuffer(
        inputBuffer: recordBytes, numChannels: 1, sampleRate: sr);
    http.post(Uri.parse(uriFittingModel), body: wavBuffer).then((response) {
      if ((response.statusCode == 200) &
          (status != RecordStatus.beforeRecording)) {
        // Sukces - otrzymano odpowiedź

        print('Odpowiedź: ${response.body}');

        setState(() {
          recordingInTheRow += 1;
          var unsortedResults = json.decode(response.body);

          resultsFromNeuralNet.forEach((key, value) {
            resultsFromNeuralNet[key] = value * (recordingInTheRow - 1);
            if (unsortedResults[key] == null) {
              unsortedResults[key] = 0.0;
            }
          });

          unsortedResults.forEach((key, value) {
            if (resultsFromNeuralNet[key] == null) {
              resultsFromNeuralNet[key] = value / recordingInTheRow;
            } else {
              resultsFromNeuralNet[key] =
                  (resultsFromNeuralNet[key]! + value) / recordingInTheRow;
            }
          });

          results = SplayTreeMap.from(
              resultsFromNeuralNet,
              (key1, key2) => resultsFromNeuralNet[key2]!
                  .compareTo(resultsFromNeuralNet[key1]!));
          int counter = 0;
          for (String spec in results!.keys) {
            counter += 1;
            if (counter <= 5) {
              tableWithResults[counter - 1][0] =
                  spec.replaceFirst(RegExp('_'), ' ');
              var value = results![spec];
              if (value is double) {
                var valueString = (value * 100).toStringAsFixed(2);
                tableWithResults[counter - 1][1] = '$valueString%';
              }
            }
          }
          if (status == RecordStatus.pickingFile) {
            _restartRecordingProces();
          }
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
      recordingInTheRow = 0;
      resultsFromNeuralNet.clear();
      sr = 22050;
      chanells = 1;
      _buttonIcon = Icon(Icons.circle);
    });
  }

  Future<void> startRecording() async {
    int seconds = 10;
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
        numChannels: chanells,
        sampleRate: sr,
      );
    }
    Timer(timeout, _restartRecording);
  }

  void _restartRecording() async {
    await soundRecorder!.stopRecorder();
    await soundRecorder!.closeRecorder();
    if (subscription != null) {
      await subscription!.cancel();
      subscription = null;
    }

    if (status == RecordStatus.duringRecording) {
      _fitModel();
      startRecording();
    }
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
        sampleRate: sr,
        numChannels: 1,
        whenFinished: () {});
  }

  void pickFile() async {
    status = RecordStatus.pickingFile;
    _buttonIcon = Icon(Icons.do_disturb);
    final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['wav'],
        allowMultiple: false,
        withData: true);
    if (result == null) return;
    final file = result.files.first;
    if (file.bytes == null) return;
    var pickedBytes = file.bytes!;
    var wav = Wav.read(pickedBytes);
    sr = wav.samplesPerSecond;

    setState(() {
      chanells = wav.channels.length;
      var monoWaw = Wav([wav.toMono()], sr);
      pickedBytes =
          flutterSoundHelper.waveToPCMBuffer(inputBuffer: monoWaw.write());
      buffer = BytesBuilder();
      buffer.add(pickedBytes.toList());
      _fitModel();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton.outlined(
                        onPressed: _handleRecordButtonClicking,
                        iconSize: 140,
                        color: Colors.red,
                        icon: _buttonIcon),
                    SizedBox(
                      width: 10,
                    ),
                    IconButton.filledTonal(
                      onPressed: pickFile,
                      icon: Icon(Icons.add),
                      iconSize: 30,
                    ),
                  ],
                )),
            const SizedBox(
              height: 20,
            ),
            // Text(stringResults),
            Table(
              textDirection: TextDirection.ltr,
              columnWidths: const <int, TableColumnWidth>{
                0: IntrinsicColumnWidth(),
                1: IntrinsicColumnWidth(),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: <TableRow>[
                TableRow(children: <Widget>[
                  Container(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(tableWithResults[0][0]),
                    ),
                  ),
                  Container(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(tableWithResults[0][1],
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 20)),
                    ),
                  ),
                ]),
                TableRow(children: <Widget>[
                  Container(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(tableWithResults[1][0]),
                    ),
                  ),
                  Container(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(tableWithResults[1][1],
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 20)),
                    ),
                  ),
                ]),
                TableRow(children: <Widget>[
                  Container(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(tableWithResults[2][0]),
                    ),
                  ),
                  Container(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(tableWithResults[2][1],
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 20)),
                    ),
                  ),
                ]),
                TableRow(children: <Widget>[
                  Container(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(tableWithResults[3][0]),
                    ),
                  ),
                  Container(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(tableWithResults[3][1],
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 20)),
                    ),
                  ),
                ]),
                TableRow(children: <Widget>[
                  Container(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(tableWithResults[4][0]),
                    ),
                  ),
                  Container(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(tableWithResults[4][1],
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 20)),
                    ),
                  ),
                ])
              ],
            )
          ],
        ),
      ),
    );
  }
}

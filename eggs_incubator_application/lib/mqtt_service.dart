import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class IncubatorData {
  final double suhu;
  final double humidity;
  final bool lampu;
  final bool kipas;
  final int hari;
  final int posServo;
  final int sisaRotasiMenit;
  final DateTime waktu;

  IncubatorData({
    required this.suhu,
    required this.humidity,
    required this.lampu,
    required this.kipas,
    required this.hari,
    required this.posServo,
    required this.sisaRotasiMenit,
    required this.waktu,
  });

  factory IncubatorData.fromJson(Map<String, dynamic> j) {
    return IncubatorData(
      suhu: (j['suhu'] as num).toDouble(),
      humidity: (j['humidity'] as num).toDouble(),
      lampu: j['lampu'] as bool,
      kipas: j['kipas'] as bool,
      hari: j['hari'] as int,
      posServo: j['posServo'] as int,
      sisaRotasiMenit: j['sisaRotasiMenit'] as int,
      waktu: DateTime.now(),
    );
  }
}

class ChartPoint {
  final double x;
  final double y;

  ChartPoint(this.x, this.y);
}

class MqttService extends ChangeNotifier {
  // ==========================================================
  // MQTT CONFIG
  // ==========================================================
  static const broker = 'broker.emqx.io';
  static const port = 1883;

  static const topicSub = 'Inkubator_Telur_ESP32_50';

  static const topicPub = 'Inkubator_Telur_ESP32_50/command';

  // ==========================================================
  late MqttServerClient _client;

  IncubatorData? data;

  List<ChartPoint> suhuHistory = [];
  List<ChartPoint> humHistory = [];

  bool connected = false;

  String status = 'Menghubungkan MQTT...';

  double _tick = 0;

  // ==========================================================
  // CONNECT MQTT
  // ==========================================================
  Future<void> connect() async {
    final clientId = 'flutter_${DateTime.now().millisecondsSinceEpoch}';

    _client = MqttServerClient.withPort(broker, clientId, port);

    // ==============================
    // BASIC CONFIG
    // ==============================
    _client.keepAlivePeriod = 20;

    _client.secure = false;

    _client.setProtocolV311();

    _client.autoReconnect = true;

    _client.logging(on: true);

    // ==============================
    // CALLBACK
    // ==============================
    _client.onConnected = _onConnected;

    _client.onDisconnected = _onDisconnected;

    _client.onSubscribed = (topic) {
      debugPrint('SUBSCRIBED: $topic');
    };

    // ==============================
    // CONNECTION MESSAGE
    // ==============================
    _client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean();

    try {
      status = 'Menghubungkan ke MQTT...';

      notifyListeners();

      debugPrint('CONNECTING MQTT...');

      await _client.connect();

      // ==========================
      // CEK STATUS
      // ==========================
      if (_client.connectionStatus!.state != MqttConnectionState.connected) {
        status = 'MQTT Gagal: ${_client.connectionStatus!.state}';

        connected = false;

        notifyListeners();

        debugPrint(status);

        _client.disconnect();

        return;
      }

      debugPrint('MQTT CONNECTED');

      // ==========================
      // SUBSCRIBE
      // ==========================
      _client.subscribe(topicSub, MqttQos.atLeastOnce);

      // ==========================
      // LISTENER
      // ==========================
      _client.updates!.listen((List<MqttReceivedMessage<MqttMessage>> msgs) {
        final recMess = msgs[0].payload as MqttPublishMessage;

        final payload = MqttPublishPayload.bytesToStringAsString(
          recMess.payload.message,
        );

        debugPrint('MQTT DATA: $payload');

        _onMessage(payload);
      });
    } catch (e) {
      connected = false;

      status = 'ERROR MQTT: $e';

      notifyListeners();

      debugPrint(status);

      _client.disconnect();
    }
  }

  // ==========================================================
  // CONNECTED
  // ==========================================================
  void _onConnected() {
    connected = true;

    status = 'MQTT Terhubung';

    notifyListeners();

    debugPrint('MQTT CONNECTED CALLBACK');
  }

  // ==========================================================
  // DISCONNECTED
  // ==========================================================
  void _onDisconnected() {
    connected = false;

    status = 'MQTT Terputus';

    notifyListeners();

    debugPrint('MQTT DISCONNECTED');
  }

  // ==========================================================
  // RECEIVE DATA
  // ==========================================================
  void _onMessage(String payload) {
    try {
      final json = jsonDecode(payload) as Map<String, dynamic>;

      data = IncubatorData.fromJson(json);

      suhuHistory.add(ChartPoint(_tick, data!.suhu));

      humHistory.add(ChartPoint(_tick, data!.humidity));

      if (suhuHistory.length > 30) {
        suhuHistory.removeAt(0);
      }

      if (humHistory.length > 30) {
        humHistory.removeAt(0);
      }

      _tick++;

      notifyListeners();
    } catch (e) {
      debugPrint('PARSE ERROR: $e');
    }
  }

  // ==========================================================
  // SEND COMMAND
  // ==========================================================
  void sendCommand(Map<String, dynamic> cmd) {
    if (!connected) return;

    final builder = MqttClientPayloadBuilder();

    builder.addString(jsonEncode(cmd));

    _client.publishMessage(topicPub, MqttQos.atLeastOnce, builder.payload!);

    debugPrint('SEND: ${jsonEncode(cmd)}');
  }

  // ==========================================================
  // RESET HARI
  // ==========================================================
  void resetHari() {
    sendCommand({'reset_hari': true});
  }

  // ==========================================================
  // SERVO MANUAL
  // ==========================================================
  void servoManual(int deg) {
    sendCommand({'servo_manual': deg});
  }
}

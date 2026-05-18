#include <Wire.h>
#include <DHT.h>
#include <LiquidCrystal_I2C.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <RTClib.h>
#include <ESP32Servo.h>
#include <WiFi.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>

// ============================================================
// KONFIGURASI — WAJIB DIISI SEBELUM UPLOAD
// ============================================================
const char* WIFI_SSID   = "Arrasyadah";
const char* WIFI_PASS   = "135641619";
const char* MQTT_BROKER = "broker.emqx.io";       // dari Deployment Overview
const int   MQTT_PORT   = 1883;
const char* MQTT_USER   = "";   // dari Authentication
const char* MQTT_PASS  = "";   // dari Authentication
const char* MQTT_CLIENT = "inkubator_esp32_01";

const char* TOPIC_STATUS = "Inkubator_Telur_ESP32_50";
const char* TOPIC_CMD    = "Inkubator_Telur_ESP32_50/command";
// ============================================================

// ================= PIN =================
#define DHTPIN        4
#define DHTTYPE       DHT22
#define RELAY_LAMPU   26
#define RELAY_KIPAS   27
#define BUTTON_RESET  13
#define SERVO_PIN     14

// ================= OBJECT =================
DHT dht(DHTPIN, DHTTYPE);
RTC_DS3231 rtc;
Servo servoMotor;
LiquidCrystal_I2C lcd(0x27, 16, 2);

#define SCREEN_WIDTH  128
#define SCREEN_HEIGHT 64
Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, -1);

WiFiClient   wifiClient;
PubSubClient mqtt(wifiClient);

// ================= VARIABEL =================
float suhu = 0;
float hum  = 0;

bool lampu = false;
bool kipas = false;
bool rtcOK  = false;
bool oledOK = false;

unsigned long lastSensor    = 0;
unsigned long lastServo     = 0;
unsigned long lastMQTT      = 0;
unsigned long lastReconnect = 0;

const unsigned long intervalSensor    = 2000;
const unsigned long intervalMQTT      = 5000;
const unsigned long intervalReconnect = 5000;
const unsigned long intervalServo     = 28800000UL; // fallback millis (8 jam)

int posisiServo       = 0;
int jamRotasiTerakhir = -1;

DateTime waktuMulai;

// ================= WIFI =================
void connectWiFi() {
  Serial.print("Connecting WiFi");
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  int coba = 0;
  while (WiFi.status() != WL_CONNECTED && coba < 20) {
    delay(500);
    Serial.print(".");
    coba++;
  }
  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\nWiFi OK: " + WiFi.localIP().toString());
  } else {
    Serial.println("\nWiFi GAGAL - lanjut offline");
  }
}

// ================= MQTT CALLBACK =================
void mqttCallback(char* topic, byte* payload, unsigned int length) {
  String msg = "";
  for (int i = 0; i < length; i++) msg += (char)payload[i];

  Serial.print("[MQTT IN] ");
  Serial.println(msg);

  StaticJsonDocument<128> doc;
  if (deserializeJson(doc, msg) == DeserializationError::Ok) {
    if (doc.containsKey("reset_hari")) {
      if (rtcOK) waktuMulai = rtc.now();
      posisiServo = 0;
      servoMotor.write(45);
      lastServo = millis();
      jamRotasiTerakhir = -1;
      Serial.println("[CMD] Reset hari dari app");
    }
    if (doc.containsKey("servo_manual")) {
      int sudut = doc["servo_manual"];
      servoMotor.write(sudut);
      Serial.print("[CMD] Servo manual: ");
      Serial.println(sudut);
    }
  }
}

// ================= MQTT CONNECT =================
bool mqttConnect() {
  if (WiFi.status() != WL_CONNECTED) return false;
  if (mqtt.connected()) return true;

  Serial.print("Connecting MQTT...");
  bool ok = mqtt.connect(MQTT_CLIENT, MQTT_USER, MQTT_PASS);

  if (ok) {
    mqtt.subscribe(TOPIC_CMD);
    Serial.println(" OK");
    return true;
  }
  Serial.print(" GAGAL rc=");
  Serial.println(mqtt.state());
  return false;
}

// ================= PUBLISH =================
void publishStatus(int hari) {
  if (!mqtt.connected()) return;

  StaticJsonDocument<256> doc;
  doc["suhu"]            = suhu;
  doc["humidity"]        = hum;
  doc["lampu"]           = lampu;
  doc["kipas"]           = kipas;
  doc["hari"]            = hari;
  doc["posServo"]        = posisiServo == 0 ? 45 : 135;

  long sisaMs = (long)intervalServo - (long)(millis() - lastServo);
  if (sisaMs < 0) sisaMs = 0;
  doc["sisaRotasiMenit"] = sisaMs / 60000L;

  char buf[256];
  serializeJson(doc, buf);
  mqtt.publish(TOPIC_STATUS, buf, true);

  Serial.print("[MQTT OUT] ");
  Serial.println(buf);
}

// ================= LCD =================
void updateLCD() {
  lcd.clear();
  lcd.setCursor(0, 0);
  lcd.print("T:");
  lcd.print(suhu, 1);
  lcd.print((char)223);
  lcd.print("C ");
  lcd.print("H:");
  lcd.print((int)hum);
  lcd.print("%");

  lcd.setCursor(0, 1);
  lcd.print("L:");
  lcd.print(lampu ? "ON " : "OFF");
  lcd.print(" K:");
  lcd.print(kipas ? "ON " : "OFF");
}

// ================= OLED =================
void updateOLED(int hari) {
  if (!oledOK) return;

  long sisaMs = (long)intervalServo - (long)(millis() - lastServo);
  if (sisaMs < 0) sisaMs = 0;
  int jam   = sisaMs / 3600000L;
  int menit = (sisaMs % 3600000L) / 60000L;
  int detik = (sisaMs % 60000L) / 1000L;

  bool masaHatch = (hari >= 19);

  display.clearDisplay();
  display.setTextColor(SSD1306_WHITE);

  display.setTextSize(1);
  display.setCursor(0, 0);
  display.print("Hari Inkubasi");

  display.setTextSize(2);
  display.setCursor(0, 12);
  display.print("Hari ");
  display.print(hari);
  display.print("/21");

  display.setTextSize(1);
  display.setCursor(0, 36);
  if (masaHatch) {
    display.print("HATCH MODE");
  } else {
    display.print("Putar: ");
    if (jam > 0) {
      display.print(jam); display.print("j ");
      display.print(menit); display.print("m");
    } else if (menit > 0) {
      display.print(menit); display.print("m ");
      display.print(detik); display.print("d");
    } else {
      display.print(detik); display.print(" dtk");
    }
  }

  display.setCursor(0, 52);
  bool wifiOk = WiFi.status() == WL_CONNECTED;
  display.print(wifiOk ? "WiFi:OK " : "WiFi:-- ");
  display.print(mqtt.connected() ? "MQTT:OK" : "MQTT:--");

  display.display();
}

// ================= SETUP =================
void setup() {
  Serial.begin(115200);
  delay(500);
  Serial.println("=== INKUBATOR TELUR ESP32 ===");

  Wire.begin(21, 22);
  delay(200);

  dht.begin();
  delay(100);

  pinMode(RELAY_LAMPU,  OUTPUT);
  pinMode(RELAY_KIPAS,  OUTPUT);
  pinMode(BUTTON_RESET, INPUT_PULLUP);

  digitalWrite(RELAY_LAMPU, LOW);
  digitalWrite(RELAY_KIPAS, LOW);

  // RTC
  Serial.print("Init RTC...");
  for (int i = 0; i < 5; i++) {
    if (rtc.begin()) {
      rtcOK = true;
      if (rtc.lostPower()) {
        rtc.adjust(DateTime(F(__DATE__), F(__TIME__)));
        Serial.print("waktu direset. ");
      }
      waktuMulai = rtc.now();
      break;
    }
    Serial.print(".");
    delay(500);
  }
  Serial.println(rtcOK ? " RTC OK" : " RTC GAGAL!");

  // LCD
  lcd.init();
  lcd.backlight();
  lcd.clear();
  lcd.setCursor(0, 0);
  lcd.print("INKUBATOR");
  lcd.setCursor(0, 1);
  lcd.print(rtcOK ? "RTC: OK" : "RTC: ERROR");

  // OLED
  if (display.begin(SSD1306_SWITCHCAPVCC, 0x3C)) {
    oledOK = true;
    display.clearDisplay();
    display.setTextSize(1);
    display.setTextColor(SSD1306_WHITE);
    display.setCursor(0, 0);
    display.println("Connecting...");
    display.display();
    Serial.println("OLED OK");
  } else {
    Serial.println("OLED GAGAL!");
  }

  // Servo posisi awal 45 derajat
  servoMotor.attach(SERVO_PIN);
  servoMotor.write(45);
  posisiServo = 0;

  // WiFi & MQTT
  connectWiFi();
  mqtt.setServer(MQTT_BROKER, MQTT_PORT);
  mqtt.setCallback(mqttCallback);
  mqttConnect();

  delay(1000);
  lcd.clear();
  Serial.println("=== SYSTEM READY ===");
}

// ================= LOOP =================
void loop() {

  // Reconnect WiFi
  if (WiFi.status() != WL_CONNECTED &&
      millis() - lastReconnect > intervalReconnect) {
    lastReconnect = millis();
    connectWiFi();
  }

  // Reconnect MQTT
  if (!mqtt.connected() &&
      millis() - lastReconnect > intervalReconnect) {
    lastReconnect = millis();
    mqttConnect();
  }
  mqtt.loop();

  // Hitung hari
  int hari = 1;
  if (rtcOK) {
    DateTime now = rtc.now();
    hari = (int)((now.unixtime() - waktuMulai.unixtime()) / 86400L) + 1;
    if (hari < 1)  hari = 1;
    if (hari > 21) hari = 21;
  }

  // ── Tombol reset hari ──
  if (digitalRead(BUTTON_RESET) == LOW) {
    delay(50);
    if (digitalRead(BUTTON_RESET) == LOW) {
      if (rtcOK) waktuMulai = rtc.now();
      posisiServo = 0;
      servoMotor.write(45);
      lastServo = millis();
      jamRotasiTerakhir = -1;
      Serial.println("[RESET] Hari direset ke 1");
      while (digitalRead(BUTTON_RESET) == LOW);
    }
  }

  // ── Baca DHT tiap 2 detik ──
  if (millis() - lastSensor > intervalSensor) {
    lastSensor = millis();

    float t = dht.readTemperature();
    float h = dht.readHumidity();

    if (!isnan(t) && !isnan(h)) {
      suhu = t;
      hum  = h;

      if (suhu < 36.5)      lampu = true;
      else if (suhu > 37.5) lampu = false;

      if (suhu > 37.5)      kipas = true;
      else if (suhu < 36.5) kipas = false;

      digitalWrite(RELAY_LAMPU, lampu ? HIGH : LOW);
      digitalWrite(RELAY_KIPAS, kipas ? HIGH : LOW);

      updateLCD();
      updateOLED(hari);

      Serial.printf("[SENSOR] Suhu:%.1fC Hum:%.0f%% Lampu:%s Kipas:%s Hari:%d\n",
        suhu, hum,
        lampu ? "ON" : "OFF",
        kipas ? "ON" : "OFF",
        hari);
    } else {
      Serial.println("[ERROR] DHT22 gagal");
    }
  }

  // ── Publish MQTT tiap 5 detik ──
  if (millis() - lastMQTT > intervalMQTT) {
    lastMQTT = millis();
    publishStatus(hari);
  }

  // ── Rotasi servo via RTC ──
  if (rtcOK) {
    DateTime now = rtc.now();
    int jamSekarang = now.hour();
    bool jadwal = (jamSekarang == 6 || jamSekarang == 14 || jamSekarang == 22);
    bool aktif  = (hari >= 1 && hari <= 18);

    if (jadwal && aktif && jamSekarang != jamRotasiTerakhir) {
      jamRotasiTerakhir = jamSekarang;
      lastServo = millis();
      if (posisiServo == 0) {
        servoMotor.write(135);
        posisiServo = 1;
        Serial.println("[SERVO] 135 derajat");
      } else {
        servoMotor.write(45);
        posisiServo = 0;
        Serial.println("[SERVO] 45 derajat");
      }
    }
  } else {
    if (millis() - lastServo > intervalServo) {
      lastServo = millis();
      if (posisiServo == 0) {
        servoMotor.write(135);
        posisiServo = 1;
      } else {
        servoMotor.write(45);
        posisiServo = 0;
      }
      Serial.println("[SERVO] Rotasi millis fallback");
    }
  }
}
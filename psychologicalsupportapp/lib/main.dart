import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(
    MaterialApp(
      title: 'Duygu Analizi',
      theme: ThemeData(
        fontFamily: 'Roboto',
        scaffoldBackgroundColor: Color(0xFFF0F2F5),
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: AudioToEmotionPage(),
    ),
  );
}

class AudioToEmotionPage extends StatefulWidget {
  @override
  _AudioToEmotionPageState createState() => _AudioToEmotionPageState();
}

class _AudioToEmotionPageState extends State<AudioToEmotionPage> {
  Map<String, dynamic>? result;
  String status = 'Henüz analiz yapılmadı.';
  bool loading = false;
  FlutterSoundRecorder? _recorder;
  bool _isRecording = false;
  String? recordedPath;

  final whisperUrl = Uri.parse(
    'https://drum-resolved-earwig.ngrok-free.app/transcribe',
  );
  final emotionUrl = Uri.parse(
    'https://drum-resolved-earwig.ngrok-free.app/analyze',
  );

  @override
  void initState() {
    super.initState();
    _recorder = FlutterSoundRecorder();
    initRecorder();
  }

  Future<void> initRecorder() async {
    await Permission.microphone.request();
    await _recorder!.openRecorder();
  }

  Future<String> _getTempPath() async {
    final dir = await getTemporaryDirectory();
    return '${dir.path}/recorded.aac';
  }

  Future<void> startRecording() async {
    final path = await _getTempPath();
    await _recorder!.startRecorder(toFile: path, codec: Codec.aacADTS);
    setState(() {
      _isRecording = true;
      recordedPath = path;
      status = '🎤 Kayıt yapılıyor...';
    });
  }

  Future<void> stopRecordingAndAnalyze() async {
    await _recorder!.stopRecorder();
    setState(() {
      _isRecording = false;
    });

    if (recordedPath != null) {
      await sendToWhisper(File(recordedPath!));
    }
  }

  Future<void> sendToWhisper(File audioFile) async {
    setState(() {
      loading = true;
      status = '📤 Whisper’a gönderiliyor...';
      result = null;
    });

    try {
      var request = http.MultipartRequest('POST', whisperUrl);
      request.files.add(
        await http.MultipartFile.fromPath('file', audioFile.path),
      );
      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final text = data['text'];
        status = '📄 Metin: \"$text\"\n\n🧠 Duygu analizi yapılıyor...';
        await sendToEmotion(text);
      } else {
        setState(() {
          status = '⚠️ Whisper sunucu hatası: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        status = '❌ Whisper bağlantı hatası: $e';
      });
    }

    setState(() => loading = false);
  }

  Future<void> sendToEmotion(String text) async {
    setState(() {
      loading = true;
      status = '🧠 Duygu analizi yapılıyor...';
      result = null;
    });

    try {
      final response = await http.post(
        emotionUrl,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'text': text, 'language': 'tr'}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          result = data;
          status = '✅ Analiz tamamlandı';
        });
      } else {
        setState(() {
          status = '⚠️ Duygu sunucu hatası: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        status = '❌ Duygu bağlantı hatası: $e';
      });
    }

    setState(() => loading = false);
  }

  Future<void> testWithSampleText() async {
    final text = "Zerdayı vurmak istiyorum :D:D:D.";
    setState(() {
      status = '📝 Test metni gönderiliyor...';
      result = null;
    });
    await sendToEmotion(text);
  }

  Widget resultSection(Map<String, dynamic> resultData) {
    final emotionEmojis = {
      "joy": "😊",
      "sadness": "😢",
      "anger": "😠",
      "fear": "😨",
      "surprise": "😲",
      "love": "❤️",
      "neutral": "😐",
      "disgust": "🤢",
      "admiration": "🥰",
      "amusement": "😄",
      "annoyance": "😤",
      "approval": "👍",
      "caring": "🤗",
      "confusion": "😕",
      "curiosity": "🤔",
      "desire": "😍",
      "disappointment": "😞",
      "disapproval": "👎",
      "embarrassment": "😳",
      "excitement": "🤩",
      "gratitude": "🙏",
      "grief": "💔",
      "nervousness": "😰",
      "optimism": "🌟",
      "pride": "🦁",
      "realization": "💡",
      "relief": "😌",
      "remorse": "😔",
    };

    return Card(
      color: Colors.white,
      elevation: 5,
      margin: EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Column(
                children: [
                  Text(
                    emotionEmojis[resultData['label']
                            .toString()
                            .toLowerCase()] ??
                        "🤔",
                    style: TextStyle(fontSize: 50),
                  ),
                  SizedBox(height: 10),
                  Text(
                    resultData['label'].toString(),
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    "Skor: %${resultData['probability'].toStringAsFixed(1)}",
                  ),
                ],
              ),
            ),
            SizedBox(height: 20),
            if (resultData['original_text'] != null) ...[
              Text(
                "📝 Orijinal Metin:",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(resultData['original_text']),
              SizedBox(height: 10),
              Text("🌐 Çeviri:", style: TextStyle(fontWeight: FontWeight.bold)),
              Text(resultData['translated_text'] ?? "Çeviri yok"),
              SizedBox(height: 20),
            ],
            if (resultData['alternatives'] != null &&
                resultData['alternatives'].isNotEmpty) ...[
              Text(
                "🔁 Alternatif Duygular:",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              ...List.generate(resultData['alternatives'].length, (i) {
                final alt = resultData['alternatives'][i];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Text(
                    emotionEmojis[alt['emotion'].toLowerCase()] ?? "🤔",
                    style: TextStyle(fontSize: 24),
                  ),
                  title: Text(alt['emotion']),
                  trailing: Text("%${alt['probability'].toStringAsFixed(1)}"),
                );
              }),
            ],
            if (resultData['support'] != null) ...[
              SizedBox(height: 20),
              Text(
                "🤖 Destek Mesajı:",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.teal,
                ),
              ),
              SelectableText(
                result?['support'] ?? '',
                style: TextStyle(fontSize: 16),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _recorder!.closeRecorder();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '🎙️ Duygu Analizi Asistanı',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: ListView(
          children: [
            ElevatedButton.icon(
              icon: Icon(_isRecording ? Icons.stop : Icons.mic),
              label: Text(_isRecording ? 'Kaydı Durdur' : 'Kayda Başla'),
              onPressed:
                  loading
                      ? null
                      : _isRecording
                      ? stopRecordingAndAnalyze
                      : startRecording,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isRecording ? Colors.red : Colors.deepPurple,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                textStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            SizedBox(height: 12),
            ElevatedButton.icon(
              icon: Icon(Icons.bug_report),
              label: Text('Test Et (Örnek Metin)'),
              onPressed: loading ? null : testWithSampleText,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
            ),
            SizedBox(height: 20),
            Text(
              status,
              style: TextStyle(
                fontSize: 16,
                color: Colors.black87,
                fontStyle: FontStyle.italic,
              ),
            ),
            if (result != null) resultSection(result!),
          ],
        ),
      ),
    );
  }
}

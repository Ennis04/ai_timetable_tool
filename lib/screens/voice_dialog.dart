import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart'; // Import this specifically
import 'package:permission_handler/permission_handler.dart';
import '../models/calendar_event.dart';
import '../services/nlp_service.dart';

class VoiceEntryDialog extends StatefulWidget {
  const VoiceEntryDialog({super.key});

  @override
  State<VoiceEntryDialog> createState() => _VoiceEntryDialogState();
}

class _VoiceEntryDialogState extends State<VoiceEntryDialog> {
  late stt.SpeechToText _speech;
  bool _isListening = false;
  String _text = 'Press the mic and speak...';
  double _confidence = 1.0;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    // Check permissions immediately
    var status = await Permission.microphone.request();
    if (status.isGranted) {
      bool available = await _speech.initialize(
        onStatus: (val) {
          // 'listening' means the mic is open
          // 'notListening' or 'done' means it closed
          if (val == 'notListening' || val == 'done') {
            setState(() => _isListening = false);
          } else if (val == 'listening') {
            setState(() => _isListening = true);
          }
        },
        onError: (val) => setState(() {
          _isListening = false;
          _text = 'Error: ${val.errorMsg}';
        }),
      );
      if (!available) {
        setState(() => _text = 'Speech recognition not available.');
      }
    } else {
      setState(() => _text = 'Microphone permission denied.');
    }
  }

  void _listen() async {
    if (!_isListening) {
      bool available = await _speech.initialize(
        onStatus: (val) {
          // Only update state if the OS forces a stop
          if (val == 'done' || val == 'notListening') {
             // Optional: You could trigger _listen() here again to force "infinite" listening, 
             // but that often causes bugs. High timeout is better.
            setState(() => _isListening = false);
          } else if (val == 'listening') {
            setState(() => _isListening = true);
          }
        },
        onError: (val) => setState(() {
          _isListening = false;
          _text = 'Error: ${val.errorMsg}';
        }),
      );

      if (available) {
        setState(() {
          _isListening = true;
          _text = "Listening... (Speak now)"; 
        });
        
        _speech.listen(
          onResult: _onSpeechResult,
          // 1. MAXIMIZE SILENCE TIMEOUT (Effective "Remove Auto-Close")
          // The mic will wait 60 seconds of pure silence before closing.
          pauseFor: const Duration(seconds: 60),
          
          // 2. MAXIMIZE SESSION DURATION
          // The mic will stay open for up to 5 minutes total.
          listenFor: const Duration(minutes: 5),
          
          // 3. SETTINGS
          partialResults: true,
          cancelOnError: false, // Do not close on minor errors
          listenMode: stt.ListenMode.dictation,
        );
      }
    } else {
      // Manual Stop
      setState(() => _isListening = false);
      _speech.stop();
    }
  }

  // New dedicated method to handle real-time updates
  void _onSpeechResult(SpeechRecognitionResult result) {
    setState(() {
      // Update the text box with what the user is currently saying
      _text = result.recognizedWords;
      
      if (result.hasConfidenceRating && result.confidence > 0) {
        _confidence = result.confidence;
      }
    });
  }

  void _processEvent() {
    if (_text.isEmpty || _text.contains('Press the mic') || _text.contains('Listening...')) return;
    
    final event = NLPService.parse(_text);
    Navigator.pop(context, event);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      // Use media query to ensure keyboard doesn't hide content if it pops up
      margin: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom), 
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Voice Entry', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          
          // Text Display Box
          Container(
            padding: const EdgeInsets.all(16),
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 100),
            decoration: BoxDecoration(
              color: _isListening ? Colors.green.withOpacity(0.1) : Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isListening ? Colors.green : Colors.transparent, 
                width: 2
              ),
            ),
            child: SingleChildScrollView(
              child: Text(
                _text,
                style: TextStyle(
                  fontSize: 18, 
                  color: _isListening ? Colors.black87 : Colors.grey[700]
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          
          const SizedBox(height: 10),
          if (_text != 'Press the mic and speak...' && _text != 'Listening... (Speak now)')
            Text(
              'Confidence: ${(_confidence * 100).toStringAsFixed(1)}%',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            
          const SizedBox(height: 30),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Mic Button with Animation Logic
              GestureDetector(
                onTap: _listen,
                child: CircleAvatar(
                  radius: 30,
                  backgroundColor: _isListening ? Colors.red : Colors.blue,
                  child: Icon(
                    _isListening ? Icons.stop : Icons.mic, 
                    color: Colors.white, 
                    size: 30
                  ),
                ),
              ),
              
              // Confirm Button
              if (_text.isNotEmpty && 
                  !_text.contains('Press the mic') && 
                  !_text.contains('Listening...') && 
                  !_text.startsWith('Error'))
                GestureDetector(
                  onTap: _processEvent,
                  child: const CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.green,
                    child: Icon(Icons.check, color: Colors.white, size: 30),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
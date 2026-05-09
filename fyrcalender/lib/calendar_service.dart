import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:googleapis/calendar/v3.dart' as cal;
import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class CalendarEvent {
  final String id;
  final String title;
  final String? description;
  final DateTime startTime;
  final DateTime endTime;
  final bool isAllDay;
  final String? location;
  final String source; // 'local' or 'google'
  final String? googleId;

  CalendarEvent({
    required this.id,
    required this.title,
    this.description,
    required this.startTime,
    required this.endTime,
    this.isAllDay = false,
    this.location,
    required this.source,
    this.googleId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime.toIso8601String(),
        'isAllDay': isAllDay,
        'location': location,
        'source': source,
        'googleId': googleId,
      };

  factory CalendarEvent.fromJson(Map<String, dynamic> json) => CalendarEvent(
        id: json['id'],
        title: json['title'],
        description: json['description'],
        startTime: DateTime.parse(json['startTime']),
        endTime: DateTime.parse(json['endTime']),
        isAllDay: json['isAllDay'] ?? false,
        location: json['location'],
        source: json['source'] ?? 'local',
        googleId: json['googleId'],
      );
}

class CalendarService {
  static final String _configPath = p.join(
    Platform.environment['HOME'] ?? '',
    '.config/fyr/calendar_events.json',
  );

  static final ValueNotifier<List<CalendarEvent>> events = ValueNotifier([]);
  static final ValueNotifier<bool> isGoogleSignedIn = ValueNotifier(false);
  
  // NOTE: Replace these with your actual Google Cloud credentials for a Desktop App
  static const String _clientId = 'YOUR_CLIENT_ID.apps.googleusercontent.com';
  static const String _clientSecret = 'YOUR_CLIENT_SECRET';

  static auth.AuthClient? _authClient;

  static Future<void> initialize() async {
    await loadLocalEvents();
    // In a real app, we would load stored credentials here
  }

  static Future<void> loadLocalEvents() async {
    try {
      final file = File(_configPath);
      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> data = jsonDecode(content);
        events.value = data.map((e) => CalendarEvent.fromJson(e)).toList();
      }
    } catch (e) {
      debugPrint('Error loading events: $e');
    }
  }

  static Future<void> saveLocalEvents() async {
    try {
      final file = File(_configPath);
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      final localEvents = events.value.where((e) => e.source == 'local').toList();
      await file.writeAsString(jsonEncode(localEvents.map((e) => e.toJson()).toList()));
    } catch (e) {
      debugPrint('Error saving events: $e');
    }
  }

  static Future<void> addEvent(CalendarEvent event) async {
    events.value = [...events.value, event];
    if (event.source == 'local') {
      await saveLocalEvents();
    }
  }

  static Future<void> deleteEvent(String id) async {
    final event = events.value.firstWhere((e) => e.id == id);
    events.value = events.value.where((e) => e.id != id).toList();
    if (event.source == 'local') {
      await saveLocalEvents();
    }
  }

  static Future<void> signInGoogle() async {
    final identifier = auth.ClientId(_clientId, _clientSecret);
    final List<String> scopes = [cal.CalendarApi.calendarReadonlyScope];

    try {
      _authClient = await auth.clientViaUserConsent(identifier, scopes, (url) async {
        debugPrint('Launching Auth URL: $url');
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.platformDefault);
        } else {
          // Fallback for FyrBrowser on Linux
          await Process.run('fyrbrowser', [url]);
        }
      });
      
      isGoogleSignedIn.value = true;
      await syncGoogleCalendar();
    } catch (e) {
      debugPrint('Error signing in to Google: $e');
    }
  }

  static Future<void> signOutGoogle() async {
    _authClient?.close();
    _authClient = null;
    isGoogleSignedIn.value = false;
    events.value = events.value.where((e) => e.source != 'google').toList();
  }

  static Future<void> syncGoogleCalendar() async {
    if (_authClient == null) return;

    final calendarApi = cal.CalendarApi(_authClient!);

    try {
      final googleEvents = await calendarApi.events.list('primary');
      final List<CalendarEvent> convertedEvents = [];

      for (var e in googleEvents.items ?? []) {
        if (e.start?.dateTime == null && e.start?.date == null) continue;

        convertedEvents.add(CalendarEvent(
          id: 'google_${e.id}',
          title: e.summary ?? '(No Title)',
          description: e.description,
          startTime: e.start?.dateTime ?? e.start!.date!,
          endTime: e.end?.dateTime ?? e.end!.date!,
          isAllDay: e.start?.dateTime == null,
          location: e.location,
          source: 'google',
          googleId: e.id,
        ));
      }

      // Merge with local events
      final localEvents = events.value.where((e) => e.source == 'local').toList();
      events.value = [...localEvents, ...convertedEvents];
    } catch (e) {
      debugPrint('Error syncing Google Calendar: $e');
    }
  }
}

import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:http/http.dart' as http;
import '../models/absence_request.dart';
import '../models/cover_offer.dart';
import '../models/duty_post.dart';
import '../models/special_request.dart';
import '../models/attendance_report.dart';
import '../models/employee.dart';
import '../models/employee_notification.dart';
import '../models/leave_request.dart';
import '../models/post_time.dart';
import '../models/replacement.dart';
import '../models/guard_shift.dart';
import '../models/schedule.dart';
import '../models/schedule_note.dart';
import '../models/special_assignment.dart';
import '../models/station.dart';
import '../models/station_roster.dart';

class ApiService {
  // The deployed API, passed in whole at build time:
  //   flutter build apk --release \
  //     --dart-define=API_BASE_URL=https://YOUR-SERVICE.onrender.com
  //
  // This has to be the FULL origin, not a host. API_HOST below cannot
  // reach Render: it hardcodes "http://" and ":8000", so a Render host
  // would build http://YOUR-SERVICE.onrender.com:8000 -- wrong scheme and a
  // port nothing listens on. Render serves HTTPS on 443.
  static const String _apiBaseUrlOverride =
      String.fromEnvironment("API_BASE_URL");

  // A physical device on the LAN, talking to a laptop running uvicorn,
  // needs the host machine's LAN IP -- still http, still :8000:
  //   flutter build apk --release --dart-define=API_HOST=192.168.1.3
  static const String _apiHostOverride = String.fromEnvironment("API_HOST");

  // Web (Chrome) and iOS simulators reach the host machine via 127.0.0.1.
  // Android emulators (AVD) resolve 127.0.0.1 to the emulator itself, not
  // the host -- 10.0.2.2 is the AVD's special alias for host loopback.
  static String get baseUrl {
    if (_apiBaseUrlOverride.isNotEmpty) {
      // Trailing slashes would double up against the "$baseUrl/employees"
      // concatenations below.
      return _apiBaseUrlOverride.replaceAll(RegExp(r"/+$"), "");
    }
    if (_apiHostOverride.isNotEmpty) {
      return "http://$_apiHostOverride:8000";
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return "http://10.0.2.2:8000";
    }
    return "http://127.0.0.1:8000";
  }

  // Re-checks the signed-in user's own password. Used to gate Developer
  // mode in admin Settings — see ServerClock.
  static Future<Map<String, dynamic>> verifyPassword({
    required String username,
    required String password,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse("$baseUrl/verify-password"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"username": username, "password": password}),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) return {"success": true};
      return {
        "success": false,
        "error": data["detail"] ?? "Password is incorrect.",
      };
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  // The server's wall clock, used by ServerClock to correct the device
  // clock. Kept on a short timeout because the offset it measures gets
  // less accurate the longer the round trip takes.
  static Future<Map<String, dynamic>> fetchServerTime() async {
    try {
      final response = await http
          .get(Uri.parse("$baseUrl/server-time"))
          .timeout(const Duration(seconds: 8));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {"success": true, "now": data["now"]};
      }
      return {
        "success": false,
        "error": data["detail"] ?? "Failed to fetch server time",
      };
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  // Turns raw client-side exception text (SocketException, timeouts,
  // failed host lookups...) into a short human-readable message for the
  // UI. Server-sent error details pass through unchanged.
  static String friendlyError(String error) {
    final lower = error.toLowerCase();
    if (lower.contains('socketexception') ||
        lower.contains('clientexception') ||
        lower.contains('timeoutexception') ||
        lower.contains('failed host lookup') ||
        lower.contains('connection refused') ||
        lower.contains('connection failed') ||
        lower.contains('connection timed out')) {
      return 'Could not reach the Sched server. Please check your '
          'internet connection and try again.';
    }
    return error;
  }

  static Future<Map<String, dynamic>> testConnection() async {
    try {
      final response = await http
          .get(Uri.parse("$baseUrl/test-connection"))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return {
          "success": true,
          "data": jsonDecode(response.body),
        };
      } else {
        return {
          "success": false,
          "error": "Server responded with status ${response.statusCode}",
        };
      }
    } catch (e) {
      return {
        "success": false,
        "error": e.toString(),
      };
    }
  }

  // Sends the Add Employee form to Python, which generates the
  // username/password, creates the login credential, and saves
  // the record to Firestore. Returns the created employee (with
  // credentials) on success.
  static Future<Map<String, dynamic>> createEmployee({
    required String name,
    required String mobileNo,
    required String role,
    String? email,
    List<String> preferredStations = const [],
  }) async {
    try {
      final response = await http
          .post(
        Uri.parse("$baseUrl/employees"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "name": name,
          "mobileNo": mobileNo,
          "role": role,
          "email": email,
          "preferredStations": preferredStations,
        }),
      )
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          "success": true,
          "employee": Employee.fromJson(data["employee"]),
        };
      } else {
        return {
          "success": false,
          "error": data["detail"] ?? "Failed to create employee",
        };
      }
    } catch (e) {
      return {
        "success": false,
        "error": e.toString(),
      };
    }
  }

  // Updates an employee's editable fields. username/password/dateJoined
  // are generated once at creation and never sent here.
  static Future<Map<String, dynamic>> updateEmployee(
      String id, {
        String? name,
        String? email,
        String? phone,
        List<String>? preferredStations,
        EmployeeType? type,
        bool? isActive,
      }) async {
    try {
      final Map<String, dynamic> body = {};
      if (name != null) body["name"] = name;
      if (email != null) body["email"] = email;
      if (phone != null) body["phone"] = phone;
      if (preferredStations != null) {
        body["preferredStations"] = preferredStations;
      }
      if (type != null) body["type"] = type.name;
      if (isActive != null) body["isActive"] = isActive;

      final response = await http
          .put(
        Uri.parse("$baseUrl/employees/$id"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(body),
      )
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          "success": true,
          "employee": Employee.fromJson(data["employee"]),
        };
      } else {
        return {
          "success": false,
          "error": data["detail"] ?? "Failed to update employee",
        };
      }
    } catch (e) {
      return {
        "success": false,
        "error": e.toString(),
      };
    }
  }

  // Sends login credentials to the Python FastAPI backend.
  // Returns success status and the user's role upon successful authentication.
  static Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      final response = await http
          .post(
        // Adjust the endpoint if your FastAPI route is named differently
        Uri.parse("$baseUrl/login"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "username": username,
          "password": password,
        }),
      )
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          "success": true,
          // Make sure your FastAPI backend actually returns a "role" field!
          "role": data["role"],
          // True when the employee is still on their auto-generated
          // password and must set a new one before entering the app.
          "mustChangePassword": data["mustChangePassword"] ?? false,
          // True until the employee confirms their preferred stations once
          // (shown right after the first password change).
          "mustSelectStations": data["mustSelectStations"] ?? false,
          // The preferences already on the record, so the onboarding picker
          // can open pre-selected.
          "preferredStations": data["preferredStations"] != null
              ? List<String>.from(data["preferredStations"])
              : <String>[],
        };
      } else {
        return {
          "success": false,
          "error": data["detail"] ?? "Invalid username or password.",
        };
      }
    } catch (e) {
      return {
        "success": false,
        "error": e.toString(),
      };
    }
  }

  // Replaces an employee's auto-generated password on first login. The
  // backend re-verifies the current password before updating the credential.
  static Future<Map<String, dynamic>> changePassword({
    required String username,
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final response = await http
          .post(
        Uri.parse("$baseUrl/change-password"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "username": username,
          "currentPassword": currentPassword,
          "newPassword": newPassword,
        }),
      )
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {"success": true};
      } else {
        return {
          "success": false,
          "error": data["detail"] ?? "Failed to change password.",
        };
      }
    } catch (e) {
      return {
        "success": false,
        "error": e.toString(),
      };
    }
  }

  // Issues a NEW password for an employee and returns it once.
  //
  // Stored passwords are bcrypt hashes and cannot be read back, so a guard
  // who forgets theirs is given a fresh one rather than told the old one.
  // The password in the response is the only time it is readable — it is
  // not stored anywhere that can be displayed again. The employee is forced
  // to replace it on their next login.
  static Future<Map<String, dynamic>> resetEmployeePassword(String id) async {
    try {
      final response = await http
          .post(
            Uri.parse("$baseUrl/employees/$id/reset-password"),
            headers: {"Content-Type": "application/json"},
          )
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {"success": true, "password": data["password"] ?? ""};
      } else {
        return {
          "success": false,
          "error": data["detail"] ?? "Failed to reset the password.",
        };
      }
    } catch (e) {
      return {
        "success": false,
        "error": e.toString(),
      };
    }
  }

  // Saves the employee's confirmed preferred stations during onboarding and
  // clears the server-side mustSelectStations flag, so the onboarding picker
  // is shown only once. Returns the updated employee on success.
  static Future<Map<String, dynamic>> confirmPreferredStations({
    required String username,
    required List<String> preferredStations,
  }) async {
    try {
      final response = await http
          .post(
        Uri.parse("$baseUrl/confirm-stations"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "username": username,
          "preferredStations": preferredStations,
        }),
      )
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          "success": true,
          "employee": Employee.fromJson(data["employee"]),
        };
      } else {
        return {
          "success": false,
          "error": data["detail"] ?? "Failed to save preferred stations.",
        };
      }
    } catch (e) {
      return {
        "success": false,
        "error": e.toString(),
      };
    }
  }

  // Deletes an employee record (and their login credential).
  static Future<Map<String, dynamic>> deleteEmployee(String id) async {
    try {
      final response = await http
          .delete(Uri.parse("$baseUrl/employees/$id"))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return {"success": true};
      } else {
        final data = jsonDecode(response.body);
        return {
          "success": false,
          "error": data["detail"] ?? "Failed to delete employee",
        };
      }
    } catch (e) {
      return {
        "success": false,
        "error": e.toString(),
      };
    }
  }

  // Fetches every employee from Firestore (via Python), used by the
  // Employee List screen.
  static Future<Map<String, dynamic>> fetchEmployees() async {
    try {
      final response = await http
          .get(Uri.parse("$baseUrl/employees"))
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final List<dynamic> raw = data["employees"] ?? [];
        return {
          "success": true,
          "employees": raw.map((e) => Employee.fromJson(e)).toList(),
        };
      } else {
        return {
          "success": false,
          "error": data["detail"] ?? "Failed to fetch employees",
        };
      }
    } catch (e) {
      return {
        "success": false,
        "error": e.toString(),
      };
    }
  }

  // Fetches one employee's record — used by the guard-facing screens
  // right after login (the username doubles as the document ID).
  static Future<Map<String, dynamic>> fetchEmployee(String id) async {
    try {
      final response = await http
          .get(Uri.parse("$baseUrl/employees/$id"))
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          "success": true,
          "employee": Employee.fromJson(data["employee"]),
        };
      } else {
        return {
          "success": false,
          "error": data["detail"] ?? "Failed to fetch employee",
        };
      }
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  // Fetches the logged-in guard's own shifts (from published schedules
  // only) plus the schedule periods they appear in, so the app can tell
  // duty days from rest days.
  static Future<Map<String, dynamic>> fetchEmployeeSchedule(String id) async {
    try {
      final response = await http
          .get(Uri.parse("$baseUrl/employees/$id/schedule"))
          .timeout(const Duration(seconds: 30));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final List<dynamic> rawShifts = data["shifts"] ?? [];
        final List<dynamic> rawPeriods = data["periods"] ?? [];
        return {
          "success": true,
          "shifts": rawShifts
              .map((s) => GuardShift.fromJson(Map<String, dynamic>.from(s)))
              .toList(),
          "periods": rawPeriods
              .map((p) => GuardPeriod.fromJson(Map<String, dynamic>.from(p)))
              .toList(),
        };
      } else {
        return {
          "success": false,
          "error": data["detail"] ?? "Failed to fetch schedule",
        };
      }
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  // Fetches today's roster for the employee's station (on duty / day off),
  // built from the published schedule — Head Guard dashboard + overview.
  // `date` (YYYY-MM-DD) defaults to today on the server. The head guard
  // layout passes one explicitly for the after-midnight tail of an
  // overnight duty, when the roster being worked is yesterday's.
  static Future<Map<String, dynamic>> fetchStationOverview(
    String id, {
    String? date,
  }) async {
    try {
      final uri = Uri.parse("$baseUrl/employees/$id/station-overview")
          .replace(queryParameters: date == null ? null : {'date': date});
      final response =
          await http.get(uri).timeout(const Duration(seconds: 30));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          "success": true,
          "roster": StationRoster.fromJson(
              Map<String, dynamic>.from(data["overview"])),
        };
      } else {
        return {
          "success": false,
          "error": data["detail"] ?? "Failed to fetch station overview",
        };
      }
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  // --- Stations ---

  // Sends the Add Station form to Python, which generates a sequential
  // station ID (e.g. STA001) and saves the record to Firestore. Returns
  // the created station on success.
  static Future<Map<String, dynamic>> createStation({
    required String name,
    required int requiredMorning,
    required int requiredAfternoon,
    required int requiredNight,
    List<String> morningPosts = const [],
    List<String> afternoonPosts = const [],
    List<String> nightPosts = const [],
    List<PostTime> morningPostTimes = const [],
    List<PostTime> afternoonPostTimes = const [],
    List<PostTime> nightPostTimes = const [],
  }) async {
    try {
      final response = await http
          .post(
        Uri.parse("$baseUrl/stations"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "name": name,
          "requiredMorning": requiredMorning,
          "requiredAfternoon": requiredAfternoon,
          "requiredNight": requiredNight,
          "posts": {
            "morning": morningPosts,
            "afternoon": afternoonPosts,
            "night": nightPosts,
          },
          // The backend re-derives these through the same stagger ladder
          // before saving, so what's sent here only has to carry the
          // admin's hand-pinned slots — the rest is recomputed anyway.
          "postTimes": {
            "morning": morningPostTimes.map((t) => t.toJson()).toList(),
            "afternoon": afternoonPostTimes.map((t) => t.toJson()).toList(),
            "night": nightPostTimes.map((t) => t.toJson()).toList(),
          },
        }),
      )
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          "success": true,
          "station": Station.fromJson(data["station"]),
        };
      } else {
        return {
          "success": false,
          "error": data["detail"] ?? "Failed to create station",
        };
      }
    } catch (e) {
      return {
        "success": false,
        "error": e.toString(),
      };
    }
  }

  // Updates a station's editable fields: the per-shift required numbers
  // and the per-shift post lists. The daily total (requiredEmployees) is
  // derived by the backend, and the station ID never changes.
  //
  // `name` is still accepted — the backend re-points employees, schedules
  // and pins at the new name — but Edit Station no longer offers it, so
  // in practice only the shift setup is sent.
  static Future<Map<String, dynamic>> updateStation(
    String id, {
    String? name,
    int? requiredMorning,
    int? requiredAfternoon,
    int? requiredNight,
    List<String>? morningPosts,
    List<String>? afternoonPosts,
    List<String>? nightPosts,
    List<PostTime>? morningPostTimes,
    List<PostTime>? afternoonPostTimes,
    List<PostTime>? nightPostTimes,
  }) async {
    try {
      final Map<String, dynamic> body = {};
      if (name != null) body["name"] = name;
      if (requiredMorning != null) body["requiredMorning"] = requiredMorning;
      if (requiredAfternoon != null) {
        body["requiredAfternoon"] = requiredAfternoon;
      }
      if (requiredNight != null) body["requiredNight"] = requiredNight;
      if (morningPosts != null ||
          afternoonPosts != null ||
          nightPosts != null) {
        body["posts"] = {
          "morning": morningPosts ?? const <String>[],
          "afternoon": afternoonPosts ?? const <String>[],
          "night": nightPosts ?? const <String>[],
        };
      }
      // Sent whenever posts are, so the two stay in step: the backend
      // re-runs both through the stagger ladder together and a times
      // payload that lagged behind the post list would re-stagger the
      // wrong slots.
      if (morningPostTimes != null ||
          afternoonPostTimes != null ||
          nightPostTimes != null) {
        body["postTimes"] = {
          "morning":
              (morningPostTimes ?? const <PostTime>[]).map((t) => t.toJson()).toList(),
          "afternoon":
              (afternoonPostTimes ?? const <PostTime>[]).map((t) => t.toJson()).toList(),
          "night":
              (nightPostTimes ?? const <PostTime>[]).map((t) => t.toJson()).toList(),
        };
      }

      final response = await http
          .put(
        Uri.parse("$baseUrl/stations/$id"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(body),
      )
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          "success": true,
          "station": Station.fromJson(data["station"]),
        };
      } else {
        return {
          "success": false,
          "error": data["detail"] ?? "Failed to update station",
        };
      }
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  // Deletes a station (and every schedule generated for it).
  static Future<Map<String, dynamic>> deleteStation(String id) async {
    try {
      final response = await http
          .delete(Uri.parse("$baseUrl/stations/$id"))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return {"success": true};
      }
      final data = jsonDecode(response.body);
      return {
        "success": false,
        "error": data["detail"] ?? "Failed to delete station",
      };
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  // --- Schedules ---

  // What the generator had to bend, as structured notes. The reading
  // lives in schedule_note.dart so a stored schedule and a generate
  // response are parsed by the same code.
  static List<ScheduleNote> _parseNotes(Map<String, dynamic> data) =>
      parseScheduleNotes(data);

  // Asks Python to generate the bi-weekly (15-day) schedule for every
  // station in the group. The backend saves them as unpublished and
  // returns them. Re-generating the same group + start date overwrites
  // the previous result.
  //
  // Pass [stationId] to generate for one station only. The backend still
  // works out the whole group (rotation placement and the shared
  // reliever/substitute pools are group-wide facts, so the station would
  // otherwise get a different roster than a group run gives it) but saves
  // only that station, leaving its siblings' schedules alone. [group] is
  // ignored in that case — the server derives it from the station.
  static Future<Map<String, dynamic>> generateSchedules({
    required int group,
    required DateTime startDate,
    bool overwrite = false,
    bool rotate = true,
    String? stationId,
  }) async {
    try {
      final response = await http
          .post(
        Uri.parse("$baseUrl/schedules/generate"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "group": group,
          "startDate": startDate.toIso8601String().substring(0, 10),
          "overwrite": overwrite,
          // Monthly station rotation — the backend keeps at least two
          // familiar guards per station and reuses the placement for
          // every period in the same month.
          "rotate": rotate,
          "stationId": ?stationId,
        }),
      )
          .timeout(const Duration(seconds: 60));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final List<dynamic> raw = data["schedules"] ?? [];
        return {
          "success": true,
          "schedules": raw
              .map((s) => Schedule.fromJson(Map<String, dynamic>.from(s)))
              .toList(),
          // Everything the generator had to bend, tagged by category and
          // severity. Schedules generated before notes carried structure
          // only have the flat strings, so those are rebuilt as plain
          // warnings rather than dropped.
          "notes": _parseNotes(data),
        };
      } else {
        // Two different 409s come back from this endpoint. A plain string
        // detail is "this period already has a schedule", which
        // regenerating with overwrite fixes — so the caller asks first.
        // A map detail carries a `code` for a refusal overwrite can NOT
        // fix, currently a special assignment that would leave a guard
        // rostered at two stations at once.
        final detail = data["detail"];
        final String? code =
            detail is Map ? detail["code"] as String? : null;
        final message = detail is Map
            ? (detail["message"] ?? "Failed to generate schedules")
            : (detail ?? "Failed to generate schedules");

        return {
          "success": false,
          "conflict": response.statusCode == 409 && code == null,
          "code": code,
          // Stations the caller has to regenerate, when the backend
          // named them (special_assignment_clash only).
          "stations": detail is Map
              ? List<Map<String, dynamic>>.from(
                  (detail["stations"] as List? ?? [])
                      .map((s) => Map<String, dynamic>.from(s)))
              : <Map<String, dynamic>>[],
          "error": message,
        };
      }
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  // Where every employee is already rostered during one cycle's month,
  // as {employeeId: [DutyPost]}. The Special Assignments picker uses it
  // to flag a guard who is already on another station's schedule for the
  // dates being pinned — pinning them strands that station's roster.
  static Future<Map<String, dynamic>> fetchDutyStatus(String cycleId) async {
    try {
      final response = await http
          .get(Uri.parse(
              "$baseUrl/special-assignments/duty-status?cycleId=$cycleId"))
          .timeout(const Duration(seconds: 20));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final raw = Map<String, dynamic>.from(data["dutyStatus"] ?? {});
        return {
          "success": true,
          "dutyStatus": raw.map(
            (employeeId, posts) => MapEntry(
              employeeId,
              (posts as List)
                  .map((p) => DutyPost.fromJson(Map<String, dynamic>.from(p)))
                  .toList(),
            ),
          ),
        };
      } else {
        return {
          "success": false,
          "error": data["detail"] ?? "Failed to fetch duty status",
        };
      }
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  // Fetches every stored schedule, used by Schedule Management.
  static Future<Map<String, dynamic>> fetchSchedules() async {
    try {
      final response = await http
          .get(Uri.parse("$baseUrl/schedules"))
          .timeout(const Duration(seconds: 30));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final List<dynamic> raw = data["schedules"] ?? [];
        return {
          "success": true,
          "schedules": raw
              .map((s) => Schedule.fromJson(Map<String, dynamic>.from(s)))
              .toList(),
        };
      } else {
        return {
          "success": false,
          "error": data["detail"] ?? "Failed to fetch schedules",
        };
      }
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  // Marks one schedule as published.
  static Future<Map<String, dynamic>> publishSchedule(String id) async {
    try {
      final response = await http
          .post(Uri.parse("$baseUrl/schedules/$id/publish"))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return {"success": true};
      }
      final data = jsonDecode(response.body);
      return {
        "success": false,
        "error": data["detail"] ?? "Failed to publish schedule",
      };
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  // Renames one guard's post across a schedule (their own entries plus
  // any entry covering their day-offs). Used to clear the Undefined
  // placeholders that block publishing.
  static Future<Map<String, dynamic>> updateSchedulePost({
    required String scheduleId,
    required String employeeId,
    required String post,
  }) async {
    try {
      final response = await http
          .put(
            Uri.parse("$baseUrl/schedules/$scheduleId/posts"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"employeeId": employeeId, "post": post}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return {"success": true};
      }
      final data = jsonDecode(response.body);
      return {
        "success": false,
        "error": data["detail"] ?? "Failed to update post",
      };
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  // Saves one roster row from Schedule Detail's Edit Assignment dialog:
  // who holds the post, the post itself, the duty window, the day-offs
  // and who relieves them on those days.
  //
  // Every field is the row's desired END STATE — omitting one keeps what
  // the row already has, but `relieverId: null` means "nobody relieves
  // this guard". The server re-checks the role rules (a Head Guard post
  // only ever goes to a head guard, a shift post only to a regular, and
  // only a reliever — or a substitute head guard on an HG row — covers a
  // day-off) and refuses anyone already booked in the same period, here
  // or at another station.
  static Future<Map<String, dynamic>> updateScheduleAssignment({
    required String scheduleId,
    required String employeeId,
    String? newEmployeeId,
    String? post,
    String? timeIn,
    String? timeOut,
    List<String>? offDates,
    String? relieverId,
  }) async {
    try {
      final response = await http
          .put(
            Uri.parse("$baseUrl/schedules/$scheduleId/assignment"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "employeeId": employeeId,
              "newEmployeeId": newEmployeeId,
              "post": post,
              "timeIn": timeIn,
              "timeOut": timeOut,
              "offDates": offDates,
              "relieverId": relieverId,
            }),
          )
          .timeout(const Duration(seconds: 20));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(data);
      }
      return {
        "success": false,
        "error": data["detail"] ?? "Failed to update the assignment",
      };
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  // Manually rosters one guard onto an unpublished schedule — the gap
  // filler for stations the generator left short. The guard gets a duty
  // entry on every day of the period except [offDates] (ISO yyyy-MM-dd).
  // The server rejects published schedules, double-bookings across
  // stations, and shifts the guard's role can't work.
  static Future<Map<String, dynamic>> addScheduleEmployee({
    required String scheduleId,
    required String employeeId,
    required String shift,
    required String post,
    List<String> offDates = const [],
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse("$baseUrl/schedules/$scheduleId/employees"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "employeeId": employeeId,
              "shift": shift,
              "post": post,
              "offDates": offDates,
            }),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(data);
      }
      return {
        "success": false,
        "error": data["detail"] ?? "Failed to add employee to schedule",
      };
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  // Reverts one schedule back to unpublished.
  static Future<Map<String, dynamic>> unpublishSchedule(String id) async {
    try {
      final response = await http
          .post(Uri.parse("$baseUrl/schedules/$id/unpublish"))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return {"success": true};
      }
      final data = jsonDecode(response.body);
      return {
        "success": false,
        "error": data["detail"] ?? "Failed to unpublish schedule",
      };
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  // Deletes one schedule permanently. Passes through `notified` — how
  // many guards were alerted that their schedule was withdrawn (0 for
  // an unpublished draft).
  static Future<Map<String, dynamic>> deleteSchedule(String id) async {
    try {
      final response = await http
          .delete(Uri.parse("$baseUrl/schedules/$id"))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      }
      final data = jsonDecode(response.body);
      return {
        "success": false,
        "error": data["detail"] ?? "Failed to delete schedule",
      };
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  // Bulk-deletes schedules. [scope] is one of 'unpublished', 'published'
  // or 'all'. Returns how many documents were removed.
  static Future<Map<String, dynamic>> deleteSchedules(String scope) async {
    try {
      final response = await http
          .delete(Uri.parse("$baseUrl/schedules?status=$scope"))
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      }
      final data = jsonDecode(response.body);
      return {
        "success": false,
        "error": data["detail"] ?? "Failed to delete schedules",
      };
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  // Marks every unpublished schedule as published.
  static Future<Map<String, dynamic>> publishAllSchedules() async {
    try {
      final response = await http
          .post(Uri.parse("$baseUrl/schedules/publish-all"))
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        // Passes through published/skippedUndefined so the caller can
        // tell the admin which stations were held back.
        return Map<String, dynamic>.from(jsonDecode(response.body));
      }
      final data = jsonDecode(response.body);
      return {
        "success": false,
        "error": data["detail"] ?? "Failed to publish schedules",
      };
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  // --- Attendance Reports (Phase 3: absence handling) ---

  // Submits the Head Guard's attendance report. The backend stores it
  // under a deterministic ID (date + head guard), so resubmitting the
  // same day's report overwrites it instead of duplicating.
  static Future<Map<String, dynamic>> submitAttendanceReport({
    required String headGuardId,
    required String headGuardName,
    required String station,
    required String shiftTitle,
    required String date,
    required List<AttendanceRecord> records,
  }) async {
    try {
      final response = await http
          .post(
        Uri.parse("$baseUrl/attendance-reports"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "headGuardId": headGuardId,
          "headGuardName": headGuardName,
          "station": station,
          "shiftTitle": shiftTitle,
          "date": date,
          "records": records.map((r) => r.toJson()).toList(),
        }),
      )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          "success": true,
          "report": AttendanceReport.fromJson(
              Map<String, dynamic>.from(data["report"])),
        };
      } else {
        return {
          "success": false,
          "error": data["detail"] ?? "Failed to submit report",
        };
      }
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  // Fetches every submitted attendance report, newest first — used by
  // the admin Notifications, Submitted Reports, Dashboard (Absent
  // Today) and Absent Management screens.
  static Future<Map<String, dynamic>> fetchAttendanceReports() async {
    try {
      final response = await http
          .get(Uri.parse("$baseUrl/attendance-reports"))
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final List<dynamic> raw = data["reports"] ?? [];
        return {
          "success": true,
          "reports": raw
              .map((r) =>
                  AttendanceReport.fromJson(Map<String, dynamic>.from(r)))
              .toList(),
        };
      } else {
        return {
          "success": false,
          "error": data["detail"] ?? "Failed to fetch reports",
        };
      }
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  // Marks one report's notification as read.
  static Future<Map<String, dynamic>> markReportRead(String id) async {
    try {
      final response = await http
          .post(Uri.parse("$baseUrl/attendance-reports/$id/read"))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return {"success": true};
      }
      final data = jsonDecode(response.body);
      return {
        "success": false,
        "error": data["detail"] ?? "Failed to mark report read",
      };
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  // Marks every unread report as read ("Mark all as read").
  static Future<Map<String, dynamic>> markAllReportsRead() async {
    try {
      final response = await http
          .post(Uri.parse("$baseUrl/attendance-reports/read-all"))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return {"success": true};
      }
      final data = jsonDecode(response.body);
      return {
        "success": false,
        "error": data["detail"] ?? "Failed to mark reports read",
      };
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  // --- Replacements (Phase 3: absence handling) ---

  // Fetches every admin-applied replacement (audit records), used by
  // the Schedule Report's Absence & Substitution Log.
  static Future<Map<String, dynamic>> fetchReplacements() async {
    try {
      final response = await http
          .get(Uri.parse("$baseUrl/replacements"))
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final List<dynamic> raw = data["replacements"] ?? [];
        return {
          "success": true,
          "replacements": raw
              .map((r) =>
                  AppliedReplacement.fromJson(Map<String, dynamic>.from(r)))
              .toList(),
        };
      } else {
        return {
          "success": false,
          "error": data["detail"] ?? "Failed to fetch replacements",
        };
      }
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  // Asks Python for ranked replacement candidates for one absence.
  // The backend already filters out anyone with a schedule conflict on
  // that date and anyone ineligible for the post's shift type.
  static Future<Map<String, dynamic>> suggestReplacements({
    required String date,
    required String station,
    required String shift,
    required String absentEmployeeId,
  }) async {
    try {
      final uri = Uri.parse("$baseUrl/replacements/suggest").replace(
        queryParameters: {
          "date": date,
          "station": station,
          "shift": shift,
          "absentEmployeeId": absentEmployeeId,
        },
      );
      final response =
          await http.get(uri).timeout(const Duration(seconds: 30));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final List<dynamic> raw = data["candidates"] ?? [];
        return {
          "success": true,
          "candidates": raw
              .map((c) => ReplacementCandidate.fromJson(
                  Map<String, dynamic>.from(c)))
              .toList(),
        };
      } else {
        return {
          "success": false,
          "error": data["detail"] ?? "Failed to suggest replacements",
        };
      }
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  // Commits the chosen replacement: the backend rewrites the schedule
  // entry, stamps the report record as replaced, and notifies the
  // chosen guard. 409 = the candidate picked up a conflict meanwhile.
  static Future<Map<String, dynamic>> applyReplacement({
    required String date,
    required String station,
    required String shift,
    required String absentEmployeeId,
    String? absentEmployeeName,
    required String replacementEmployeeId,
    String? reportId,
    String? absenceRequestId,
  }) async {
    try {
      final response = await http
          .post(
        Uri.parse("$baseUrl/replacements/apply"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "date": date,
          "station": station,
          "shift": shift,
          "absentEmployeeId": absentEmployeeId,
          "absentEmployeeName": absentEmployeeName,
          "replacementEmployeeId": replacementEmployeeId,
          "reportId": reportId,
          "absenceRequestId": absenceRequestId,
        }),
      )
          .timeout(const Duration(seconds: 30));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {"success": true, "replacement": data["replacement"]};
      } else {
        return {
          "success": false,
          "conflict": response.statusCode == 409,
          "error": data["detail"] ?? "Failed to apply replacement",
        };
      }
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  // --- Employee notifications (guard app Alerts tab) ---

  // Fetches this guard's notifications, newest first.
  static Future<Map<String, dynamic>> fetchEmployeeNotifications(
      String employeeId) async {
    try {
      final response = await http
          .get(Uri.parse("$baseUrl/employees/$employeeId/notifications"))
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final List<dynamic> raw = data["notifications"] ?? [];
        return {
          "success": true,
          "notifications": raw
              .map((n) => EmployeeNotification.fromJson(
                  Map<String, dynamic>.from(n)))
              .toList(),
        };
      } else {
        return {
          "success": false,
          "error": data["detail"] ?? "Failed to fetch notifications",
        };
      }
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  // Marks one employee notification as read.
  static Future<Map<String, dynamic>> markNotificationRead(String id) async {
    try {
      final response = await http
          .post(Uri.parse("$baseUrl/notifications/$id/read"))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return {"success": true};
      }
      final data = jsonDecode(response.body);
      return {
        "success": false,
        "error": data["detail"] ?? "Failed to mark notification read",
      };
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  // Marks every unread notification for this guard as read.
  static Future<Map<String, dynamic>> markAllNotificationsRead(
      String employeeId) async {
    try {
      final response = await http
          .post(Uri.parse(
              "$baseUrl/employees/$employeeId/notifications/read-all"))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return {"success": true};
      }
      final data = jsonDecode(response.body);
      return {
        "success": false,
        "error": data["detail"] ?? "Failed to mark notifications read",
      };
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  // Fetches every station from Firestore (via Python), used by the
  // Station Management screen.
  static Future<Map<String, dynamic>> fetchStations() async {
    try {
      final response = await http
          .get(Uri.parse("$baseUrl/stations"))
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final List<dynamic> raw = data["stations"] ?? [];
        return {
          "success": true,
          "stations": raw.map((s) => Station.fromJson(s)).toList(),
        };
      } else {
        return {
          "success": false,
          "error": data["detail"] ?? "Failed to fetch stations",
        };
      }
    } catch (e) {
      return {
        "success": false,
        "error": e.toString(),
      };
    }
  }

  // Fetches the admin pins for one rotation cycle (e.g. "202607") —
  // every station's at once, so Station Management can badge each card
  // and the dialog can warn when a guard is already pinned elsewhere.
  static Future<Map<String, dynamic>> fetchSpecialAssignments(
      String cycleId) async {
    try {
      final response = await http
          .get(Uri.parse("$baseUrl/special-assignments?cycleId=$cycleId"))
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final List<dynamic> raw = data["specialAssignments"] ?? [];
        return {
          "success": true,
          "specialAssignments":
              raw.map((s) => SpecialAssignment.fromJson(s)).toList(),
        };
      } else {
        return {
          "success": false,
          "error": data["detail"] ?? "Failed to fetch special assignments",
        };
      }
    } catch (e) {
      return {
        "success": false,
        "error": e.toString(),
      };
    }
  }

  // Replaces one station's pins for one cycle with the given list (the
  // dialog sends the complete list it wants to end up with, so the save
  // is idempotent). Returns the saved pins plus any notes — e.g. that a
  // guard was moved here off a pin at another station.
  static Future<Map<String, dynamic>> saveSpecialAssignments({
    required String stationId,
    required String cycleId,
    required List<SpecialAssignment> assignments,
  }) async {
    try {
      final response = await http
          .put(
            Uri.parse("$baseUrl/stations/$stationId/special-assignments"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "cycleId": cycleId,
              "assignments":
                  assignments.map((a) => a.toSaveJson()).toList(),
            }),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final List<dynamic> raw = data["specialAssignments"] ?? [];
        return {
          "success": true,
          "specialAssignments":
              raw.map((s) => SpecialAssignment.fromJson(s)).toList(),
          "notes": List<String>.from(data["notes"] ?? []),
        };
      } else {
        return {
          "success": false,
          "error": data["detail"] ?? "Failed to save special assignments",
        };
      }
    } catch (e) {
      return {
        "success": false,
        "error": e.toString(),
      };
    }
  }

  // --- Absence requests (emergency absence handling) ---

  // Files one guard's emergency absence request. A 409 comes back when
  // they already have a pending request for that same date — the detail
  // string is passed through so the form can show it verbatim.
  static Future<Map<String, dynamic>> submitAbsenceRequest({
    required String employeeId,
    required String employeeName,
    required String employeeType,
    required String station,
    required String shiftTitle,
    required String date,
    required String title,
    required String reason,
    required String body,
  }) async {
    try {
      final response = await http
          .post(
        Uri.parse("$baseUrl/absence-requests"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "employeeId": employeeId,
          "employeeName": employeeName,
          "employeeType": employeeType,
          "station": station,
          "shiftTitle": shiftTitle,
          "date": date,
          "title": title,
          "reason": reason,
          "body": body,
        }),
      )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          "success": true,
          "request": AbsenceRequest.fromJson(
              Map<String, dynamic>.from(data["request"])),
        };
      } else {
        return {
          "success": false,
          "error": data["detail"] ?? "Failed to submit absence request",
        };
      }
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  // Fetches every absence request, newest first — used by the admin
  // Notifications screen's Absence Requests tab.
  static Future<Map<String, dynamic>> fetchAbsenceRequests() async {
    try {
      final response = await http
          .get(Uri.parse("$baseUrl/absence-requests"))
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final List<dynamic> raw = data["requests"] ?? [];
        return {
          "success": true,
          "requests": raw
              .map((r) =>
                  AbsenceRequest.fromJson(Map<String, dynamic>.from(r)))
              .toList(),
        };
      } else {
        return {
          "success": false,
          "error": data["detail"] ?? "Failed to fetch absence requests",
        };
      }
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  // Fetches one guard's own absence requests, newest first, so the
  // guard app can show the status of what they already filed.
  static Future<Map<String, dynamic>> fetchEmployeeAbsenceRequests(
      String employeeId) async {
    try {
      final response = await http
          .get(Uri.parse("$baseUrl/employees/$employeeId/absence-requests"))
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final List<dynamic> raw = data["requests"] ?? [];
        return {
          "success": true,
          "requests": raw
              .map((r) =>
                  AbsenceRequest.fromJson(Map<String, dynamic>.from(r)))
              .toList(),
        };
      } else {
        return {
          "success": false,
          "error": data["detail"] ?? "Failed to fetch absence requests",
        };
      }
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  // Approves or denies one request. The backend also drops a
  // notification into the guard's Alerts inbox. 409 = someone already
  // decided it, so the detail string reaches the admin unchanged.
  static Future<Map<String, dynamic>> decideAbsenceRequest({
    required String id,
    required String status,
    String adminNote = '',
    String decidedBy = 'admin',
  }) async {
    try {
      final response = await http
          .post(
        Uri.parse("$baseUrl/absence-requests/$id/decision"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "status": status,
          "adminNote": adminNote,
          "decidedBy": decidedBy,
        }),
      )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          "success": true,
          "request": AbsenceRequest.fromJson(
              Map<String, dynamic>.from(data["request"])),
        };
      } else {
        return {
          "success": false,
          "error": data["detail"] ?? "Failed to save decision",
        };
      }
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  // Marks one absence request as opened by the admin.
  static Future<Map<String, dynamic>> markAbsenceRequestRead(String id) async {
    try {
      final response = await http
          .post(Uri.parse("$baseUrl/absence-requests/$id/read"))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return {"success": true};
      }
      final data = jsonDecode(response.body);
      return {
        "success": false,
        "error": data["detail"] ?? "Failed to mark request read",
      };
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  // --- Special day-off requests (filed ahead of the schedule) ---

  // The date-picker bounds the guard app needs before showing the form:
  // the earliest and latest selectable day, the days already scheduled
  // (which must be greyed out), and the dates this guard has already
  // requested. All strings are ISO YYYY-MM-DD.
  static Future<Map<String, dynamic>> fetchSpecialRequestWindow(
      String employeeId) async {
    try {
      final response = await http
          .get(Uri.parse(
              "$baseUrl/employees/$employeeId/special-request-window"))
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          "success": true,
          "minDate": data["minDate"]?.toString() ?? "",
          "maxDate": data["maxDate"]?.toString() ?? "",
          "maxDates": data["maxDates"] ?? 3,
          "blockedDates": ((data["blockedDates"] as List?) ?? [])
              .map((d) => d.toString())
              .toList(),
          "requestedDates": ((data["requestedDates"] as List?) ?? [])
              .map((d) => d.toString())
              .toList(),
        };
      }
      return {
        "success": false,
        "error": data["detail"] ?? "Failed to load the request window",
      };
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  // Files one special day-off request (1..3 dates sharing a title/reason).
  // A 409 comes back when a date is already scheduled or already requested;
  // the detail string is passed through so the form can show it verbatim.
  static Future<Map<String, dynamic>> submitSpecialRequest({
    required String employeeId,
    required String employeeName,
    required String employeeType,
    required String station,
    required List<String> dates,
    required String title,
    required String reason,
    required String body,
  }) async {
    try {
      final response = await http
          .post(
        Uri.parse("$baseUrl/special-requests"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "employeeId": employeeId,
          "employeeName": employeeName,
          "employeeType": employeeType,
          "station": station,
          "dates": dates,
          "title": title,
          "reason": reason,
          "body": body,
        }),
      )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          "success": true,
          "request": SpecialRequest.fromJson(
              Map<String, dynamic>.from(data["request"])),
        };
      } else {
        return {
          "success": false,
          "error": data["detail"] ?? "Failed to submit special request",
        };
      }
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  // Every special request, newest first — the admin Special Requests tab.
  static Future<Map<String, dynamic>> fetchSpecialRequests() async {
    try {
      final response = await http
          .get(Uri.parse("$baseUrl/special-requests"))
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final List<dynamic> raw = data["requests"] ?? [];
        return {
          "success": true,
          "requests": raw
              .map((r) =>
                  SpecialRequest.fromJson(Map<String, dynamic>.from(r)))
              .toList(),
        };
      } else {
        return {
          "success": false,
          "error": data["detail"] ?? "Failed to fetch special requests",
        };
      }
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  // One guard's own special requests, newest first, for the history list
  // shown under the filing form.
  static Future<Map<String, dynamic>> fetchEmployeeSpecialRequests(
      String employeeId) async {
    try {
      final response = await http
          .get(Uri.parse("$baseUrl/employees/$employeeId/special-requests"))
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final List<dynamic> raw = data["requests"] ?? [];
        return {
          "success": true,
          "requests": raw
              .map((r) =>
                  SpecialRequest.fromJson(Map<String, dynamic>.from(r)))
              .toList(),
        };
      } else {
        return {
          "success": false,
          "error": data["detail"] ?? "Failed to fetch special requests",
        };
      }
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  // Approves or denies one whole request. The backend also drops a
  // notification into the guard's Alerts inbox. 409 = someone already
  // decided it, so the detail string reaches the admin unchanged.
  static Future<Map<String, dynamic>> decideSpecialRequest({
    required String id,
    required String status,
    String adminNote = '',
    String decidedBy = 'admin',
  }) async {
    try {
      final response = await http
          .post(
        Uri.parse("$baseUrl/special-requests/$id/decision"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "status": status,
          "adminNote": adminNote,
          "decidedBy": decidedBy,
        }),
      )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          "success": true,
          "request": SpecialRequest.fromJson(
              Map<String, dynamic>.from(data["request"])),
        };
      } else {
        return {
          "success": false,
          "error": data["detail"] ?? "Failed to save decision",
        };
      }
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  // Marks one special request as opened by the admin.
  static Future<Map<String, dynamic>> markSpecialRequestRead(String id) async {
    try {
      final response = await http
          .post(Uri.parse("$baseUrl/special-requests/$id/read"))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return {"success": true};
      }
      final data = jsonDecode(response.body);
      return {
        "success": false,
        "error": data["detail"] ?? "Failed to mark request read",
      };
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  // --- Cover offers (guard volunteers to cover on a rest day) ---

  // Files (or updates) this guard's offer to cover a shift on the given
  // rest day, with the shift times and stations they'd prefer. A 409 comes
  // back when they're already on duty that day or already assigned to
  // cover it; the detail string is passed through for the form to show.
  static Future<Map<String, dynamic>> submitCoverOffer({
    required String employeeId,
    required String employeeName,
    required String employeeType,
    required String date,
    required List<String> preferredShifts,
    required List<String> preferredStations,
  }) async {
    try {
      final response = await http
          .post(
        Uri.parse("$baseUrl/cover-offers"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "employeeId": employeeId,
          "employeeName": employeeName,
          "employeeType": employeeType,
          "date": date,
          "preferredShifts": preferredShifts,
          "preferredStations": preferredStations,
        }),
      )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          "success": true,
          "offer":
              CoverOffer.fromJson(Map<String, dynamic>.from(data["offer"])),
        };
      } else {
        return {
          "success": false,
          "error": data["detail"] ?? "Failed to submit cover offer",
        };
      }
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  // This guard's own cover offers, newest date first — feeds the
  // availability card and the rest-day badges in the schedule.
  static Future<Map<String, dynamic>> fetchEmployeeCoverOffers(
      String employeeId) async {
    try {
      final response = await http
          .get(Uri.parse("$baseUrl/employees/$employeeId/cover-offers"))
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final List<dynamic> raw = data["offers"] ?? [];
        return {
          "success": true,
          "offers": raw
              .map((o) => CoverOffer.fromJson(Map<String, dynamic>.from(o)))
              .toList(),
        };
      } else {
        return {
          "success": false,
          "error": data["detail"] ?? "Failed to fetch cover offers",
        };
      }
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  // Every guard who volunteered to work on one date (defaults to today,
  // still-standing offers only) — the admin's Volunteer Employee tab.
  static Future<Map<String, dynamic>> fetchCoverOffersForDate(
    String date, {
    String status = 'active',
  }) async {
    try {
      final uri = Uri.parse("$baseUrl/cover-offers")
          .replace(queryParameters: {"date": date, "status": status});
      final response =
          await http.get(uri).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final List<dynamic> raw = data["offers"] ?? [];
        return {
          "success": true,
          "offers": raw
              .map((o) => CoverOffer.fromJson(Map<String, dynamic>.from(o)))
              .toList(),
        };
      } else {
        return {
          "success": false,
          "error": data["detail"] ?? "Failed to fetch cover offers",
        };
      }
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  // Withdraws an offer the guard no longer wants to stand by. A 409 comes
  // back if they've already been assigned to cover that day.
  static Future<Map<String, dynamic>> withdrawCoverOffer(String id) async {
    try {
      final response = await http
          .delete(Uri.parse("$baseUrl/cover-offers/$id"))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return {"success": true};
      }
      final data = jsonDecode(response.body);
      return {
        "success": false,
        "error": data["detail"] ?? "Failed to withdraw cover offer",
      };
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  // --- Employee leave ---

  // A leave refusal is richer than the other endpoints': when a rule
  // breaks, the backend sends `detail` as an object naming which rules
  // and whether a supervisor endorsement would let it through. This
  // keeps that structure intact instead of flattening it to a string,
  // so the admin form can offer the override for exactly those rules.
  static Map<String, dynamic> _leaveFailure(dynamic detail, String fallback) {
    if (detail is Map) {
      return {
        "success": false,
        "error": detail["message"]?.toString() ?? fallback,
        "blockers": ((detail["blockers"] as List?) ?? [])
            .map((b) => Map<String, dynamic>.from(b))
            .toList(),
        "requiresEndorsement": detail["requiresEndorsement"] == true,
        "cap": detail["cap"],
        "days": detail["days"],
      };
    }
    return {"success": false, "error": detail?.toString() ?? fallback};
  }

  // The leave catalogue and each type's day cap. Fetched rather than
  // hardcoded so the caps live only in backend_python/leave.py.
  static Future<Map<String, dynamic>> fetchLeaveTypes() async {
    try {
      final response = await http
          .get(Uri.parse("$baseUrl/leave-types"))
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final List<dynamic> raw = data["leaveTypes"] ?? [];
        return {
          "success": true,
          "leaveTypes": raw
              .map((t) => LeaveType.fromJson(Map<String, dynamic>.from(t)))
              .toList(),
          "defaultLeaveType": data["defaultLeaveType"] ?? '',
          "minLeadDays": data["minLeadDays"] ?? 7,
          "leavesPerYear": data["leavesPerYear"] ?? 2,
          "cooldownMonths": data["cooldownMonths"] ?? 6,
        };
      }
      return _leaveFailure(data["detail"], "Failed to fetch leave types");
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  // Everything the guard app's leave form needs before anything is typed:
  // whether this employee may file (and why not), the earliest day they
  // could start, the days already rostered, quota and cooldown.
  static Future<Map<String, dynamic>> fetchLeaveWindow(
      String employeeId) async {
    try {
      final response = await http
          .get(Uri.parse("$baseUrl/employees/$employeeId/leave-window"))
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          "success": true,
          "canFile": data["canFile"] == true,
          "reason": data["reason"] ?? '',
          "earliestStart": data["earliestStart"] ?? '',
          "maxDate": data["maxDate"] ?? '',
          "minLeadDays": data["minLeadDays"] ?? 7,
          "leaveTypes": ((data["leaveTypes"] as List?) ?? [])
              .map((t) => LeaveType.fromJson(Map<String, dynamic>.from(t)))
              .toList(),
          "defaultLeaveType": data["defaultLeaveType"] ?? '',
          "quota": Map<String, dynamic>.from(data["quota"] ?? {}),
          "cooldown": Map<String, dynamic>.from(data["cooldown"] ?? {}),
          "blockedDates": ((data["blockedDates"] as List?) ?? [])
              .map((d) => d.toString())
              .toList(),
          "pendingRequestId": data["pendingRequestId"],
          "activeLeave": data["activeLeave"] == null
              ? null
              : LeaveRequest.fromJson(
                  Map<String, dynamic>.from(data["activeLeave"])),
        };
      }
      return _leaveFailure(data["detail"], "Failed to build leave window");
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  // Files one leave request from the guard app. Every rule is enforced on
  // the backend, so a refusal here is the message to show the employee.
  static Future<Map<String, dynamic>> submitLeaveRequest({
    required String employeeId,
    required String employeeName,
    required String employeeType,
    required String station,
    required String leaveType,
    required String startDate,
    required String endDate,
    required String title,
    required String body,
  }) async {
    try {
      final response = await http
          .post(
        Uri.parse("$baseUrl/leave-requests"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "employeeId": employeeId,
          "employeeName": employeeName,
          "employeeType": employeeType,
          "station": station,
          "leaveType": leaveType,
          "startDate": startDate,
          "endDate": endDate,
          "title": title,
          "body": body,
        }),
      )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          "success": true,
          "request": LeaveRequest.fromJson(
              Map<String, dynamic>.from(data["request"])),
        };
      }
      return _leaveFailure(data["detail"], "Failed to file leave request");
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  // Every leave record, newest first — the admin's Leave Requests tab and
  // the Leave Report both read this.
  static Future<Map<String, dynamic>> fetchLeaveRequests() async {
    try {
      final response = await http
          .get(Uri.parse("$baseUrl/leave-requests"))
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final List<dynamic> raw = data["requests"] ?? [];
        return {
          "success": true,
          "requests": raw
              .map((r) => LeaveRequest.fromJson(Map<String, dynamic>.from(r)))
              .toList(),
        };
      }
      return _leaveFailure(data["detail"], "Failed to fetch leave requests");
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  // One employee's leave history, newest first.
  static Future<Map<String, dynamic>> fetchEmployeeLeaveRequests(
      String employeeId) async {
    try {
      final response = await http
          .get(Uri.parse("$baseUrl/employees/$employeeId/leave-requests"))
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final List<dynamic> raw = data["requests"] ?? [];
        return {
          "success": true,
          "requests": raw
              .map((r) => LeaveRequest.fromJson(Map<String, dynamic>.from(r)))
              .toList(),
        };
      }
      return _leaveFailure(data["detail"], "Failed to fetch leave requests");
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  // {employeeId: leave} for every approved leave covering the given day
  // (today by default) — how the employee list shows "On Leave".
  static Future<Map<String, dynamic>> fetchActiveLeaves({String? date}) async {
    try {
      final query = date == null ? '' : '?date=$date';
      final response = await http
          .get(Uri.parse("$baseUrl/leaves/active$query"))
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final raw = Map<String, dynamic>.from(data["leaves"] ?? {});
        return {
          "success": true,
          "leaves": raw.map((id, r) => MapEntry(
              id, LeaveRequest.fromJson(Map<String, dynamic>.from(r)))),
        };
      }
      return _leaveFailure(data["detail"], "Failed to fetch active leaves");
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  // What approving this leave costs the roster — the duties it swallows
  // and how thin it leaves the employee's shift. Read by the approval
  // dialog so nobody approves a 15-day leave blind.
  static Future<Map<String, dynamic>> fetchLeaveImpact(String id) async {
    try {
      final response = await http
          .get(Uri.parse("$baseUrl/leave-requests/$id/impact"))
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final impact = Map<String, dynamic>.from(data["impact"] ?? {});
        return {
          "success": true,
          "peerCount": (impact["peerCount"] as num?)?.toInt() ?? 0,
          "station": impact["station"] ?? '',
          "shift": impact["shift"],
          "days": (impact["days"] as num?)?.toInt() ?? 0,
          "leavesShiftBare": impact["leavesShiftBare"] == true,
          "publishedDutyCount":
              (impact["publishedDutyCount"] as num?)?.toInt() ?? 0,
          "affectedDuties": ((impact["affectedDuties"] as List?) ?? [])
              .map((d) =>
                  LeaveAffectedDuty.fromJson(Map<String, dynamic>.from(d)))
              .toList(),
          "cap": (data["cap"] as num?)?.toInt() ?? 0,
          "overCap": data["overCap"] == true,
        };
      }
      return _leaveFailure(data["detail"], "Failed to build leave impact");
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  // Approves or denies one leave request. Approving a leave that runs
  // past its type's cap is refused unless the endorsing supervisor is
  // named — the backend decides that, not this method.
  static Future<Map<String, dynamic>> decideLeaveRequest({
    required String id,
    required String status,
    String adminNote = '',
    String decidedBy = 'admin',
    String supervisorName = '',
    bool supervisorConfirmed = false,
  }) async {
    try {
      final response = await http
          .post(
        Uri.parse("$baseUrl/leave-requests/$id/decision"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "status": status,
          "adminNote": adminNote,
          "decidedBy": decidedBy,
          "supervisorName": supervisorName,
          "supervisorConfirmed": supervisorConfirmed,
        }),
      )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          "success": true,
          "request": LeaveRequest.fromJson(
              Map<String, dynamic>.from(data["request"])),
        };
      }
      return _leaveFailure(data["detail"], "Failed to save decision");
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  // Marks one leave request as opened by the admin.
  static Future<Map<String, dynamic>> markLeaveRequestRead(String id) async {
    try {
      final response = await http
          .post(Uri.parse("$baseUrl/leave-requests/$id/read"))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return {"success": true};
      }
      final data = jsonDecode(response.body);
      return _leaveFailure(data["detail"], "Failed to mark request read");
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  // The guard withdrawing their own request before it is decided. A 409
  // comes back once it has been approved or denied.
  static Future<Map<String, dynamic>> withdrawLeaveRequest(String id) async {
    try {
      final response = await http
          .delete(Uri.parse("$baseUrl/leave-requests/$id"))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return {"success": true};
      }
      final data = jsonDecode(response.body);
      return _leaveFailure(data["detail"], "Failed to withdraw leave request");
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  // The admin cancelling an approved leave — the employee comes off
  // "On Leave" and the days go back to the roster. Kept as a cancelled
  // record so the report still shows it happened.
  static Future<Map<String, dynamic>> cancelLeave({
    required String id,
    String cancelledBy = 'admin',
    String reason = '',
  }) async {
    try {
      final response = await http
          .post(
        Uri.parse("$baseUrl/leave-requests/$id/cancel"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"cancelledBy": cancelledBy, "reason": reason}),
      )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          "success": true,
          "request": LeaveRequest.fromJson(
              Map<String, dynamic>.from(data["request"])),
        };
      }
      return _leaveFailure(data["detail"], "Failed to cancel leave");
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  // The admin's "Set On Leave" form. Saved as approved on the spot.
  // Submitting without `overrideRules` first is deliberate: a leave that
  // breaks a rule comes back 409 with the blockers, and only a second
  // submit naming the endorsing supervisor may proceed past them.
  static Future<Map<String, dynamic>> setEmployeeOnLeave({
    required String employeeId,
    required String leaveType,
    required String startDate,
    required String endDate,
    required String title,
    required String body,
    String createdBy = 'admin',
    String adminNote = '',
    bool overrideRules = false,
    String supervisorName = '',
    bool supervisorConfirmed = false,
  }) async {
    try {
      final response = await http
          .post(
        Uri.parse("$baseUrl/employees/$employeeId/leave"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "leaveType": leaveType,
          "startDate": startDate,
          "endDate": endDate,
          "title": title,
          "body": body,
          "createdBy": createdBy,
          "adminNote": adminNote,
          "overrideRules": overrideRules,
          "supervisorName": supervisorName,
          "supervisorConfirmed": supervisorConfirmed,
        }),
      )
          .timeout(const Duration(seconds: 20));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final impact = Map<String, dynamic>.from(data["impact"] ?? {});
        return {
          "success": true,
          "request": LeaveRequest.fromJson(
              Map<String, dynamic>.from(data["request"])),
          "affectedDuties": ((impact["affectedDuties"] as List?) ?? [])
              .map((d) =>
                  LeaveAffectedDuty.fromJson(Map<String, dynamic>.from(d)))
              .toList(),
          "peerCount": (impact["peerCount"] as num?)?.toInt() ?? 0,
        };
      }
      return _leaveFailure(data["detail"], "Failed to save leave");
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }
}
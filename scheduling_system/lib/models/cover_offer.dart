// models/cover_offer.dart
//
// A guard's offer to cover a shift on one of their rest days. Filed from
// the guard app (dashboard card / clickable rest day) when someone who is
// off wants to be considered for a sudden duty. The offer names the shift
// times and stations they'd prefer; the backend boosts them to the top of
// the replacement suggestions for that date. Mirrors the JSON stored in
// the Python backend's `cover_offers` collection.

class CoverOffer {
  final String id;
  final String employeeId;
  final String employeeName;
  final String employeeType; // 'regular' | 'reliever' | 'headGuard'
  final String date; // ISO rest-day date the offer is for, YYYY-MM-DD

  // Shift labels the guard is willing to work, in the schedule's own
  // vocabulary ('Morning'|'Afternoon'|'Night' or 'HG Day'|'HG Night').
  final List<String> preferredShifts;
  // Station names the guard wants to be deployed to.
  final List<String> preferredStations;

  // 'active' while it stands, 'fulfilled' once the admin assigned this
  // guard to cover. Withdrawn offers are deleted, so never appear here.
  final String status;

  // Set on the record once fulfilled — where/what they were assigned to.
  final String? fulfilledStation;
  final String? fulfilledShift;

  const CoverOffer({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.employeeType,
    required this.date,
    required this.preferredShifts,
    required this.preferredStations,
    required this.status,
    this.fulfilledStation,
    this.fulfilledShift,
  });

  bool get isActive => status == 'active';
  bool get isFulfilled => status == 'fulfilled';

  factory CoverOffer.fromJson(Map<String, dynamic> json) {
    return CoverOffer(
      id: json['id'] ?? '',
      employeeId: json['employeeId'] ?? '',
      employeeName: json['employeeName'] ?? '',
      employeeType: json['employeeType'] ?? 'regular',
      date: json['date'] ?? '',
      preferredShifts: json['preferredShifts'] != null
          ? List<String>.from(json['preferredShifts'])
          : const [],
      preferredStations: json['preferredStations'] != null
          ? List<String>.from(json['preferredStations'])
          : const [],
      status: json['status'] ?? 'active',
      fulfilledStation: json['fulfilledStation'],
      fulfilledShift: json['fulfilledShift'],
    );
  }
}

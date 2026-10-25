class ChangesReviewAddress {
  const ChangesReviewAddress(this.sessionId, this.seq, this.turn);
  final String sessionId;
  final num seq;
  final int turn;
  static const prefix = 'dsh-resource://changes-review/session/';
  String get address =>
      '$prefix${Uri.encodeComponent(sessionId)}/${seq == seq.truncate() ? seq.truncate() : seq}/$turn';
  static ChangesReviewAddress? parse(String value) {
    if (!value.startsWith(prefix)) return null;
    final parts = value.substring(prefix.length).split('/');
    if (parts.length != 3 ||
        parts[0].isEmpty ||
        !RegExp(r'^\d+$').hasMatch(parts[1]) ||
        !RegExp(r'^[1-9]\d*$').hasMatch(parts[2])) {
      return null;
    }
    try {
      return ChangesReviewAddress(
        Uri.decodeComponent(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      );
    } on ArgumentError {
      return null;
    } on FormatException {
      return null;
    }
  }
}

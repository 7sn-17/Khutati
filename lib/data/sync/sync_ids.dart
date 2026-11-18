import 'dart:math';

/// Small, dependency-free identity helpers for the cloud outbox.
abstract final class SyncIds {
  static final Random _random = Random.secure();

  /// RFC-4122-shaped v4 identifier. It only needs to be unique across the
  /// user's devices, not cryptographically verifiable.
  static String newId() {
    final List<int> bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final String hex = bytes
        .map((int value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}

/// Stable JSON-friendly representation used by both the outbox and Supabase.
String? isoOrNull(DateTime? value) => value?.toUtc().toIso8601String();

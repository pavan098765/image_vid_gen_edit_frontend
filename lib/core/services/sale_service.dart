import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class SaleState {
  final bool isActive;
  final int discountPercent;
  final DateTime? windowEnd;
  final DateTime? nextWindowStart;
  final int? nextDiscountPercent;

  const SaleState({
    this.isActive = false,
    this.discountPercent = 0,
    this.windowEnd,
    this.nextWindowStart,
    this.nextDiscountPercent,
  });

  Duration get timeRemaining {
    if (!isActive || windowEnd == null) return Duration.zero;
    final diff = windowEnd!.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  Duration get timeUntilNext {
    if (isActive || nextWindowStart == null) return Duration.zero;
    final diff = nextWindowStart!.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  int applyDiscount(int baseCost) {
    if (!isActive || discountPercent <= 0) return baseCost;
    return (baseCost * (1 - discountPercent / 100)).round();
  }
}

/// Lets the 1s countdown tick listeners without changing [value] (same as banner/timer UI).
class SaleStateNotifier extends ValueNotifier<SaleState> {
  SaleStateNotifier() : super(const SaleState());

  void notifyTick() => notifyListeners();
}

class SaleService {
  static final SaleService _instance = SaleService._();
  factory SaleService() => _instance;
  SaleService._();

  static const String _baseUrl = 'https://genedit.mooo.com';

  static const Duration _minPoll = Duration(seconds: 10);
  static const Duration _maxPoll = Duration(minutes: 5);

  final SaleStateNotifier state = SaleStateNotifier();

  Timer? _pollTimer;
  Timer? _countdownTimer;
  bool _started = false;

  /// Echo server `ETag` header value for `If-None-Match` (may include quotes).
  String? _lastEtag;

  int _consecutiveFetchErrors = 0;

  void start() {
    if (_started) return;
    _started = true;
    _startCountdown();
    _fetch();
  }

  void dispose() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _started = false;
    _lastEtag = null;
    _consecutiveFetchErrors = 0;
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final s = state.value;
      if (s.isActive && s.windowEnd != null) {
        if (s.windowEnd!.isBefore(DateTime.now())) {
          _fetch();
        } else {
          state.notifyTick();
        }
      } else if (!s.isActive && s.nextWindowStart != null) {
        if (s.nextWindowStart!.isBefore(DateTime.now())) {
          _fetch();
        } else {
          state.notifyTick();
        }
      }
    });
  }

  void _scheduleNextPoll([Duration? override]) {
    _pollTimer?.cancel();
    final raw = override ?? _computeAdaptivePollDelay(state.value);
    final delay = _clampPollDuration(raw);
    _pollTimer = Timer(delay, _fetch);
  }

  Duration _clampPollDuration(Duration d) {
    if (d < _minPoll) return _minPoll;
    if (d > _maxPoll) return _maxPoll;
    return d;
  }

  /// Next poll delay from current sale state (wall clock).
  Duration _computeAdaptivePollDelay(SaleState s) {
    final now = DateTime.now();
    DateTime? boundary;
    if (s.isActive && s.windowEnd != null) {
      boundary = s.windowEnd;
    } else if (!s.isActive && s.nextWindowStart != null) {
      boundary = s.nextWindowStart;
    }
    if (boundary == null) {
      return const Duration(minutes: 5);
    }
    final until = boundary.difference(now);
    if (until <= Duration.zero) {
      return const Duration(seconds: 10);
    }
    if (until < const Duration(seconds: 90)) {
      return const Duration(seconds: 18);
    }
    if (until < const Duration(minutes: 5)) {
      return const Duration(seconds: 50);
    }
    if (until < const Duration(minutes: 30)) {
      return const Duration(minutes: 2);
    }
    return const Duration(minutes: 5);
  }

  Duration _errorBackoffDelay() {
    final step = math.min(math.max(0, _consecutiveFetchErrors - 1), 2);
    final seconds = math.min(30 * (1 << step), 120);
    return Duration(seconds: seconds);
  }

  Future<void> _fetch() async {
    try {
      final headers = <String, String>{
        'Accept': 'application/json',
      };
      if (_lastEtag != null && _lastEtag!.isNotEmpty) {
        headers['If-None-Match'] = _lastEtag!;
      }

      final resp = await http
          .get(
            Uri.parse('$_baseUrl/sales/active'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode == 304) {
        _consecutiveFetchErrors = 0;
        _scheduleNextPoll();
        return;
      }

      if (resp.statusCode != 200) {
        _consecutiveFetchErrors++;
        debugPrint(
          '[SaleService] fetch HTTP ${resp.statusCode}',
        );
        _scheduleNextPoll(_errorBackoffDelay());
        return;
      }

      final etag = resp.headers['etag'];
      if (etag != null && etag.isNotEmpty) {
        _lastEtag = etag;
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;

      final isActive = data['is_active'] == true;
      final discountPercent = (data['discount_percent'] as num?)?.toInt() ?? 0;

      DateTime? windowEnd;
      if (isActive && data['window_end'] != null) {
        windowEnd = _parseDateTime(data['window_end'] as String);
      }

      DateTime? nextStart;
      int? nextDiscount;
      final nextWindow = data['next_window'] as Map<String, dynamic>?;
      if (nextWindow != null) {
        if (nextWindow['start_utc'] != null) {
          nextStart = DateTime.tryParse(nextWindow['start_utc'] as String);
        }
        nextDiscount = (nextWindow['discount_percent'] as num?)?.toInt();
      }

      state.value = SaleState(
        isActive: isActive,
        discountPercent: discountPercent,
        windowEnd: windowEnd,
        nextWindowStart: nextStart,
        nextDiscountPercent: nextDiscount,
      );

      _consecutiveFetchErrors = 0;
      _scheduleNextPoll();
    } catch (e) {
      debugPrint('[SaleService] fetch error: $e');
      _consecutiveFetchErrors++;
      _scheduleNextPoll(_errorBackoffDelay());
    }
  }

  DateTime? _parseDateTime(String s) {
    return DateTime.tryParse(s);
  }
}

import '../models/race_metrics.dart';

class PhysicsEngine {
  static const double gAcceleration = 9.80665; // m/s^2

  static const double distance60ft = 18.288;
  static const double distance330ft = 100.584;
  static const double distance18Mile = 201.168;
  static const double distance1000ft = 304.8;
  static const double distance14Mile = 402.336;
  static const double distance12Mile = 804.672;

  static const double launchCommitThreshold =
      3.0; // km/h needed to confirm a real launch (ignores GPS wandering)
  static const double zeroCrossingThreshold =
      0.5; // km/h threshold for interpolating exact start

  /// Raise the standing-start commit when speed accuracy (sAcc) is poor.
  /// [sAccMps] in m/s; unknown (null/≤0) keeps the base 3 km/h gate.
  static double launchCommitThresholdForSAcc(double? sAccMps) {
    if (sAccMps == null || sAccMps <= 0) return launchCommitThreshold;
    final noiseKmh = sAccMps * 3.6 * 2.5;
    return noiseKmh > launchCommitThreshold ? noiseKmh : launchCommitThreshold;
  }

  final List<DataPoint> _preRunBuffer = [];
  /// High-rate longitudinal G samples stamped with latest GPS iTOW (when known).
  final List<_ImuGSample> _imuGBuffer = [];
  int _stoppedTicks = 0;
  int _rejectedCount = 0;
  int? _lastGpsTimeMs;
  double? _lastGpsTimeSeconds;
  double? _lastValidDt;

  static const double imuLaunchGThreshold = 0.18;
  static const double imuLaunchGQuiet = 0.10;
  /// Prefer IMU edge over GPS zero-cross only when it leads by at most this.
  static const double imuLeadMaxSeconds = 0.35;

  double get lastValidDt => _lastValidDt ?? 0.1;

  /// Feed calibrated longitudinal G (~20 Hz). Used to pull launch t0 earlier than GPS.
  void noteImuG(double gForce) {
    _imuGBuffer.add(_ImuGSample(gpsTimeMs: _lastGpsTimeMs, gForce: gForce));
    while (_imuGBuffer.length > 80) {
      _imuGBuffer.removeAt(0);
    }
  }

  /// GPS week–aware delta in milliseconds (iTOW).
  static int deltaGpsMs(int fromMs, int toMs) {
    var d = toMs - fromMs;
    if (d < 0) {
      d += 604800000;
    }
    return d;
  }

  static double deltaGpsSeconds(int fromMs, int toMs) =>
      deltaGpsMs(fromMs, toMs) / 1000.0;

  /// Interpolate GPS time (ms) where speed crosses [targetKmh] between two samples.
  static double interpolateGpsTimeMs({
    required int t0Ms,
    required double v0,
    required int t1Ms,
    required double v1,
    required double targetKmh,
  }) {
    if (v1 == v0) return t1Ms.toDouble();
    final frac = (targetKmh - v0) / (v1 - v0);
    return t0Ms + frac * deltaGpsMs(t0Ms, t1Ms);
  }

  RaceMetrics updateMetrics(
    RaceMetrics current,
    double newSpeedKmh,
    double currentAltitude, {
    required bool isArmed,
    required String runMode,
    required double? targetDistance,
    required String? targetDistanceUnit,
    required double? targetStartSpeed,
    required double? targetEndSpeed,
    required String? targetSpeedUnit,
    required double intervalStartSpeed,
    required double intervalEndSpeed,
    double? gpsTimeSeconds,
    int? gpsTimeMs,
    double? sAccMps,
    bool allowStandingLaunch = true,
  }) {
    // Calculate current dynamic dt — prefer GPS iTOW (ms) over UTC seconds.
    double currentDt = _lastValidDt ?? 0.1;
    if (gpsTimeMs != null && _lastGpsTimeMs != null) {
      var deltaMs = gpsTimeMs - _lastGpsTimeMs!;
      if (deltaMs < 0) {
        deltaMs += 604800000; // GPS week rollover
      }
      final delta = deltaMs / 1000.0;
      if (delta > 0.001 && delta < 2.0) {
        currentDt = delta;
        _lastValidDt = delta;
      }
    } else if (gpsTimeSeconds != null && _lastGpsTimeSeconds != null) {
      double delta = gpsTimeSeconds - _lastGpsTimeSeconds!;
      if (delta < 0) {
        delta += 86400.0; // handle midnight rollover (NMEA)
      }
      if (delta > 0.01 && delta < 2.0) {
        currentDt = delta;
        _lastValidDt = delta;
      }
    }
    _lastGpsTimeMs = gpsTimeMs;
    _lastGpsTimeSeconds = gpsTimeSeconds;

    // 0. Maintain Rolling Buffer (50 ticks) for 200ms G-Force latency shifting
    _preRunBuffer.add(DataPoint(
      elapsedTime: current.isRunning ? current.elapsedTime : 0.0,
      speedKmh: newSpeedKmh,
      gForce: current.gForce,
      altitude: currentAltitude,
      gpsTimeMs: gpsTimeMs,
    ));
    if (_preRunBuffer.length > 50) {
      _preRunBuffer.removeAt(0);
    }

    int delayTicks = 2; // 200ms at 10Hz
    double shiftedGForce = current.gForce;
    if (_preRunBuffer.length > delayTicks) {
      shiftedGForce = _preRunBuffer[_preRunBuffer.length - 1 - delayTicks].gForce;
    }

    // Smooth G-Force slightly
    double smoothedGForce = shiftedGForce;
    if (current.history.isNotEmpty) {
      smoothedGForce =
          (current.history.last.gForce * 0.7) + (shiftedGForce * 0.3);
    }

    // 0.5 Sensor-Fusion Outlier Rejection
    // Validate the GPS speed jump against the delayed IMU acceleration.
    double lastSpeed = current.isRunning
        ? current.speedKmh
        : (_preRunBuffer.length > 1 ? _preRunBuffer[_preRunBuffer.length - 2].speedKmh : 0.0);

    if (_preRunBuffer.isNotEmpty || current.isRunning) {
      double actualDeltaKmh = newSpeedKmh - lastSpeed;
      double expectedDeltaKmh = (shiftedGForce * gAcceleration * currentDt) * 3.6;
      double dynamicToleranceKmh = (1.0 * gAcceleration * currentDt) * 3.6;

      if (actualDeltaKmh > 0 &&
          (actualDeltaKmh - expectedDeltaKmh).abs() > dynamicToleranceKmh) {
        _rejectedCount++;
        if (_rejectedCount > 2) {
          // 200ms of sustained mismatch
          _rejectedCount = 0;
          if (!current.isRunning) {
            // Accept new reality (e.g., GPS reconnect) but do not clear buffer to maintain latency
          }
        } else {
          return current; // Ignore this likely GPS multipath glitch
        }
      } else {
        _rejectedCount = 0;
      }
    } else {
      _rejectedCount = 0;
    }

    // If not armed and not running, just return current with updated speed and altitude
    // without triggering or integrating, preserving completed run statistics
    if (!isArmed && !current.isRunning) {
      _stoppedTicks = 0;
      double displaySpeed = newSpeedKmh < 2.0 ? 0.0 : newSpeedKmh;
      return current.copyWith(
        speedKmh: displaySpeed,
        isRunning: false,
        distanceMeters: current.history.isNotEmpty ? current.distanceMeters : 0.0,
        elapsedTime: current.history.isNotEmpty ? current.elapsedTime : 0.0,
        startAltitude: current.history.isNotEmpty ? current.startAltitude : currentAltitude,
      );
    }

    if (!current.isRunning) {

      if (runMode == 'drag') {
        // Armed state
        if (newSpeedKmh == 0.0) {
          return current.copyWith(
            speedKmh: 0.0,
            distanceMeters: current.history.isNotEmpty ? current.distanceMeters : 0.0,
            elapsedTime: current.history.isNotEmpty ? current.elapsedTime : 0.0,
            gForce: current.gForce,
            startAltitude: current.history.isNotEmpty ? current.startAltitude : currentAltitude,
            runMode: 'drag',
            targetDistance: targetDistance,
            targetDistanceUnit: targetDistanceUnit,
            targetStartSpeed: targetStartSpeed,
            targetEndSpeed: targetEndSpeed,
            targetSpeedUnit: targetSpeedUnit,
          );
        }

        // 2. Launch Detection & Validation
        if (allowStandingLaunch) {
          final triggered = _tryTriggerStandingStart(
            current,
            newSpeedKmh,
            currentAltitude,
            runMode: 'drag',
            targetDistance: targetDistance,
            targetDistanceUnit: targetDistanceUnit,
            targetStartSpeed: targetStartSpeed,
            targetEndSpeed: targetEndSpeed,
            targetSpeedUnit: targetSpeedUnit,
            currentDt: currentDt,
            sAccMps: sAccMps,
          );
          if (triggered != null) {
            return triggered;
          }
        }

        // We are stopped or moving slowly (creeping/GPS wandering).
        double displaySpeed = newSpeedKmh < 2.0 ? 0.0 : newSpeedKmh;
        return current.copyWith(
          speedKmh: displaySpeed,
          distanceMeters: current.history.isNotEmpty ? current.distanceMeters : 0.0,
          elapsedTime: current.history.isNotEmpty ? current.elapsedTime : 0.0,
          gForce: current.gForce,
          startAltitude: current.history.isNotEmpty ? current.startAltitude : currentAltitude,
          runMode: 'drag',
          targetDistance: targetDistance,
          targetDistanceUnit: targetDistanceUnit,
          targetStartSpeed: targetStartSpeed,
          targetEndSpeed: targetEndSpeed,
          targetSpeedUnit: targetSpeedUnit,
        );
      } else {
        // Interval Mode
        if (intervalStartSpeed == 0.0) {
          if (allowStandingLaunch) {
            final triggered = _tryTriggerStandingStart(
              current,
              newSpeedKmh,
              currentAltitude,
              runMode: 'interval',
              targetDistance: targetDistance,
              targetDistanceUnit: targetDistanceUnit,
              targetStartSpeed: targetStartSpeed,
              targetEndSpeed: targetEndSpeed,
              targetSpeedUnit: targetSpeedUnit,
              currentDt: currentDt,
              sAccMps: sAccMps,
            );
            if (triggered != null) {
              return triggered;
            }
          }
        } else {
          if (_preRunBuffer.length >= 2) {
            double prevSpeed = _preRunBuffer[_preRunBuffer.length - 2].speedKmh;
            if (prevSpeed <= intervalStartSpeed && newSpeedKmh > intervalStartSpeed) {
              // Trigger! Exact start crossing — prefer iTOW between the two samples.
              final prevPoint = _preRunBuffer[_preRunBuffer.length - 2];
              final currPoint = _preRunBuffer[_preRunBuffer.length - 1];
              final speedDiff = newSpeedKmh - prevSpeed;
              final fraction = (intervalStartSpeed - prevSpeed) / speedDiff;

              final prevMs = prevPoint.gpsTimeMs;
              final currMs = currPoint.gpsTimeMs;
              final stepDt = (prevMs != null && currMs != null)
                  ? deltaGpsSeconds(prevMs, currMs)
                  : currentDt;
              final elapsedOffset = (1.0 - fraction) * stepDt;

              // Average speed during this fractional step (m/s)
              final avgSpeedMs =
                  ((intervalStartSpeed / 3.6) + (newSpeedKmh / 3.6)) / 2;
              final initialDistance = avgSpeedMs * elapsedOffset;

              final startGpsMs = (prevMs != null && currMs != null)
                  ? (prevMs + fraction * deltaGpsMs(prevMs, currMs)).round()
                  : null;

              RaceMetrics simulated = current.copyWith(
                isRunning: true,
                elapsedTime: elapsedOffset,
                distanceMeters: initialDistance,
                speedKmh: newSpeedKmh,
                gForce: smoothedGForce,
                startAltitude: currentAltitude,
                runMode: 'interval',
                targetDistance: targetDistance,
                targetDistanceUnit: targetDistanceUnit,
                targetStartSpeed: targetStartSpeed,
                targetEndSpeed: targetEndSpeed,
                targetSpeedUnit: targetSpeedUnit,
                history: [
                  DataPoint(
                    elapsedTime: 0.0,
                    speedKmh: intervalStartSpeed,
                    gForce: current.gForce,
                    altitude: currentAltitude,
                    gpsTimeMs: startGpsMs,
                  ),
                  DataPoint(
                    elapsedTime: elapsedOffset,
                    speedKmh: newSpeedKmh,
                    gForce: smoothedGForce,
                    altitude: currentAltitude,
                    gpsTimeMs: currMs,
                  ),
                ],
              );

              // Do not clear _preRunBuffer to maintain latency history
              return simulated;
            }
          }
        }

        double displaySpeed = newSpeedKmh < 2.0 ? 0.0 : newSpeedKmh;
        return current.copyWith(
          speedKmh: displaySpeed,
          distanceMeters: current.history.isNotEmpty ? current.distanceMeters : 0.0,
          elapsedTime: current.history.isNotEmpty ? current.elapsedTime : 0.0,
          gForce: current.gForce,
          startAltitude: current.history.isNotEmpty ? current.startAltitude : currentAltitude,
          runMode: 'interval',
          targetDistance: targetDistance,
          targetDistanceUnit: targetDistanceUnit,
          targetStartSpeed: targetStartSpeed,
          targetEndSpeed: targetEndSpeed,
          targetSpeedUnit: targetSpeedUnit,
        );
      }
    } else {
      // 4. Already running, just integrate normally
      if (runMode == 'drag') {
        // Auto-stop logic: if we are fully stopped for 2 seconds, finish/cancel the run
        if (newSpeedKmh < 3.0) {
          _stoppedTicks++;
          if (_stoppedTicks >= 20) {
            _stoppedTicks = 0;
            return current.copyWith(
              isRunning: false,
              speedKmh: 0.0,
              gForce: current.gForce,
            );
          }
        } else {
          _stoppedTicks = 0;
        }

        return _integrateDrag(
          current,
          newSpeedKmh,
          currentAltitude,
          currentDt,
          smoothedGForce,
          gpsTimeMs: gpsTimeMs,
        );
      } else {
        // Interval Mode
        // Auto-cancel logic: if speed drops below starting speed - 10 km/h for 2 seconds, cancel the run
        final double cancelThreshold = intervalStartSpeed == 0.0
            ? 3.0
            : (intervalStartSpeed - 10.0).clamp(0.0, 300.0);
        if (newSpeedKmh < cancelThreshold) {
          _stoppedTicks++;
          if (_stoppedTicks >= 20) {
            _stoppedTicks = 0;
            return current.copyWith(
              isRunning: false,
              speedKmh: newSpeedKmh,
              gForce: current.gForce,
            );
          }
        } else {
          _stoppedTicks = 0;
        }

        return _integrateInterval(
          current,
          newSpeedKmh,
          currentAltitude,
          smoothedGForce,
          intervalStartSpeed: intervalStartSpeed,
          intervalEndSpeed: intervalEndSpeed,
          currentDt: currentDt,
          gpsTimeMs: gpsTimeMs,
        );
      }
    }
  }

  RaceMetrics _integrateDrag(
    RaceMetrics current,
    double newSpeedKmh,
    double currentAltitude,
    double currentDt,
    double smoothedGForce, {
    int? gpsTimeMs,
  }) {
    final currentSpeedMs = current.speedKmh / 3.6;
    final newSpeedMs = newSpeedKmh / 3.6;

    // Trapezoidal integration for distance
    final avgSpeedMs = (currentSpeedMs + newSpeedMs) / 2;
    final double deltaDistance = avgSpeedMs * currentDt;
    final double newDistance = current.distanceMeters + deltaDistance;

    final newElapsedTime = current.elapsedTime + currentDt;

    final newHistory = List<DataPoint>.from(current.history)
      ..add(
        DataPoint(
          elapsedTime: newElapsedTime,
          speedKmh: newSpeedKmh,
          gForce: smoothedGForce,
          altitude: currentAltitude,
          gpsTimeMs: gpsTimeMs,
        ),
      );

    // Metrics triggers
    double? t60ft = current.time60ft;
    double? trap60 = current.trap60ft;
    double? t330ft = current.time330ft;
    double? trap330 = current.trap330ft;
    double? t0_50kmh = current.time0to50kmh;
    double? t0_60mph = current.time0to60mph;
    double? t0_100kmh = current.time0to100kmh;
    double? t18 = current.time18Mile;
    double? trap18 = current.trap18Mile;
    double? t1000ft = current.time1000ft;
    double? trap1000 = current.trap1000ft;
    double? t14 = current.time14Mile;
    double? trap14 = current.trap14Mile;
    double? t12 = current.time12Mile;
    double? trap12 = current.trap12Mile;

    // Rollout triggers
    double? rollout1ft = current.rolloutTime1ft;
    double? t60ftRollout = current.time60ftRollout;
    double? t330ftRollout = current.time330ftRollout;
    double? t0_50kmhRollout = current.time0to50kmhRollout;
    double? t0_60mphRollout = current.time0to60mphRollout;
    double? t0_100kmhRollout = current.time0to100kmhRollout;
    double? t18Rollout = current.time18MileRollout;
    double? t1000Rollout = current.time1000ftRollout;
    double? t14Rollout = current.time14MileRollout;
    double? t12Rollout = current.time12MileRollout;

    // Speed intervals
    double? t60_130 = current.time60to130mph;
    double? t100_200 = current.time100to200kmh;
    double? t0_130mph = current.time0to130mph;
    double? t0_200kmh = current.time0to200kmh;

    final double startAltitude = current.startAltitude ?? currentAltitude;

    // 1 ft (0.3048 meters) for rollout trigger point
    if (rollout1ft == null && newDistance >= 0.3048) {
      double distDiff = newDistance - current.distanceMeters;
      if (distDiff > 0) {
        double fraction = (0.3048 - current.distanceMeters) / distDiff;
        rollout1ft = current.elapsedTime + (currentDt * fraction);
      } else {
        rollout1ft = newElapsedTime;
      }
    }

    // 60 ft (18.288 meters)
    if (t60ft == null && newDistance >= distance60ft) {
      double distDiff = newDistance - current.distanceMeters;
      if (distDiff > 0) {
        double fraction = (distance60ft - current.distanceMeters) / distDiff;
        t60ft = current.elapsedTime + (currentDt * fraction);
        trap60 =
            current.speedKmh + ((newSpeedKmh - current.speedKmh) * fraction);
      } else {
        t60ft = newElapsedTime;
        trap60 = newSpeedKmh;
      }
    }

    // 60 ft Rollout (target: 60ft + 1ft = 18.288 + 0.3048 = 18.5928 meters)
    if (t60ftRollout == null && rollout1ft != null && newDistance >= (distance60ft + 0.3048)) {
      double distDiff = newDistance - current.distanceMeters;
      double absTime;
      if (distDiff > 0) {
        double fraction = ((distance60ft + 0.3048) - current.distanceMeters) / distDiff;
        absTime = current.elapsedTime + (currentDt * fraction);
      } else {
        absTime = newElapsedTime;
      }
      t60ftRollout = absTime - rollout1ft;
    }

    // 330 ft (100.584 meters)
    if (t330ft == null && newDistance >= distance330ft) {
      double distDiff = newDistance - current.distanceMeters;
      if (distDiff > 0) {
        double fraction = (distance330ft - current.distanceMeters) / distDiff;
        t330ft = current.elapsedTime + (currentDt * fraction);
        trap330 =
            current.speedKmh + ((newSpeedKmh - current.speedKmh) * fraction);
      } else {
        t330ft = newElapsedTime;
        trap330 = newSpeedKmh;
      }
    }

    // 330 ft Rollout (target: distance330ft + 0.3048)
    if (t330ftRollout == null && rollout1ft != null && newDistance >= (distance330ft + 0.3048)) {
      double distDiff = newDistance - current.distanceMeters;
      double absTime;
      if (distDiff > 0) {
        double fraction = ((distance330ft + 0.3048) - current.distanceMeters) / distDiff;
        absTime = current.elapsedTime + (currentDt * fraction);
      } else {
        absTime = newElapsedTime;
      }
      t330ftRollout = absTime - rollout1ft;
    }

    // 0-50 km/h
    if (t0_50kmh == null && newSpeedKmh >= 50.0) {
      double speedDiff = newSpeedKmh - current.speedKmh;
      if (speedDiff > 0) {
        double fraction = (50.0 - current.speedKmh) / speedDiff;
        t0_50kmh = current.elapsedTime + (currentDt * fraction);
      } else {
        t0_50kmh = newElapsedTime;
      }
    }

    // 0-50 km/h Rollout
    if (t0_50kmhRollout == null && t0_50kmh != null && rollout1ft != null) {
      t0_50kmhRollout = t0_50kmh - rollout1ft;
    }

    // 0-60 mph (96.5606 km/h)
    if (t0_60mph == null && newSpeedKmh >= 96.5606) {
      double speedDiff = newSpeedKmh - current.speedKmh;
      if (speedDiff > 0) {
        double fraction = (96.5606 - current.speedKmh) / speedDiff;
        t0_60mph = current.elapsedTime + (currentDt * fraction);
      } else {
        t0_60mph = newElapsedTime;
      }
    }

    // 0-60 mph Rollout
    if (t0_60mphRollout == null && t0_60mph != null && rollout1ft != null) {
      t0_60mphRollout = t0_60mph - rollout1ft;
    }

    // 0-100 km/h
    if (t0_100kmh == null && newSpeedKmh >= 100.0) {
      double speedDiff = newSpeedKmh - current.speedKmh;
      if (speedDiff > 0) {
        double fraction = (100.0 - current.speedKmh) / speedDiff;
        t0_100kmh = current.elapsedTime + (currentDt * fraction);
      } else {
        t0_100kmh = newElapsedTime;
      }
    }

    // 0-100 km/h Rollout
    if (t0_100kmhRollout == null && t0_100kmh != null && rollout1ft != null) {
      t0_100kmhRollout = t0_100kmh - rollout1ft;
    }

    // 0-130 mph (209.2147 km/h)
    if (t0_130mph == null && newSpeedKmh >= 209.2147) {
      double speedDiff = newSpeedKmh - current.speedKmh;
      if (speedDiff > 0) {
        double fraction = (209.2147 - current.speedKmh) / speedDiff;
        t0_130mph = current.elapsedTime + (currentDt * fraction);
      } else {
        t0_130mph = newElapsedTime;
      }
    }

    // 0-200 km/h (200.0 km/h)
    if (t0_200kmh == null && newSpeedKmh >= 200.0) {
      double speedDiff = newSpeedKmh - current.speedKmh;
      if (speedDiff > 0) {
        double fraction = (200.0 - current.speedKmh) / speedDiff;
        t0_200kmh = current.elapsedTime + (currentDt * fraction);
      } else {
        t0_200kmh = newElapsedTime;
      }
    }

    // 1/8 mile (201.168 meters)
    if (t18 == null && newDistance >= distance18Mile) {
      double distDiff = newDistance - current.distanceMeters;
      if (distDiff > 0) {
        double fraction = (distance18Mile - current.distanceMeters) / distDiff;
        t18 = current.elapsedTime + (currentDt * fraction);
        trap18 = current.speedKmh + ((newSpeedKmh - current.speedKmh) * fraction);
      } else {
        t18 = newElapsedTime;
        trap18 = newSpeedKmh;
      }
    }

    // 1/8 mile Rollout (target: distance18Mile + 0.3048)
    if (t18Rollout == null && rollout1ft != null && newDistance >= (distance18Mile + 0.3048)) {
      double distDiff = newDistance - current.distanceMeters;
      double absTime;
      if (distDiff > 0) {
        double fraction = ((distance18Mile + 0.3048) - current.distanceMeters) / distDiff;
        absTime = current.elapsedTime + (currentDt * fraction);
      } else {
        absTime = newElapsedTime;
      }
      t18Rollout = absTime - rollout1ft;
    }

    // 1000 ft (304.8 meters)
    if (t1000ft == null && newDistance >= distance1000ft) {
      double distDiff = newDistance - current.distanceMeters;
      if (distDiff > 0) {
        double fraction = (distance1000ft - current.distanceMeters) / distDiff;
        t1000ft = current.elapsedTime + (currentDt * fraction);
        trap1000 = current.speedKmh + ((newSpeedKmh - current.speedKmh) * fraction);
      } else {
        t1000ft = newElapsedTime;
        trap1000 = newSpeedKmh;
      }
    }

    // 1000 ft Rollout (target: distance1000ft + 0.3048)
    if (t1000Rollout == null && rollout1ft != null && newDistance >= (distance1000ft + 0.3048)) {
      double distDiff = newDistance - current.distanceMeters;
      double absTime;
      if (distDiff > 0) {
        double fraction = ((distance1000ft + 0.3048) - current.distanceMeters) / distDiff;
        absTime = current.elapsedTime + (currentDt * fraction);
      } else {
        absTime = newElapsedTime;
      }
      t1000Rollout = absTime - rollout1ft;
    }

    // 1/4 mile (402.336 meters)
    if (t14 == null && newDistance >= distance14Mile) {
      double distDiff = newDistance - current.distanceMeters;
      if (distDiff > 0) {
        double fraction = (distance14Mile - current.distanceMeters) / distDiff;
        t14 = current.elapsedTime + (currentDt * fraction);
        trap14 = current.speedKmh + ((newSpeedKmh - current.speedKmh) * fraction);
      } else {
        t14 = newElapsedTime;
        trap14 = newSpeedKmh;
      }
    }

    // 1/4 mile Rollout (target: distance14Mile + 0.3048)
    if (t14Rollout == null && rollout1ft != null && newDistance >= (distance14Mile + 0.3048)) {
      double distDiff = newDistance - current.distanceMeters;
      double absTime;
      if (distDiff > 0) {
        double fraction = ((distance14Mile + 0.3048) - current.distanceMeters) / distDiff;
        absTime = current.elapsedTime + (currentDt * fraction);
      } else {
        absTime = newElapsedTime;
      }
      t14Rollout = absTime - rollout1ft;
    }

    // 1/2 mile (804.672 meters)
    if (t12 == null && newDistance >= distance12Mile) {
      double distDiff = newDistance - current.distanceMeters;
      if (distDiff > 0) {
        double fraction = (distance12Mile - current.distanceMeters) / distDiff;
        t12 = current.elapsedTime + (currentDt * fraction);
        trap12 = current.speedKmh + ((newSpeedKmh - current.speedKmh) * fraction);
      } else {
        t12 = newElapsedTime;
        trap12 = newSpeedKmh;
      }
    }

    // 1/2 mile Rollout (target: distance12Mile + 0.3048)
    if (t12Rollout == null && rollout1ft != null && newDistance >= (distance12Mile + 0.3048)) {
      double distDiff = newDistance - current.distanceMeters;
      double absTime;
      if (distDiff > 0) {
        double fraction = ((distance12Mile + 0.3048) - current.distanceMeters) / distDiff;
        absTime = current.elapsedTime + (currentDt * fraction);
      } else {
        absTime = newElapsedTime;
      }
      t12Rollout = absTime - rollout1ft;
    }

    // 60-130 mph interval (96.5606 to 209.2147 km/h)
    if (t60_130 == null && t0_60mph != null && newSpeedKmh >= 209.2147) {
      double speedDiff = newSpeedKmh - current.speedKmh;
      if (speedDiff > 0) {
        double fraction = (209.2147 - current.speedKmh) / speedDiff;
        double t130 = current.elapsedTime + (currentDt * fraction);
        t60_130 = t130 - t0_60mph;
      }
    }

    // 100-200 km/h interval (100.0 to 200.0 km/h)
    if (t100_200 == null && t0_100kmh != null && newSpeedKmh >= 200.0) {
      double speedDiff = newSpeedKmh - current.speedKmh;
      if (speedDiff > 0) {
        double fraction = (200.0 - current.speedKmh) / speedDiff;
        double t200 = current.elapsedTime + (currentDt * fraction);
        t100_200 = t200 - t0_100kmh;
      }
    }

    // Determine target completion
    bool targetAchieved = false;
    if (current.targetDistance != null && current.targetDistanceUnit != null) {
      double targetDistanceMeters = current.targetDistance!;
      final unit = current.targetDistanceUnit!.toLowerCase();
      if (unit == 'feet') {
        targetDistanceMeters = current.targetDistance! * 0.3048;
      } else if (unit == 'mile') {
        targetDistanceMeters = current.targetDistance! * 1609.344;
      } else if (unit == 'kilometer') {
        targetDistanceMeters = current.targetDistance! * 1000.0;
      }
      if (newDistance >= targetDistanceMeters) {
        targetAchieved = true;
      }
    } else if (current.targetEndSpeed != null && current.targetStartSpeed == 0.0) {
      if (newSpeedKmh >= current.targetEndSpeed!) {
        targetAchieved = true;
      }
    }

    return current.copyWith(
      speedKmh: newSpeedKmh,
      distanceMeters: newDistance,
      elapsedTime: newElapsedTime,
      gForce: smoothedGForce,
      time60ft: t60ft,
      trap60ft: trap60,
      time330ft: t330ft,
      trap330ft: trap330,
      time0to50kmh: t0_50kmh,
      time0to60mph: t0_60mph,
      time0to100kmh: t0_100kmh,
      time18Mile: t18,
      trap18Mile: trap18,
      time1000ft: t1000ft,
      trap1000ft: trap1000,
      time14Mile: t14,
      trap14Mile: trap14,
      time12Mile: t12,
      trap12Mile: trap12,
      rolloutTime1ft: rollout1ft,
      time60ftRollout: t60ftRollout,
      time330ftRollout: t330ftRollout,
      time0to50kmhRollout: t0_50kmhRollout,
      time0to60mphRollout: t0_60mphRollout,
      time0to100kmhRollout: t0_100kmhRollout,
      time18MileRollout: t18Rollout,
      time1000ftRollout: t1000Rollout,
      time14MileRollout: t14Rollout,
      time12MileRollout: t12Rollout,
      time60to130mph: t60_130,
      time100to200kmh: t100_200,
      time0to130mph: t0_130mph,
      time0to200kmh: t0_200kmh,
      startAltitude: startAltitude,
      isRunning: !targetAchieved,
      history: newHistory,
    );
  }

  RaceMetrics _integrateInterval(
    RaceMetrics current,
    double newSpeedKmh,
    double currentAltitude,
    double smoothedGForce, {
    required double intervalStartSpeed,
    required double intervalEndSpeed,
    required double currentDt,
    int? gpsTimeMs,
  }) {
    final currentSpeedMs = current.speedKmh / 3.6;
    final newSpeedMs = newSpeedKmh / 3.6;

    // Trapezoidal integration for distance
    final avgSpeedMs = (currentSpeedMs + newSpeedMs) / 2;
    final double deltaDistance = avgSpeedMs * currentDt;
    final double newDistance = current.distanceMeters + deltaDistance;

    final newElapsedTime = current.elapsedTime + currentDt;

    final newHistory = List<DataPoint>.from(current.history)
      ..add(
        DataPoint(
          elapsedTime: newElapsedTime,
          speedKmh: newSpeedKmh,
          gForce: smoothedGForce,
          altitude: currentAltitude,
          gpsTimeMs: gpsTimeMs,
        ),
      );

    bool targetAchieved = false;
    double newElapsedTimeCalculated = newElapsedTime;
    
    if (newSpeedKmh >= intervalEndSpeed) {
      targetAchieved = true;
      double speedDiff = newSpeedKmh - current.speedKmh;
      if (speedDiff > 0) {
        double fraction = (intervalEndSpeed - current.speedKmh) / speedDiff;
        newElapsedTimeCalculated = current.elapsedTime + (currentDt * fraction);
      }
    }

    double? t60_130 = current.time60to130mph;
    double? t100_200 = current.time100to200kmh;
    double? t0_50kmh = current.time0to50kmh;
    double? t0_60mph = current.time0to60mph;
    double? t0_100kmh = current.time0to100kmh;
    double? t0_130mph = current.time0to130mph;
    double? t0_200kmh = current.time0to200kmh;
    
    if (current.targetStartSpeed != null && current.targetEndSpeed != null) {
      if ((current.targetStartSpeed! - 96.56).abs() < 1.0 &&
          (current.targetEndSpeed! - 209.21).abs() < 1.0 &&
          current.targetSpeedUnit == 'mph') {
        t60_130 = newElapsedTimeCalculated;
      } else if ((current.targetStartSpeed! - 100.0).abs() < 0.1 &&
                 (current.targetEndSpeed! - 200.0).abs() < 0.1 &&
                 current.targetSpeedUnit == 'kmh') {
        t100_200 = newElapsedTimeCalculated;
      } else if (current.targetStartSpeed == 0.0) {
        if ((current.targetEndSpeed! - 96.56).abs() < 1.0 &&
            current.targetSpeedUnit == 'mph') {
          t0_60mph = newElapsedTimeCalculated;
        } else if ((current.targetEndSpeed! - 50.0).abs() < 0.1 &&
                   current.targetSpeedUnit == 'kmh') {
          t0_50kmh = newElapsedTimeCalculated;
        } else if ((current.targetEndSpeed! - 100.0).abs() < 0.1 &&
                   current.targetSpeedUnit == 'kmh') {
          t0_100kmh = newElapsedTimeCalculated;
        } else if ((current.targetEndSpeed! - 209.21).abs() < 1.0 &&
                   current.targetSpeedUnit == 'mph') {
          t0_130mph = newElapsedTimeCalculated;
        } else if ((current.targetEndSpeed! - 200.0).abs() < 0.1 &&
                   current.targetSpeedUnit == 'kmh') {
          t0_200kmh = newElapsedTimeCalculated;
        }
      }
    }

    return current.copyWith(
      speedKmh: newSpeedKmh,
      distanceMeters: newDistance,
      elapsedTime: newElapsedTimeCalculated,
      gForce: smoothedGForce,
      time60to130mph: t60_130,
      time100to200kmh: t100_200,
      time0to50kmh: t0_50kmh,
      time0to60mph: t0_60mph,
      time0to100kmh: t0_100kmh,
      time0to130mph: t0_130mph,
      time0to200kmh: t0_200kmh,
      startAltitude: current.startAltitude,
      isRunning: !targetAchieved,
      history: newHistory,
    );
  }

  RaceMetrics? _tryTriggerStandingStart(
    RaceMetrics current,
    double newSpeedKmh,
    double currentAltitude, {
    required String runMode,
    required double? targetDistance,
    required String? targetDistanceUnit,
    required double? targetStartSpeed,
    required double? targetEndSpeed,
    required String? targetSpeedUnit,
    required double currentDt,
    double? sAccMps,
  }) {
    final commitKmh = launchCommitThresholdForSAcc(sAccMps);
    if (newSpeedKmh > commitKmh && _preRunBuffer.length >= 2) {
      final k = _preRunBuffer.length - 1;
      var crossingIndex = -1;

      for (var j = k - 1; j >= 0; j--) {
        if (_preRunBuffer[j].speedKmh <= zeroCrossingThreshold &&
            _preRunBuffer[j + 1].speedKmh > zeroCrossingThreshold) {
          crossingIndex = j;
          break;
        }
      }

      if (crossingIndex == -1) return null;

      final vStart = _preRunBuffer[crossingIndex].speedKmh;
      final vEnd = _preRunBuffer[crossingIndex + 1].speedKmh;
      final startFraction =
          (zeroCrossingThreshold - vStart) / (vEnd - vStart);

      final tCross0 = _preRunBuffer[crossingIndex].gpsTimeMs;
      final tCross1 = _preRunBuffer[crossingIndex + 1].gpsTimeMs;
      final tNow = _preRunBuffer[k].gpsTimeMs;
      final useItow = tCross0 != null && tCross1 != null && tNow != null;

      double stepDt(int fromIdx, int toIdx) {
        if (useItow) {
          return deltaGpsSeconds(
            _preRunBuffer[fromIdx].gpsTimeMs!,
            _preRunBuffer[toIdx].gpsTimeMs!,
          );
        }
        return currentDt;
      }

      final firstFullStepDt = stepDt(crossingIndex, crossingIndex + 1);
      final firstStepTime = firstFullStepDt * (1.0 - startFraction);

      var elapsedOffset = firstStepTime;
      for (var j = crossingIndex + 1; j < k; j++) {
        elapsedOffset += stepDt(j, j + 1);
      }

      var initialDistance = 0.0;
      final firstAvgMs =
          ((zeroCrossingThreshold / 3.6) + (vEnd / 3.6)) / 2;
      initialDistance += firstAvgMs * firstStepTime;
      for (var j = crossingIndex + 1; j < k; j++) {
        final stepAvgSpeedMs =
            ((_preRunBuffer[j].speedKmh / 3.6) +
                    (_preRunBuffer[j + 1].speedKmh / 3.6)) /
                2;
        initialDistance += stepAvgSpeedMs * stepDt(j, j + 1);
      }

      double? t0Ms = useItow
          ? tCross0 + startFraction * deltaGpsMs(tCross0, tCross1)
          : null;
      var launchSource = 'gps';

      // Pull t0 earlier when longitudinal G rises before GPS speed zero-cross.
      if (t0Ms != null) {
        final imuEdge = _findImuLaunchEdge(atOrBeforeGpsMs: t0Ms.round());
        if (imuEdge?.gpsTimeMs != null) {
          final leadSec =
              deltaGpsSeconds(imuEdge!.gpsTimeMs!, t0Ms.round());
          final sAccPoor = sAccMps != null && sAccMps > 0.35;
          if (leadSec >= 0.04 && leadSec <= imuLeadMaxSeconds) {
            final leadMs = leadSec * 1000.0;
            t0Ms = t0Ms - leadMs;
            elapsedOffset += leadSec;
            // Distance during the IMU-only lead is tiny at near-zero speed — skip.
            launchSource = sAccPoor ? 'imu' : 'fused';
          }
        }
      }

      const delayTicks = 2;
      int getShiftedIndex(int idx) =>
          (idx - delayTicks).clamp(0, _preRunBuffer.length - 1);

      final initialHistory = <DataPoint>[
        DataPoint(
          elapsedTime: 0.0,
          speedKmh: 0.0,
          gForce: _preRunBuffer[getShiftedIndex(crossingIndex)].gForce,
          altitude: _preRunBuffer[crossingIndex].altitude ?? currentAltitude,
          gpsTimeMs: t0Ms?.round(),
        ),
      ];

      for (var j = crossingIndex + 1; j <= k; j++) {
        final double tJ;
        if (useItow && t0Ms != null) {
          var dMs = _preRunBuffer[j].gpsTimeMs! - t0Ms;
          if (dMs < 0) dMs += 604800000;
          tJ = dMs / 1000.0;
        } else {
          tJ = firstStepTime + (j - (crossingIndex + 1)) * currentDt;
        }
        initialHistory.add(DataPoint(
          elapsedTime: tJ,
          speedKmh: _preRunBuffer[j].speedKmh,
          gForce: _preRunBuffer[getShiftedIndex(j)].gForce,
          altitude: _preRunBuffer[j].altitude ?? currentAltitude,
          gpsTimeMs: _preRunBuffer[j].gpsTimeMs,
        ));
      }

      return current.copyWith(
        isRunning: true,
        elapsedTime: elapsedOffset,
        distanceMeters: initialDistance,
        speedKmh: newSpeedKmh,
        gForce: current.gForce,
        startAltitude: currentAltitude,
        launchSource: launchSource,
        runMode: runMode,
        targetDistance: targetDistance,
        targetDistanceUnit: targetDistanceUnit,
        targetStartSpeed: targetStartSpeed,
        targetEndSpeed: targetEndSpeed,
        targetSpeedUnit: targetSpeedUnit,
        history: initialHistory,
      );
    }
    return null;
  }

  /// Latest IMU G rising edge at/before the GPS zero-crossing epoch.
  _ImuGSample? _findImuLaunchEdge({required int atOrBeforeGpsMs}) {
    if (_imuGBuffer.length < 3) return null;
    _ImuGSample? best;
    for (var i = 1; i < _imuGBuffer.length; i++) {
      final prev = _imuGBuffer[i - 1];
      final curr = _imuGBuffer[i];
      if (curr.gpsTimeMs == null) continue;
      if (prev.gForce >= imuLaunchGQuiet) continue;
      if (curr.gForce < imuLaunchGThreshold) continue;
      // Must not be after GPS t0 (allow 50 ms jitter).
      if (deltaGpsMs(atOrBeforeGpsMs, curr.gpsTimeMs!) > 50 &&
          curr.gpsTimeMs! > atOrBeforeGpsMs) {
        continue;
      }
      best = curr;
    }
    return best;
  }

  RaceMetrics reset() {
    _preRunBuffer.clear();
    _imuGBuffer.clear();
    _stoppedTicks = 0;
    _rejectedCount = 0;
    _lastGpsTimeMs = null;
    _lastGpsTimeSeconds = null;
    _lastValidDt = null;
    return RaceMetrics();
  }
}

class _ImuGSample {
  final int? gpsTimeMs;
  final double gForce;
  const _ImuGSample({required this.gpsTimeMs, required this.gForce});
}

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

  final List<DataPoint> _preRunBuffer = [];
  int _stoppedTicks = 0;
  int _rejectedCount = 0;
  double? _lastGpsTimeSeconds;
  double? _lastValidDt;

  double get lastValidDt => _lastValidDt ?? 0.1;

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
  }) {
    // Calculate current dynamic dt
    double currentDt = _lastValidDt ?? 0.1;
    if (gpsTimeSeconds != null && _lastGpsTimeSeconds != null) {
      double delta = gpsTimeSeconds - _lastGpsTimeSeconds!;
      if (delta < 0) {
        delta += 86400.0; // handle midnight rollover
      }
      if (delta > 0.01 && delta < 2.0) {
        currentDt = delta;
        _lastValidDt = delta;
      }
    }
    _lastGpsTimeSeconds = gpsTimeSeconds;

    // 0. Maintain Rolling Buffer (50 ticks) for 200ms G-Force latency shifting
    _preRunBuffer.add(
      DataPoint(
        elapsedTime: current.isRunning ? current.elapsedTime : 0.0,
        speedKmh: newSpeedKmh,
        gForce: current.gForce,
        altitude: currentAltitude,
      ),
    );
    if (_preRunBuffer.length > 50) {
      _preRunBuffer.removeAt(0);
    }

    int delayTicks = 2; // 200ms at 10Hz
    double shiftedGForce = current.gForce;
    if (_preRunBuffer.length > delayTicks) {
      shiftedGForce =
          _preRunBuffer[_preRunBuffer.length - 1 - delayTicks].gForce;
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
        : (_preRunBuffer.length > 1
              ? _preRunBuffer[_preRunBuffer.length - 2].speedKmh
              : 0.0);

    if (_preRunBuffer.isNotEmpty || current.isRunning) {
      double actualDeltaKmh = newSpeedKmh - lastSpeed;
      double expectedDeltaKmh =
          (shiftedGForce * gAcceleration * currentDt) * 3.6;
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
        distanceMeters: current.history.isNotEmpty
            ? current.distanceMeters
            : 0.0,
        elapsedTime: current.history.isNotEmpty ? current.elapsedTime : 0.0,
        startAltitude: current.history.isNotEmpty
            ? current.startAltitude
            : currentAltitude,
      );
    }

    if (!current.isRunning) {
      if (runMode == 'drag') {
        // Armed state
        if (newSpeedKmh == 0.0) {
          return current.copyWith(
            speedKmh: 0.0,
            distanceMeters: current.history.isNotEmpty
                ? current.distanceMeters
                : 0.0,
            elapsedTime: current.history.isNotEmpty ? current.elapsedTime : 0.0,
            gForce: current.gForce,
            startAltitude: current.history.isNotEmpty
                ? current.startAltitude
                : currentAltitude,
            runMode: 'drag',
            targetDistance: targetDistance,
            targetDistanceUnit: targetDistanceUnit,
            targetStartSpeed: targetStartSpeed,
            targetEndSpeed: targetEndSpeed,
            targetSpeedUnit: targetSpeedUnit,
          );
        }

        // 2. Launch Detection & Validation
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
        );
        if (triggered != null) {
          return triggered;
        }

        // We are stopped or moving slowly (creeping/GPS wandering).
        double displaySpeed = newSpeedKmh < 2.0 ? 0.0 : newSpeedKmh;
        return current.copyWith(
          speedKmh: displaySpeed,
          distanceMeters: current.history.isNotEmpty
              ? current.distanceMeters
              : 0.0,
          elapsedTime: current.history.isNotEmpty ? current.elapsedTime : 0.0,
          gForce: current.gForce,
          startAltitude: current.history.isNotEmpty
              ? current.startAltitude
              : currentAltitude,
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
          );
          if (triggered != null) {
            return triggered;
          }
        } else {
          if (_preRunBuffer.length >= 2) {
            double prevSpeed = _preRunBuffer[_preRunBuffer.length - 2].speedKmh;
            if (prevSpeed <= intervalStartSpeed &&
                newSpeedKmh > intervalStartSpeed) {
              // Trigger! Calculate the exact start crossing point.
              double speedDiff = newSpeedKmh - prevSpeed;
              double fraction = (intervalStartSpeed - prevSpeed) / speedDiff;

              // Time offset from the crossing point to the current tick
              double elapsedOffset = (1.0 - fraction) * currentDt;

              // Average speed during this fractional step (m/s)
              double avgSpeedMs =
                  ((intervalStartSpeed / 3.6) + (newSpeedKmh / 3.6)) / 2;
              double initialDistance = avgSpeedMs * elapsedOffset;

              RaceMetrics simulated = RaceMetrics(
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
                  ),
                  DataPoint(
                    elapsedTime: elapsedOffset,
                    speedKmh: newSpeedKmh,
                    gForce: smoothedGForce,
                    altitude: currentAltitude,
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
          distanceMeters: current.history.isNotEmpty
              ? current.distanceMeters
              : 0.0,
          elapsedTime: current.history.isNotEmpty ? current.elapsedTime : 0.0,
          gForce: current.gForce,
          startAltitude: current.history.isNotEmpty
              ? current.startAltitude
              : currentAltitude,
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
        );
      }
    }
  }

  RaceMetrics _integrateDrag(
    RaceMetrics current,
    double newSpeedKmh,
    double currentAltitude,
    double currentDt,
    double smoothedGForce,
  ) {
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
        ),
      );

    // Metrics triggers
    double? t60ft = current.time60ft;
    double? t330ft = current.time330ft;
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
      } else {
        t60ft = newElapsedTime;
      }
    }

    // 60 ft Rollout (target: 60ft + 1ft = 18.288 + 0.3048 = 18.5928 meters)
    if (t60ftRollout == null &&
        rollout1ft != null &&
        newDistance >= (distance60ft + 0.3048)) {
      double distDiff = newDistance - current.distanceMeters;
      double absTime;
      if (distDiff > 0) {
        double fraction =
            ((distance60ft + 0.3048) - current.distanceMeters) / distDiff;
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
      } else {
        t330ft = newElapsedTime;
      }
    }

    // 330 ft Rollout (target: distance330ft + 0.3048)
    if (t330ftRollout == null &&
        rollout1ft != null &&
        newDistance >= (distance330ft + 0.3048)) {
      double distDiff = newDistance - current.distanceMeters;
      double absTime;
      if (distDiff > 0) {
        double fraction =
            ((distance330ft + 0.3048) - current.distanceMeters) / distDiff;
        absTime = current.elapsedTime + (currentDt * fraction);
      } else {
        absTime = newElapsedTime;
      }
      t330ftRollout = absTime - rollout1ft;
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
        trap18 =
            current.speedKmh + ((newSpeedKmh - current.speedKmh) * fraction);
      } else {
        t18 = newElapsedTime;
        trap18 = newSpeedKmh;
      }
    }

    // 1/8 mile Rollout (target: distance18Mile + 0.3048)
    if (t18Rollout == null &&
        rollout1ft != null &&
        newDistance >= (distance18Mile + 0.3048)) {
      double distDiff = newDistance - current.distanceMeters;
      double absTime;
      if (distDiff > 0) {
        double fraction =
            ((distance18Mile + 0.3048) - current.distanceMeters) / distDiff;
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
        trap1000 =
            current.speedKmh + ((newSpeedKmh - current.speedKmh) * fraction);
      } else {
        t1000ft = newElapsedTime;
        trap1000 = newSpeedKmh;
      }
    }

    // 1000 ft Rollout (target: distance1000ft + 0.3048)
    if (t1000Rollout == null &&
        rollout1ft != null &&
        newDistance >= (distance1000ft + 0.3048)) {
      double distDiff = newDistance - current.distanceMeters;
      double absTime;
      if (distDiff > 0) {
        double fraction =
            ((distance1000ft + 0.3048) - current.distanceMeters) / distDiff;
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
        trap14 =
            current.speedKmh + ((newSpeedKmh - current.speedKmh) * fraction);
      } else {
        t14 = newElapsedTime;
        trap14 = newSpeedKmh;
      }
    }

    // 1/4 mile Rollout (target: distance14Mile + 0.3048)
    if (t14Rollout == null &&
        rollout1ft != null &&
        newDistance >= (distance14Mile + 0.3048)) {
      double distDiff = newDistance - current.distanceMeters;
      double absTime;
      if (distDiff > 0) {
        double fraction =
            ((distance14Mile + 0.3048) - current.distanceMeters) / distDiff;
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
        trap12 =
            current.speedKmh + ((newSpeedKmh - current.speedKmh) * fraction);
      } else {
        t12 = newElapsedTime;
        trap12 = newSpeedKmh;
      }
    }

    // 1/2 mile Rollout (target: distance12Mile + 0.3048)
    if (t12Rollout == null &&
        rollout1ft != null &&
        newDistance >= (distance12Mile + 0.3048)) {
      double distDiff = newDistance - current.distanceMeters;
      double absTime;
      if (distDiff > 0) {
        double fraction =
            ((distance12Mile + 0.3048) - current.distanceMeters) / distDiff;
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
      // Add 1ft (0.3048m) to allow for NHRA rollout calculations to complete
      if (newDistance >= targetDistanceMeters + 0.3048) {
        targetAchieved = true;
      }
    } else if (current.targetEndSpeed != null &&
        current.targetStartSpeed == 0.0) {
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
      time330ft: t330ft,
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
  }) {
    if (newSpeedKmh > launchCommitThreshold && _preRunBuffer.length >= 2) {
      int k = _preRunBuffer.length - 1;
      int crossingIndex = -1;

      // Scan backwards to find the most recent zero-crossing transition
      for (int j = k - 1; j >= 0; j--) {
        if (_preRunBuffer[j].speedKmh <= zeroCrossingThreshold &&
            _preRunBuffer[j + 1].speedKmh > zeroCrossingThreshold) {
          crossingIndex = j;
          break;
        }
      }

      if (crossingIndex != -1) {
        double vStart = _preRunBuffer[crossingIndex].speedKmh;
        double vEnd = _preRunBuffer[crossingIndex + 1].speedKmh;
        double startFraction =
            (zeroCrossingThreshold - vStart) / (vEnd - vStart);

        // Time offset from the crossing point to the current tick
        double elapsedOffset = (k - crossingIndex - startFraction) * currentDt;

        // Integrate distance for the first fractional step
        double firstStepTime = currentDt * (1.0 - startFraction);
        double avgSpeedMs = ((zeroCrossingThreshold / 3.6) + (vEnd / 3.6)) / 2;
        double initialDistance = avgSpeedMs * firstStepTime;

        // Integrate distance for all subsequent steps
        for (int j = crossingIndex + 1; j < k; j++) {
          double stepAvgSpeedMs =
              ((_preRunBuffer[j].speedKmh / 3.6) +
                  (_preRunBuffer[j + 1].speedKmh / 3.6)) /
              2;
          initialDistance += stepAvgSpeedMs * currentDt;
        }

        int delayTicks = 2;
        int getShiftedIndex(int idx) =>
            (idx - delayTicks).clamp(0, _preRunBuffer.length - 1);

        List<DataPoint> initialHistory = [];
        // Zero crossing point
        initialHistory.add(
          DataPoint(
            elapsedTime: 0.0,
            speedKmh: 0.0, // Start exactly at 0 to match physical reality
            gForce: _preRunBuffer[getShiftedIndex(crossingIndex)].gForce,
            altitude: _preRunBuffer[crossingIndex].altitude ?? currentAltitude,
          ),
        );

        // Points from crossingIndex + 1 to k
        for (int j = crossingIndex + 1; j <= k; j++) {
          double tJ = firstStepTime + (j - (crossingIndex + 1)) * currentDt;
          initialHistory.add(
            DataPoint(
              elapsedTime: tJ,
              speedKmh: _preRunBuffer[j].speedKmh,
              gForce: _preRunBuffer[getShiftedIndex(j)].gForce,
              altitude: _preRunBuffer[j].altitude ?? currentAltitude,
            ),
          );
        }

        RaceMetrics simulated = RaceMetrics(
          isRunning: true,
          elapsedTime: elapsedOffset,
          distanceMeters: initialDistance,
          speedKmh: newSpeedKmh,
          gForce: current.gForce,
          startAltitude: currentAltitude,
          runMode: runMode,
          targetDistance: targetDistance,
          targetDistanceUnit: targetDistanceUnit,
          targetStartSpeed: targetStartSpeed,
          targetEndSpeed: targetEndSpeed,
          targetSpeedUnit: targetSpeedUnit,
          history: initialHistory,
        );

        // Buffer is kept for ongoing history
        return simulated;
      }
    }
    return null;
  }

  RaceMetrics reset() {
    _preRunBuffer.clear();
    _stoppedTicks = 0;
    _rejectedCount = 0;
    _lastGpsTimeSeconds = null;
    _lastValidDt = null;
    return RaceMetrics();
  }
}

import 'package:open_dragy/models/race_target.dart';

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
    required RunMode runMode,
    required double? targetDistance,
    required DistanceUnit? targetDistanceUnit,
    required double? targetStartSpeed,
    required double? targetEndSpeed,
    required SpeedUnit? targetSpeedUnit,
    required double intervalStartSpeed,
    required double intervalEndSpeed,
    double? gpsTimeSeconds,
    List<RaceTarget> activeTargets = officialTests,
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

    // 0. Maintain Rolling Buffer for launch zero-crossing detection and outlier checking
    _preRunBuffer.add(
      DataPoint(
        elapsedTime: current.isRunning ? current.elapsedTime : 0.0,
        speedKmh: newSpeedKmh,
        gForce: current.gForce,
        altitude: currentAltitude,
      ),
    );

    // Keep buffer bounded (50 ticks = ~0.5s of history for launch detection)
    if (_preRunBuffer.length > 50) {
      _preRunBuffer.removeAt(0);
    }

    double smoothedGForce = current.gForce;

    // 0.5 Sensor-Fusion Outlier Rejection
    // Validate the GPS speed jump against the IMU acceleration.
    double lastSpeed = current.isRunning
        ? current.speedKmh
        : (_preRunBuffer.length > 1
              ? _preRunBuffer[_preRunBuffer.length - 2].speedKmh
              : 0.0);

    if (_preRunBuffer.isNotEmpty || current.isRunning) {
      double actualDeltaKmh = newSpeedKmh - lastSpeed;
      double expectedDeltaKmh =
          (smoothedGForce * gAcceleration * currentDt) * 3.6;
      double dynamicToleranceKmh = (1.0 * gAcceleration * currentDt) * 3.6;

      if (actualDeltaKmh > 0 &&
          (actualDeltaKmh - expectedDeltaKmh).abs() > dynamicToleranceKmh) {
        _rejectedCount++;
        if (_rejectedCount > 2) {
          // 200ms of sustained mismatch
          _rejectedCount = 0;
          if (!current.isRunning) {
            // Accept new reality (e.g., GPS reconnect) but do not clear buffer to maintain history
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
      if (runMode == RunMode.drag) {
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
            runMode: RunMode.drag,
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
          runMode: RunMode.drag,
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
          runMode: RunMode.drag,
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
            runMode: RunMode.interval,
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
                runMode: RunMode.interval,
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

              // Do not clear _preRunBuffer to maintain rolling history
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
          runMode: RunMode.interval,
          targetDistance: targetDistance,
          targetDistanceUnit: targetDistanceUnit,
          targetStartSpeed: targetStartSpeed,
          targetEndSpeed: targetEndSpeed,
          targetSpeedUnit: targetSpeedUnit,
        );
      }
    } else {
      // 4. Already running, just integrate normally
      if (runMode == RunMode.drag) {
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
          activeTargets,
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
          activeTargets: activeTargets,
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
    List<RaceTarget> activeTargets,
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

    final Map<String, double> newTargetTimes = Map.from(current.targetTimes);
    final Map<String, double> newTargetSpeeds = Map.from(current.targetSpeeds);
    double? rollout1ft = current.rolloutTime1ft;
    
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

    for (final target in activeTargets) {
      if (newTargetTimes.containsKey(target.id)) continue;

      if (target.distance != null && target.distanceUnit != null) {
        double targetDistanceMeters = convertToMeters(target.distance!, target.distanceUnit!);

        if (newDistance >= targetDistanceMeters) {
          double distDiff = newDistance - current.distanceMeters;
          if (distDiff > 0) {
            double fraction = (targetDistanceMeters - current.distanceMeters) / distDiff;
            newTargetTimes[target.id] = current.elapsedTime + (currentDt * fraction);
            newTargetSpeeds[target.id] = current.speedKmh + ((newSpeedKmh - current.speedKmh) * fraction);
          } else {
            newTargetTimes[target.id] = newElapsedTime;
            newTargetSpeeds[target.id] = newSpeedKmh;
          }
        }
      } else if (target.endSpeed != null && (target.startSpeed == null || target.startSpeed == 0.0)) {
        double targetEndSpeedKmh = target.endSpeed!;
        if (newSpeedKmh >= targetEndSpeedKmh) {
          double speedDiff = newSpeedKmh - current.speedKmh;
          if (speedDiff > 0) {
            double fraction = (targetEndSpeedKmh - current.speedKmh) / speedDiff;
            newTargetTimes[target.id] = current.elapsedTime + (currentDt * fraction);
          } else {
            newTargetTimes[target.id] = newElapsedTime;
          }
        }
      }
    }

    // Real-time calculation for official rolling intervals
    if (!newTargetTimes.containsKey('60-130mph') && newTargetTimes.containsKey('0-60mph') && newSpeedKmh >= 209.2147) {
      double speedDiff = newSpeedKmh - current.speedKmh;
      if (speedDiff > 0) {
        double fraction = (209.2147 - current.speedKmh) / speedDiff;
        double t130 = current.elapsedTime + (currentDt * fraction);
        newTargetTimes['60-130mph'] = t130 - newTargetTimes['0-60mph']!;
      }
    }

    if (!newTargetTimes.containsKey('100-200kmh') && newTargetTimes.containsKey('0-100kmh') && newSpeedKmh >= 200.0) {
      double speedDiff = newSpeedKmh - current.speedKmh;
      if (speedDiff > 0) {
        double fraction = (200.0 - current.speedKmh) / speedDiff;
        double t200 = current.elapsedTime + (currentDt * fraction);
        newTargetTimes['100-200kmh'] = t200 - newTargetTimes['0-100kmh']!;
      }
    }

    // Determine target completion
    bool targetAchieved = false;
    if (current.targetDistance != null && current.targetDistanceUnit != null) {
      double targetDistanceMeters = convertToMeters(current.targetDistance!, current.targetDistanceUnit!);
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
      targetTimes: newTargetTimes,
      targetSpeeds: newTargetSpeeds,
      rolloutTime1ft: rollout1ft,
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
    required List<RaceTarget> activeTargets,
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

    final Map<String, double> newTargetTimes = Map.from(current.targetTimes);

    if (targetAchieved) {
      for (final target in activeTargets) {
        if (newTargetTimes.containsKey(target.id)) continue;
        
        if (target.endSpeed != null && target.startSpeed != null) {
          if ((current.targetStartSpeed! - target.startSpeed!).abs() < 1.0 &&
              (current.targetEndSpeed! - target.endSpeed!).abs() < 1.0) {
             newTargetTimes[target.id] = newElapsedTimeCalculated;
          }
        }
      }
    }

    return current.copyWith(
      speedKmh: newSpeedKmh,
      distanceMeters: newDistance,
      elapsedTime: newElapsedTimeCalculated,
      gForce: smoothedGForce,
      targetTimes: newTargetTimes,
      startAltitude: current.startAltitude,
      isRunning: !targetAchieved,
      history: newHistory,
    );
  }

  RaceMetrics? _tryTriggerStandingStart(
    RaceMetrics current,
    double newSpeedKmh,
    double currentAltitude, {
    required RunMode runMode,
    required double? targetDistance,
    required DistanceUnit? targetDistanceUnit,
    required double? targetStartSpeed,
    required double? targetEndSpeed,
    required SpeedUnit? targetSpeedUnit,
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

        List<DataPoint> initialHistory = [];
        // Zero crossing point
        initialHistory.add(
          DataPoint(
            elapsedTime: 0.0,
            speedKmh: 0.0, // Start exactly at 0 to match physical reality
            gForce: _preRunBuffer[crossingIndex].gForce,
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
              gForce: _preRunBuffer[j].gForce,
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

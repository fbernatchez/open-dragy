import 'package:open_dragy/models/race_test.dart';

import '../models/race_metrics.dart';

class PhysicsEngine {
  static const double gAcceleration = 9.80665; // m/s^2

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
    required double? testDistance,
    required DistanceUnit? testDistanceUnit,
    required double? testStartSpeed,
    required double? testEndSpeed,
    required SpeedUnit? testSpeedUnit,
    required double intervalStartSpeed,
    required double intervalEndSpeed,
    double? gpsTimeSeconds,
    List<RaceTest> activeTests = officialTests,
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
      return _buildWaitingMetrics(
        current,
        newSpeedKmh,
        currentAltitude,
        runMode: runMode,
        testDistance: testDistance,
        testDistanceUnit: testDistanceUnit,
        testStartSpeed: testStartSpeed,
        testEndSpeed: testEndSpeed,
        testSpeedUnit: testSpeedUnit,
      );
    }

    if (!current.isRunning) {
      if (runMode == RunMode.drag) {
        if (newSpeedKmh == 0.0) {
          return _buildWaitingMetrics(
            current,
            0.0,
            currentAltitude,
            runMode: RunMode.drag,
            testDistance: testDistance,
            testDistanceUnit: testDistanceUnit,
            testStartSpeed: testStartSpeed,
            testEndSpeed: testEndSpeed,
            testSpeedUnit: testSpeedUnit,
          );
        }

        // 2. Launch Detection & Validation
        final triggered = _tryTriggerStandingStart(
          current,
          newSpeedKmh,
          currentAltitude,
          runMode: RunMode.drag,
          testDistance: testDistance,
          testDistanceUnit: testDistanceUnit,
          testStartSpeed: testStartSpeed,
          testEndSpeed: testEndSpeed,
          testSpeedUnit: testSpeedUnit,
          currentDt: currentDt,
        );
        if (triggered != null) {
          return triggered;
        }

        return _buildWaitingMetrics(
          current,
          newSpeedKmh,
          currentAltitude,
          runMode: RunMode.drag,
          testDistance: testDistance,
          testDistanceUnit: testDistanceUnit,
          testStartSpeed: testStartSpeed,
          testEndSpeed: testEndSpeed,
          testSpeedUnit: testSpeedUnit,
        );
      } else {
        // Interval Mode
        if (intervalStartSpeed == 0.0) {
          final triggered = _tryTriggerStandingStart(
            current,
            newSpeedKmh,
            currentAltitude,
            runMode: RunMode.interval,
            testDistance: testDistance,
            testDistanceUnit: testDistanceUnit,
            testStartSpeed: testStartSpeed,
            testEndSpeed: testEndSpeed,
            testSpeedUnit: testSpeedUnit,
            currentDt: currentDt,
          );
          if (triggered != null) {
            return triggered;
          }
        } else {
          if (_preRunBuffer.length >= 2) {
            double prevSpeed = _preRunBuffer[_preRunBuffer.length - 2].speedKmh;
            bool isBraking = intervalStartSpeed > intervalEndSpeed;
            bool triggered = false;

            if (!isBraking &&
                prevSpeed <= intervalStartSpeed &&
                newSpeedKmh > intervalStartSpeed) {
              triggered = true;
            } else if (isBraking &&
                prevSpeed >= intervalStartSpeed &&
                newSpeedKmh < intervalStartSpeed) {
              triggered = true;
            }

            if (triggered) {
              // Trigger! Calculate the exact start crossing point.
              double speedDiff = (newSpeedKmh - prevSpeed).abs();
              double fraction =
                  (intervalStartSpeed - prevSpeed).abs() / speedDiff;

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
                testDistance: testDistance,
                testDistanceUnit: testDistanceUnit,
                testStartSpeed: testStartSpeed,
                testEndSpeed: testEndSpeed,
                testSpeedUnit: testSpeedUnit,
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

        return _buildWaitingMetrics(
          current,
          newSpeedKmh,
          currentAltitude,
          runMode: RunMode.interval,
          testDistance: testDistance,
          testDistanceUnit: testDistanceUnit,
          testStartSpeed: testStartSpeed,
          testEndSpeed: testEndSpeed,
          testSpeedUnit: testSpeedUnit,
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
          activeTests,
        );
      } else {
        // Interval Mode
        // Auto-cancel logic:
        bool isBraking = intervalStartSpeed > intervalEndSpeed;
        bool shouldCancel = false;

        if (isBraking) {
          shouldCancel = newSpeedKmh > intervalStartSpeed + 10.0;
        } else {
          final double cancelThreshold = intervalStartSpeed == 0.0
              ? 3.0
              : (intervalStartSpeed - 10.0).clamp(0.0, double.infinity);
          shouldCancel = newSpeedKmh < cancelThreshold;
        }

        if (shouldCancel) {
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
          activeTests: activeTests,
        );
      }
    }
  }

  RaceMetrics _buildWaitingMetrics(
    RaceMetrics current,
    double speedKmh,
    double currentAltitude, {
    required RunMode runMode,
    required double? testDistance,
    required DistanceUnit? testDistanceUnit,
    required double? testStartSpeed,
    required double? testEndSpeed,
    required SpeedUnit? testSpeedUnit,
  }) {
    final double displaySpeed = speedKmh < 2.0 ? 0.0 : speedKmh;
    return current.copyWith(
      speedKmh: displaySpeed,
      isRunning: false,
      distanceMeters: current.history.isNotEmpty ? current.distanceMeters : 0.0,
      elapsedTime: current.history.isNotEmpty ? current.elapsedTime : 0.0,
      gForce: current.gForce,
      startAltitude:
          current.history.isNotEmpty ? current.startAltitude : currentAltitude,
      runMode: runMode,
      testDistance: testDistance,
      testDistanceUnit: testDistanceUnit,
      testStartSpeed: testStartSpeed,
      testEndSpeed: testEndSpeed,
      testSpeedUnit: testSpeedUnit,
    );
  }

  static ({
    double newDistance,
    double newElapsedTime,
    List<DataPoint> newHistory,
  }) _integrateStep(
    RaceMetrics current,
    double newSpeedKmh,
    double currentAltitude,
    double currentDt,
    double smoothedGForce,
  ) {
    final currentSpeedMs = current.speedKmh / 3.6;
    final newSpeedMs = newSpeedKmh / 3.6;
    final avgSpeedMs = (currentSpeedMs + newSpeedMs) / 2;
    final double deltaDistance = avgSpeedMs * currentDt;
    final double newDistance = current.distanceMeters + deltaDistance;
    final double newElapsedTime = current.elapsedTime + currentDt;

    final newHistory = List<DataPoint>.from(current.history)
      ..add(
        DataPoint(
          elapsedTime: newElapsedTime,
          speedKmh: newSpeedKmh,
          gForce: smoothedGForce,
          altitude: currentAltitude,
        ),
      );

    return (
      newDistance: newDistance,
      newElapsedTime: newElapsedTime,
      newHistory: newHistory,
    );
  }

  static double _interpolateCrossingTime({
    required double t0,
    required double currentDt,
    required double val0,
    required double val1,
    required double target,
  }) {
    final diff = (val1 - val0).abs();
    if (diff > 0) {
      final fraction = (target - val0).abs() / diff;
      return t0 + (currentDt * fraction);
    }
    return t0 + currentDt;
  }

  RaceMetrics _integrateDrag(
    RaceMetrics current,
    double newSpeedKmh,
    double currentAltitude,
    double currentDt,
    double smoothedGForce,
    List<RaceTest> activeTests,
  ) {
    final (:newDistance, :newElapsedTime, :newHistory) = _integrateStep(
      current,
      newSpeedKmh,
      currentAltitude,
      currentDt,
      smoothedGForce,
    );

    final Map<String, double> newtestTimes = Map.from(current.testTimes);
    double? rollout1ft = current.rolloutTime1ft;
    final double startAltitude = current.startAltitude ?? currentAltitude;

    // 1 ft (0.3048 meters) for rollout trigger point
    if (rollout1ft == null && newDistance >= 0.3048) {
      rollout1ft = _interpolateCrossingTime(
        t0: current.elapsedTime,
        currentDt: currentDt,
        val0: current.distanceMeters,
        val1: newDistance,
        target: 0.3048,
      );
    }

    for (final test in activeTests) {
      if (test.distance != null && test.distanceUnit != null) {
        double testDistanceMeters = convertToMeters(
          test.distance!,
          test.distanceUnit!,
        );

        if (!newtestTimes.containsKey(test.id) &&
            newDistance >= testDistanceMeters) {
          newtestTimes[test.id] = _interpolateCrossingTime(
            t0: current.elapsedTime,
            currentDt: currentDt,
            val0: current.distanceMeters,
            val1: newDistance,
            target: testDistanceMeters,
          );
        }

        // Distance Rollout (+1ft / 0.3048m track shift)
        final rolloutKey = '${test.id}_rollout';
        if (rollout1ft != null &&
            !newtestTimes.containsKey(rolloutKey) &&
            newDistance >= (testDistanceMeters + 0.3048)) {
          final absTime = _interpolateCrossingTime(
            t0: current.elapsedTime,
            currentDt: currentDt,
            val0: current.distanceMeters,
            val1: newDistance,
            target: testDistanceMeters + 0.3048,
          );
          newtestTimes[rolloutKey] = absTime - rollout1ft;
        }
      } else if (test.endSpeed != null &&
          (test.startSpeed == null || test.startSpeed == 0.0)) {
        double testEndSpeedKmh = test.endSpeed!;
        if (!newtestTimes.containsKey(test.id) &&
            newSpeedKmh >= testEndSpeedKmh) {
          final crossingTime = _interpolateCrossingTime(
            t0: current.elapsedTime,
            currentDt: currentDt,
            val0: current.speedKmh,
            val1: newSpeedKmh,
            target: testEndSpeedKmh,
          );
          newtestTimes[test.id] = crossingTime;
          if (rollout1ft != null) {
            newtestTimes['${test.id}_rollout'] = crossingTime - rollout1ft;
          }
        }
      } else if (test.endSpeed != null &&
          test.startSpeed != null &&
          test.startSpeed! > 0.0) {
        double testStartSpeedKmh = test.startSpeed!;
        double testEndSpeedKmh = test.endSpeed!;
        String startKey = '${test.id}_start';
        bool isBraking = testStartSpeedKmh > testEndSpeedKmh;

        double effectiveEndSpeed = testEndSpeedKmh;
        if (isBraking && testEndSpeedKmh == 0.0) {
          effectiveEndSpeed = PhysicsEngine.zeroCrossingThreshold;
        }

        // Track start crossing
        if (!newtestTimes.containsKey(startKey)) {
          if ((!isBraking &&
                  current.speedKmh <= testStartSpeedKmh &&
                  newSpeedKmh >= testStartSpeedKmh) ||
              (isBraking &&
                  current.speedKmh >= testStartSpeedKmh &&
                  newSpeedKmh <= testStartSpeedKmh)) {
            newtestTimes[startKey] = _interpolateCrossingTime(
              t0: current.elapsedTime,
              currentDt: currentDt,
              val0: current.speedKmh,
              val1: newSpeedKmh,
              target: testStartSpeedKmh,
            );
          }
        }

        // Check if we crossed the end speed (and already have the start time)
        if (newtestTimes.containsKey(startKey) &&
            !newtestTimes.containsKey(test.id)) {
          if (!isBraking) {
            if (newSpeedKmh < testStartSpeedKmh) {
              newtestTimes.remove(startKey);
            } else if (newSpeedKmh >= testEndSpeedKmh) {
              final tEnd = _interpolateCrossingTime(
                t0: current.elapsedTime,
                currentDt: currentDt,
                val0: current.speedKmh,
                val1: newSpeedKmh,
                target: testEndSpeedKmh,
              );
              newtestTimes[test.id] = tEnd - newtestTimes[startKey]!;
            }
          } else {
            if (newSpeedKmh > testStartSpeedKmh) {
              newtestTimes.remove(startKey);
            } else if (newSpeedKmh <= effectiveEndSpeed) {
              final tEnd = _interpolateCrossingTime(
                t0: current.elapsedTime,
                currentDt: currentDt,
                val0: current.speedKmh,
                val1: newSpeedKmh,
                target: testEndSpeedKmh,
              );
              newtestTimes[test.id] = tEnd - newtestTimes[startKey]!;
            }
          }
        }
      }
    }

    // Determine target completion
    bool testAchieved = false;
    if (current.testDistance != null && current.testDistanceUnit != null) {
      double testDistanceMeters = convertToMeters(
        current.testDistance!,
        current.testDistanceUnit!,
      );
      // Add 1ft (0.3048m) to allow for NHRA rollout calculations to complete
      if (newDistance >= testDistanceMeters + 0.3048) {
        testAchieved = true;
      }
    } else if (current.testEndSpeed != null && current.testStartSpeed == 0.0) {
      if (newSpeedKmh >= current.testEndSpeed!) {
        testAchieved = true;
      }
    }

    return current.copyWith(
      speedKmh: newSpeedKmh,
      distanceMeters: newDistance,
      elapsedTime: newElapsedTime,
      gForce: smoothedGForce,
      testTimes: newtestTimes,
      rolloutTime1ft: rollout1ft,
      startAltitude: startAltitude,
      isRunning: !testAchieved,
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
    required List<RaceTest> activeTests,
  }) {
    final (:newDistance, :newElapsedTime, :newHistory) = _integrateStep(
      current,
      newSpeedKmh,
      currentAltitude,
      currentDt,
      smoothedGForce,
    );

    bool testAchieved = false;
    double newElapsedTimeCalculated = newElapsedTime;
    bool isBraking = intervalStartSpeed > intervalEndSpeed;

    double effectiveEndSpeed = intervalEndSpeed;
    if (isBraking && intervalEndSpeed == 0.0) {
      effectiveEndSpeed = PhysicsEngine.zeroCrossingThreshold;
    }

    if (!isBraking && newSpeedKmh >= intervalEndSpeed) {
      testAchieved = true;
      newElapsedTimeCalculated = _interpolateCrossingTime(
        t0: current.elapsedTime,
        currentDt: currentDt,
        val0: current.speedKmh,
        val1: newSpeedKmh,
        target: intervalEndSpeed,
      );
    } else if (isBraking && newSpeedKmh <= effectiveEndSpeed) {
      testAchieved = true;
      newElapsedTimeCalculated = _interpolateCrossingTime(
        t0: current.elapsedTime,
        currentDt: currentDt,
        val0: current.speedKmh,
        val1: newSpeedKmh,
        target: intervalEndSpeed,
      );
    }

    double? rollout1ft = current.rolloutTime1ft;
    if (intervalStartSpeed == 0.0 &&
        rollout1ft == null &&
        newDistance >= 0.3048) {
      rollout1ft = _interpolateCrossingTime(
        t0: current.elapsedTime,
        currentDt: currentDt,
        val0: current.distanceMeters,
        val1: newDistance,
        target: 0.3048,
      );
    }

    final Map<String, double> newtestTimes = Map.from(current.testTimes);

    if (testAchieved) {
      if (current.testStartSpeed != null &&
          current.testEndSpeed != null &&
          current.testSpeedUnit != null) {
        final unit = current.testSpeedUnit!.name;
        final customId =
            'custom_${current.testStartSpeed!.round()}_${current.testEndSpeed!.round()}_$unit';
        if (!newtestTimes.containsKey(customId)) {
          newtestTimes[customId] = newElapsedTimeCalculated;
          if (intervalStartSpeed == 0.0 && rollout1ft != null) {
            newtestTimes['${customId}_rollout'] =
                newElapsedTimeCalculated - rollout1ft;
          }
        }
      }
      for (final test in activeTests) {
        if (newtestTimes.containsKey(test.id)) continue;

        if (test.endSpeed != null && test.startSpeed != null) {
          if ((intervalStartSpeed - test.startSpeed!).abs() < 1.0 &&
              (intervalEndSpeed - test.endSpeed!).abs() < 1.0) {
            newtestTimes[test.id] = newElapsedTimeCalculated;
            if (intervalStartSpeed == 0.0 && rollout1ft != null) {
              newtestTimes['${test.id}_rollout'] =
                  newElapsedTimeCalculated - rollout1ft;
            }
          }
        }
      }
    }

    return current.copyWith(
      speedKmh: newSpeedKmh,
      distanceMeters: newDistance,
      elapsedTime: newElapsedTimeCalculated,
      gForce: smoothedGForce,
      testTimes: newtestTimes,
      rolloutTime1ft: rollout1ft,
      startAltitude: current.startAltitude,
      isRunning: !testAchieved,
      history: newHistory,
    );
  }

  RaceMetrics? _tryTriggerStandingStart(
    RaceMetrics current,
    double newSpeedKmh,
    double currentAltitude, {
    required RunMode runMode,
    required double? testDistance,
    required DistanceUnit? testDistanceUnit,
    required double? testStartSpeed,
    required double? testEndSpeed,
    required SpeedUnit? testSpeedUnit,
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
          testDistance: testDistance,
          testDistanceUnit: testDistanceUnit,
          testStartSpeed: testStartSpeed,
          testEndSpeed: testEndSpeed,
          testSpeedUnit: testSpeedUnit,
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

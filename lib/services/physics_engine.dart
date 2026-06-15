import '../models/race_metrics.dart';

class PhysicsEngine {
  static const double gAcceleration = 9.80665; // m/s^2

  static const double distance60ft = 18.288;
  static const double distance18Mile = 201.168;
  static const double distance1000ft = 304.8;
  static const double distance14Mile = 402.336;
  static const double distance12Mile = 804.672;

  static const double launchCommitThreshold =
      3.0; // km/h needed to confirm a real launch (ignores GPS wandering)
  static const double zeroCrossingThreshold =
      0.5; // km/h threshold for interpolating exact start


  final List<double> _speedBuffer = [];
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

    // 0.5 Sensor-Fusion Outlier Rejection
    // Validate the GPS speed jump against the live IMU acceleration.
    double lastSpeed = current.isRunning
        ? current.speedKmh
        : (_speedBuffer.isNotEmpty ? _speedBuffer.last : 0.0);

    if (_speedBuffer.isNotEmpty || current.isRunning) {
      double actualDeltaKmh = newSpeedKmh - lastSpeed;
      double expectedDeltaKmh = (current.gForce * gAcceleration * currentDt) * 3.6;
      double dynamicToleranceKmh = (1.0 * gAcceleration * currentDt) * 3.6;

      if (actualDeltaKmh > 0 &&
          (actualDeltaKmh - expectedDeltaKmh).abs() > dynamicToleranceKmh) {
        _rejectedCount++;
        if (_rejectedCount > 2) {
          // 200ms of sustained mismatch
          _rejectedCount = 0;
          if (!current.isRunning) {
            _speedBuffer.clear(); // Accept new reality (e.g., GPS reconnect)
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
      _speedBuffer.clear();
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
      // We are armed, waiting for trigger
      _speedBuffer.add(newSpeedKmh);
      if (_speedBuffer.length > 50) {
        _speedBuffer.removeAt(0);
      }

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
          if (_speedBuffer.length >= 2) {
            double prevSpeed = _speedBuffer[_speedBuffer.length - 2];
            if (prevSpeed <= intervalStartSpeed && newSpeedKmh > intervalStartSpeed) {
              // Trigger! Calculate the exact start crossing point.
              double speedDiff = newSpeedKmh - prevSpeed;
              double fraction = (intervalStartSpeed - prevSpeed) / speedDiff;
              
              // Time offset from the crossing point to the current tick
              double elapsedOffset = (1.0 - fraction) * currentDt;

              // Average speed during this fractional step (m/s)
              double avgSpeedMs = ((intervalStartSpeed / 3.6) + (newSpeedKmh / 3.6)) / 2;
              double initialDistance = avgSpeedMs * elapsedOffset;

              RaceMetrics simulated = current.copyWith(
                isRunning: true,
                elapsedTime: elapsedOffset,
                distanceMeters: initialDistance,
                speedKmh: newSpeedKmh,
                gForce: current.gForce,
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
                    gForce: current.gForce,
                    altitude: currentAltitude,
                  ),
                ],
              );

              _speedBuffer.clear();
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

        return _integrateDrag(current, newSpeedKmh, currentAltitude, currentDt);
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
  ) {
    final currentSpeedMs = current.speedKmh / 3.6;
    final newSpeedMs = newSpeedKmh / 3.6;

    // Trapezoidal integration for distance
    final avgSpeedMs = (currentSpeedMs + newSpeedMs) / 2;
    final double deltaDistance = avgSpeedMs * currentDt;
    final double newDistance = current.distanceMeters + deltaDistance;

    final double smoothedGForce = current.gForce;
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

    // Speed intervals
    double? t60_130 = current.time60to130mph;
    double? t100_200 = current.time100to200kmh;
    double? t0_130mph = current.time0to130mph;
    double? t0_200kmh = current.time0to200kmh;

    final double startAltitude = current.startAltitude ?? currentAltitude;

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
    double currentAltitude, {
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

    final double smoothedGForce = current.gForce;
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
    if (newSpeedKmh > launchCommitThreshold && _speedBuffer.length >= 2) {
      int k = _speedBuffer.length - 1;
      int crossingIndex = -1;

      // Scan backwards to find the most recent zero-crossing transition
      for (int j = k - 1; j >= 0; j--) {
        if (_speedBuffer[j] <= zeroCrossingThreshold &&
            _speedBuffer[j + 1] > zeroCrossingThreshold) {
          crossingIndex = j;
          break;
        }
      }

      if (crossingIndex != -1) {
        double vStart = _speedBuffer[crossingIndex];
        double vEnd = _speedBuffer[crossingIndex + 1];
        double startFraction =
            (zeroCrossingThreshold - vStart) / (vEnd - vStart);

        // Time offset from the crossing point to the current tick
        double elapsedOffset = (k - crossingIndex - startFraction) * currentDt;

        // Integrate distance for the first fractional step
        double firstStepTime = currentDt * (1.0 - startFraction);
        double avgSpeedMs =
            ((zeroCrossingThreshold / 3.6) + (vEnd / 3.6)) / 2;
        double initialDistance = avgSpeedMs * firstStepTime;

        // Integrate distance for all subsequent steps
        for (int j = crossingIndex + 1; j < k; j++) {
          double stepAvgSpeedMs =
              ((_speedBuffer[j] / 3.6) + (_speedBuffer[j + 1] / 3.6)) / 2;
          initialDistance += stepAvgSpeedMs * currentDt;
        }

        List<DataPoint> initialHistory = [];
        // Zero crossing point
        initialHistory.add(DataPoint(
          elapsedTime: 0.0,
          speedKmh: zeroCrossingThreshold,
          gForce: current.gForce,
          altitude: currentAltitude,
        ));

        // Points from crossingIndex + 1 to k
        for (int j = crossingIndex + 1; j <= k; j++) {
          double tJ = firstStepTime + (j - (crossingIndex + 1)) * currentDt;
          initialHistory.add(DataPoint(
            elapsedTime: tJ,
            speedKmh: _speedBuffer[j],
            gForce: current.gForce,
            altitude: currentAltitude,
          ));
        }

        RaceMetrics simulated = current.copyWith(
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

        _speedBuffer.clear();
        return simulated;
      }
    }
    return null;
  }

  RaceMetrics reset() {
    _speedBuffer.clear();
    _stoppedTicks = 0;
    _rejectedCount = 0;
    _lastGpsTimeSeconds = null;
    _lastValidDt = null;
    return RaceMetrics();
  }
}

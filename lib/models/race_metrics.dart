class DataPoint {
  final double elapsedTime;
  final double speedKmh;
  final double gForce;
  final double? altitude; // Elevation in meters

  const DataPoint({
    required this.elapsedTime,
    required this.speedKmh,
    required this.gForce,
    this.altitude,
  });

  Map<String, dynamic> toJson() {
    return {
      'elapsedTime': elapsedTime,
      'speedKmh': speedKmh,
      'gForce': gForce,
      'altitude': altitude,
    };
  }

  factory DataPoint.fromJson(Map<String, dynamic> json) {
    return DataPoint(
      elapsedTime: (json['elapsedTime'] as num).toDouble(),
      speedKmh: (json['speedKmh'] as num).toDouble(),
      gForce: (json['gForce'] as num).toDouble(),
      altitude: json['altitude'] != null
          ? (json['altitude'] as num).toDouble()
          : null,
    );
  }
}

class RaceMetrics {
  final double speedKmh;
  final double distanceMeters;
  final double gForce;
  final double elapsedTime;

  // Timers (in seconds)
  final double? time60ft;
  final double? time0to60mph;
  final double? time0to100kmh;
  final double? time18Mile;
  final double? trap18Mile; // Trap speed in km/h
  final double? time1000ft;
  final double? trap1000ft; // Trap speed in km/h
  final double? time14Mile;
  final double? trap14Mile; // Trap speed in km/h
  final double? time12Mile;
  final double? trap12Mile; // Trap speed in km/h

  // Rollout Timers (in seconds)
  final double? rolloutTime1ft;
  final double? time60ftRollout;
  final double? time0to60mphRollout;
  final double? time0to100kmhRollout;
  final double? time18MileRollout;
  final double? time1000ftRollout;
  final double? time14MileRollout;
  final double? time12MileRollout;

  // Speed intervals (in seconds)
  final double? time60to130mph;
  final double? time100to200kmh;
  final double? time0to130mph;
  final double? time0to200kmh;

  // Elevation
  final double? startAltitude; // Start elevation in meters

  // Mode & Target Info
  final String? runMode; // 'drag' or 'interval'
  final double? targetDistance;
  final String? targetDistanceUnit;
  final double? targetStartSpeed;
  final double? targetEndSpeed;
  final String? targetSpeedUnit;

  final bool isRunning;
  final List<DataPoint> history;

  RaceMetrics({
    this.speedKmh = 0.0,
    this.distanceMeters = 0.0,
    this.gForce = 0.0,
    this.elapsedTime = 0.0,
    this.time60ft,
    this.time0to60mph,
    this.time0to100kmh,
    this.time18Mile,
    this.trap18Mile,
    this.time1000ft,
    this.trap1000ft,
    this.time14Mile,
    this.trap14Mile,
    this.time12Mile,
    this.trap12Mile,
    this.rolloutTime1ft,
    this.time60ftRollout,
    this.time0to60mphRollout,
    this.time0to100kmhRollout,
    this.time18MileRollout,
    this.time1000ftRollout,
    this.time14MileRollout,
    this.time12MileRollout,
    this.time60to130mph,
    this.time100to200kmh,
    this.time0to130mph,
    this.time0to200kmh,
    this.startAltitude,
    this.runMode,
    this.targetDistance,
    this.targetDistanceUnit,
    this.targetStartSpeed,
    this.targetEndSpeed,
    this.targetSpeedUnit,
    this.isRunning = false,
    this.history = const [],
  });

  RaceMetrics copyWith({
    double? speedKmh,
    double? distanceMeters,
    double? gForce,
    double? elapsedTime,
    double? time60ft,
    double? time0to60mph,
    double? time0to100kmh,
    double? time18Mile,
    double? trap18Mile,
    double? time1000ft,
    double? trap1000ft,
    double? time14Mile,
    double? trap14Mile,
    double? time12Mile,
    double? trap12Mile,
    double? rolloutTime1ft,
    double? time60ftRollout,
    double? time0to60mphRollout,
    double? time0to100kmhRollout,
    double? time18MileRollout,
    double? time1000ftRollout,
    double? time14MileRollout,
    double? time12MileRollout,
    double? time60to130mph,
    double? time100to200kmh,
    double? time0to130mph,
    double? time0to200kmh,
    double? startAltitude,
    String? runMode,
    double? targetDistance,
    String? targetDistanceUnit,
    double? targetStartSpeed,
    double? targetEndSpeed,
    String? targetSpeedUnit,
    bool? isRunning,
    List<DataPoint>? history,
  }) {
    return RaceMetrics(
      speedKmh: speedKmh ?? this.speedKmh,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      gForce: gForce ?? this.gForce,
      elapsedTime: elapsedTime ?? this.elapsedTime,
      time60ft: time60ft ?? this.time60ft,
      time0to60mph: time0to60mph ?? this.time0to60mph,
      time0to100kmh: time0to100kmh ?? this.time0to100kmh,
      time18Mile: time18Mile ?? this.time18Mile,
      trap18Mile: trap18Mile ?? this.trap18Mile,
      time1000ft: time1000ft ?? this.time1000ft,
      trap1000ft: trap1000ft ?? this.trap1000ft,
      time14Mile: time14Mile ?? this.time14Mile,
      trap14Mile: trap14Mile ?? this.trap14Mile,
      time12Mile: time12Mile ?? this.time12Mile,
      trap12Mile: trap12Mile ?? this.trap12Mile,
      rolloutTime1ft: rolloutTime1ft ?? this.rolloutTime1ft,
      time60ftRollout: time60ftRollout ?? this.time60ftRollout,
      time0to60mphRollout: time0to60mphRollout ?? this.time0to60mphRollout,
      time0to100kmhRollout: time0to100kmhRollout ?? this.time0to100kmhRollout,
      time18MileRollout: time18MileRollout ?? this.time18MileRollout,
      time1000ftRollout: time1000ftRollout ?? this.time1000ftRollout,
      time14MileRollout: time14MileRollout ?? this.time14MileRollout,
      time12MileRollout: time12MileRollout ?? this.time12MileRollout,
      time60to130mph: time60to130mph ?? this.time60to130mph,
      time100to200kmh: time100to200kmh ?? this.time100to200kmh,
      time0to130mph: time0to130mph ?? this.time0to130mph,
      time0to200kmh: time0to200kmh ?? this.time0to200kmh,
      startAltitude: startAltitude ?? this.startAltitude,
      runMode: runMode ?? this.runMode,
      targetDistance: targetDistance ?? this.targetDistance,
      targetDistanceUnit: targetDistanceUnit ?? this.targetDistanceUnit,
      targetStartSpeed: targetStartSpeed ?? this.targetStartSpeed,
      targetEndSpeed: targetEndSpeed ?? this.targetEndSpeed,
      targetSpeedUnit: targetSpeedUnit ?? this.targetSpeedUnit,
      isRunning: isRunning ?? this.isRunning,
      history: history ?? this.history,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'speedKmh': speedKmh,
      'distanceMeters': distanceMeters,
      'gForce': gForce,
      'elapsedTime': elapsedTime,
      'time60ft': time60ft,
      'time0to60mph': time0to60mph,
      'time0to100kmh': time0to100kmh,
      'time18Mile': time18Mile,
      'trap18Mile': trap18Mile,
      'time1000ft': time1000ft,
      'trap1000ft': trap1000ft,
      'time14Mile': time14Mile,
      'trap14Mile': trap14Mile,
      'time12Mile': time12Mile,
      'trap12Mile': trap12Mile,
      'rolloutTime1ft': rolloutTime1ft,
      'time60ftRollout': time60ftRollout,
      'time0to60mphRollout': time0to60mphRollout,
      'time0to100kmhRollout': time0to100kmhRollout,
      'time18MileRollout': time18MileRollout,
      'time1000ftRollout': time1000ftRollout,
      'time14MileRollout': time14MileRollout,
      'time12MileRollout': time12MileRollout,
      'time60to130mph': time60to130mph,
      'time100to200kmh': time100to200kmh,
      'time0to130mph': time0to130mph,
      'time0to200kmh': time0to200kmh,
      'startAltitude': startAltitude,
      'runMode': runMode,
      'targetDistance': targetDistance,
      'targetDistanceUnit': targetDistanceUnit,
      'targetStartSpeed': targetStartSpeed,
      'targetEndSpeed': targetEndSpeed,
      'targetSpeedUnit': targetSpeedUnit,
      'history': history.map((e) => e.toJson()).toList(),
    };
  }

  factory RaceMetrics.fromJson(Map<String, dynamic> json) {
    return RaceMetrics(
      speedKmh: (json['speedKmh'] as num).toDouble(),
      distanceMeters: (json['distanceMeters'] as num).toDouble(),
      gForce: (json['gForce'] as num).toDouble(),
      elapsedTime: (json['elapsedTime'] as num).toDouble(),
      time60ft: json['time60ft'] != null
          ? (json['time60ft'] as num).toDouble()
          : null,
      time0to60mph: json['time0to60mph'] != null
          ? (json['time0to60mph'] as num).toDouble()
          : null,
      time0to100kmh: json['time0to100kmh'] != null
          ? (json['time0to100kmh'] as num).toDouble()
          : null,
      time18Mile: json['time18Mile'] != null
          ? (json['time18Mile'] as num).toDouble()
          : null,
      trap18Mile: json['trap18Mile'] != null
          ? (json['trap18Mile'] as num).toDouble()
          : null,
      time1000ft: json['time1000ft'] != null
          ? (json['time1000ft'] as num).toDouble()
          : null,
      trap1000ft: json['trap1000ft'] != null
          ? (json['trap1000ft'] as num).toDouble()
          : null,
      time14Mile: json['time14Mile'] != null
          ? (json['time14Mile'] as num).toDouble()
          : null,
      trap14Mile: json['trap14Mile'] != null
          ? (json['trap14Mile'] as num).toDouble()
          : null,
      time12Mile: json['time12Mile'] != null
          ? (json['time12Mile'] as num).toDouble()
          : null,
      trap12Mile: json['trap12Mile'] != null
          ? (json['trap12Mile'] as num).toDouble()
          : null,
      rolloutTime1ft: json['rolloutTime1ft'] != null
          ? (json['rolloutTime1ft'] as num).toDouble()
          : null,
      time60ftRollout: json['time60ftRollout'] != null
          ? (json['time60ftRollout'] as num).toDouble()
          : null,
      time0to60mphRollout: json['time0to60mphRollout'] != null
          ? (json['time0to60mphRollout'] as num).toDouble()
          : null,
      time0to100kmhRollout: json['time0to100kmhRollout'] != null
          ? (json['time0to100kmhRollout'] as num).toDouble()
          : null,
      time18MileRollout: json['time18MileRollout'] != null
          ? (json['time18MileRollout'] as num).toDouble()
          : null,
      time1000ftRollout: json['time1000ftRollout'] != null
          ? (json['time1000ftRollout'] as num).toDouble()
          : null,
      time14MileRollout: json['time14MileRollout'] != null
          ? (json['time14MileRollout'] as num).toDouble()
          : null,
      time12MileRollout: json['time12MileRollout'] != null
          ? (json['time12MileRollout'] as num).toDouble()
          : null,
      time60to130mph: json['time60to130mph'] != null
          ? (json['time60to130mph'] as num).toDouble()
          : null,
      time100to200kmh: json['time100to200kmh'] != null
          ? (json['time100to200kmh'] as num).toDouble()
          : null,
      time0to130mph: json['time0to130mph'] != null
          ? (json['time0to130mph'] as num).toDouble()
          : null,
      time0to200kmh: json['time0to200kmh'] != null
          ? (json['time0to200kmh'] as num).toDouble()
          : null,
      startAltitude: json['startAltitude'] != null
          ? (json['startAltitude'] as num).toDouble()
          : null,
      runMode: json['runMode'] as String?,
      targetDistance: json['targetDistance'] != null
          ? (json['targetDistance'] as num).toDouble()
          : null,
      targetDistanceUnit: json['targetDistanceUnit'] as String?,
      targetStartSpeed: json['targetStartSpeed'] != null
          ? (json['targetStartSpeed'] as num).toDouble()
          : null,
      targetEndSpeed: json['targetEndSpeed'] != null
          ? (json['targetEndSpeed'] as num).toDouble()
          : null,
      targetSpeedUnit: json['targetSpeedUnit'] as String?,
      isRunning: false,
      history: (json['history'] as List? ?? [])
          .map((e) => DataPoint.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }
}

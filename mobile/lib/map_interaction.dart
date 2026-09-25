import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';

/// Lets an embedded native map win the gesture arena against surrounding
/// scroll views. Without this, vertical and diagonal drags can feel sticky.
Set<Factory<OneSequenceGestureRecognizer>> mapGestureRecognizers() =>
    <Factory<OneSequenceGestureRecognizer>>{
      Factory<EagerGestureRecognizer>(EagerGestureRecognizer.new),
    };

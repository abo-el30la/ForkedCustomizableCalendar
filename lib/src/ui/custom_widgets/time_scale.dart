import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_customizable_calendar/src/ui/themes/themes.dart';
import 'package:flutter_customizable_calendar/src/utils/utils.dart';

/// It displays a time scale of a day view (with hours and minutes marks).
class TimeScale extends StatefulWidget {
  /// Creates view of a time scale.
  const TimeScale({
    super.key,
    this.showCurrentTimeMark = true,
    this.isArabic = false,
    this.theme = const TimeScaleTheme(),
  });

  /// Whether current time mark needs to be shown
  final bool showCurrentTimeMark;

  /// Customization params for the view
  final TimeScaleTheme theme;

  final bool isArabic;

  @override
  State<TimeScale> createState() => _TimeScaleState();
}

class _TimeScaleState extends State<TimeScale> {
  final _clock = ClockNotifier.instance();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(
        widget.theme.width,
        widget.theme.hourExtent * Duration.hoursPerDay,
      ),
      painter: _scale,
      foregroundPainter: widget.showCurrentTimeMark ? _currentTimeMark : null,
    );
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  CustomPainter get _scale => _ScalePainter(
        dayDate: _clock.value,
        theme: widget.theme,
        isArabic: widget.isArabic,
      );

  CustomPainter get _currentTimeMark => _CurrentTimeMarkPainter(
        currentTime: _clock,
        theme: widget.theme.currentTimeMarkTheme,
        isArabic: widget.isArabic,
      );
}

class _ScalePainter extends CustomPainter {
  const _ScalePainter({
    required this.dayDate,
    required this.theme,
    required this.isArabic,
  });

  final DateTime dayDate;

  final TimeScaleTheme theme;

  final bool isArabic;

  @override
  void paint(Canvas canvas, Size size) {
    final hourExtent = size.height / Duration.hoursPerDay;
    // print('paint - hourExtent: $hourExtent');
    final quarterHeight = hourExtent / 4;

    for (var hour = 0; hour < Duration.hoursPerDay; hour += 1) {
      final time = DateTime(
        dayDate.year,
        dayDate.month,
        dayDate.day,
        hour,
      );
      final hourTextPainter = TextPainter(
        text: TextSpan(
          text: theme.hourFormatter.call(time),
          style: theme.textStyle,
        ),
        textAlign: _textAlign,
        textDirection: TextDirection.ltr,
      );
      final hourOffset = hourExtent * hour;
      // print('paint - hourOffset: $hourOffset');
      // Draw an hour text
      hourTextPainter
        ..layout(
          minWidth: size.width,
          maxWidth: size.width,
        )
        ..paint(
          canvas,
          Offset(-1, hourOffset - hourTextPainter.height / 2),
        );
      // print('paint - hourTextPainter.height: ${hourTextPainter.height}');
      // Draw a line next to the hour text
      canvas.drawLine(
        Offset(isArabic ? size.width - 55 : size.width, hourOffset),
        Offset(
          isArabic ? canvas.getDestinationClipBounds().left : canvas.getDestinationClipBounds().right,
          hourOffset,
        ),
        Paint()
          ..color = const Color(0xff8C8F90)
          ..strokeWidth = 0.2,
      );

      if (theme.drawHalfHourMarks) {
        // Draw a half-hour time text
        final halfHourTime = DateTime(
          dayDate.year,
          dayDate.month,
          dayDate.day,
          hour,
          30,
        );
        final halfHourTextPainter = TextPainter(
          text: TextSpan(
            text: theme.hourFormatter.call(halfHourTime),
            style: theme.textStyle,
          ),
          textAlign: _textAlign,
          textDirection: TextDirection.ltr,
        );
        final halfHourOffset = hourOffset + quarterHeight * 2;

        halfHourTextPainter
          ..layout(
            minWidth: size.width,
            maxWidth: size.width,
          )
          ..paint(
            canvas,
            Offset(-1, halfHourOffset - halfHourTextPainter.height / 2),
          );

        // Draw a line next to the half-hour text
        canvas.drawLine(
          Offset(isArabic ? size.width - 55 : size.width, halfHourOffset),
          Offset(
            isArabic ? canvas.getDestinationClipBounds().left : canvas.getDestinationClipBounds().right,
            halfHourOffset,
          ),
          Paint()
            ..color = const Color(0xff8C8F90)
            ..strokeWidth = 0.5,
        );
      }

      if (theme.drawQuarterHourMarks) {
        final line = theme.quarterHourMarkTheme;
        final dx = _calculateLineDx(size.width, line.length);
        final dy1 = hourOffset + quarterHeight - line.strokeWidth / 2;
        final dy2 = hourOffset + quarterHeight * 3 - line.strokeWidth / 2;

        canvas
          ..drawLine(
            Offset(dx, dy1),
            Offset(dx + line.length, dy1),
            line.painter,
          )
          ..drawLine(
            Offset(dx, dy2),
            Offset(dx + line.length, dy2),
            line.painter,
          );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ScalePainter oldDelegate) => theme != oldDelegate.theme || dayDate != oldDelegate.dayDate;

  TextAlign get _textAlign {
    switch (theme.marksAlign) {
      case MarksAlign.center:
        return TextAlign.center;
      case MarksAlign.left:
        return TextAlign.left;
      case MarksAlign.right:
        return TextAlign.right;
    }
  }

  double _calculateLineDx(double canvasWidth, double lineLength) {
    switch (theme.marksAlign) {
      case MarksAlign.center:
        return (canvasWidth - lineLength) / 2;
      case MarksAlign.left:
        return 0;
      case MarksAlign.right:
        return canvasWidth - lineLength;
    }
  }
}

class _CurrentTimeMarkPainter extends CustomPainter {
  const _CurrentTimeMarkPainter({
    required this.currentTime,
    required this.theme,
    required this.isArabic,
  }) : super(repaint: currentTime);

  final ValueListenable<DateTime> currentTime;

  final TimeMarkTheme theme;

  final bool isArabic;

  @override
  void paint(Canvas canvas, Size size) {
    final secondExtent = size.height / Duration.secondsPerDay;
    final dayDate = DateUtils.dateOnly(currentTime.value);
    final timeDiff = currentTime.value.difference(dayDate);
    final currentTimeOffset = timeDiff.inSeconds * secondExtent;
    final dy = currentTimeOffset - theme.strokeWidth / 2;

    const circleRadius = 5.0; // adjust the radius of the circle as needed

    // final circleCenter = Offset(0, dy); // center point of the circle
    final circleCenter = Offset(3 + circleRadius, dy); // center point of the circle with padding
    // // draw current time mark depending on language
    canvas.drawCircle(
      Offset(isArabic ? size.width - (circleCenter.dx - 3) : circleCenter.dx, circleCenter.dy),
      circleRadius,
      Paint()..color = theme.color,
    );
    canvas
      //..drawCircle(circleCenter, circleRadius, theme.painter)
      ..drawLine(
        Offset(isArabic ? size.width - (theme.length) : 5, dy),
        Offset(isArabic ? size.width : theme.length, dy),
        theme.painter,
      );
  }

  @override
  bool shouldRepaint(covariant _CurrentTimeMarkPainter oldDelegate) => theme != oldDelegate.theme || currentTime != oldDelegate.currentTime;
}

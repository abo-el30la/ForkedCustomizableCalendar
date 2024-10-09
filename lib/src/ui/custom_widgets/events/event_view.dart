import 'package:flutter/material.dart';
import 'package:flutter_customizable_calendar/src/domain/models/models.dart';
import 'package:flutter_customizable_calendar/src/ui/custom_widgets/events/events.dart';
import 'package:flutter_customizable_calendar/src/ui/custom_widgets/events/simple_all_day_event_view.dart';
import 'package:flutter_customizable_calendar/src/ui/themes/themes.dart';
import 'package:flutter_customizable_calendar/src/utils/enums.dart';

/// Wrapper for all [CalendarEvent] views. It needs to unify
/// their main views parameters (like elevation, shape, margin).
class EventView<T extends CalendarEvent> extends StatelessWidget {
  /// Creates a view of given [event].
  const EventView(
    this.event, {
    required this.viewType,
    this.theme = const FloatingEventsTheme(),
    this.allDayEventsTheme = const AllDayEventsTheme(),
    super.key,
    this.onTap,
    this.eventBuilders = const {},
  });

  /// Custom event builders
  final Map<Type, EventBuilder> eventBuilders;

  /// Calendar event
  final T event;

  /// Customization parameters of the view
  final FloatingEventsTheme theme;

  /// Theme which allows to customize all day events
  final AllDayEventsTheme allDayEventsTheme;

  final CalendarView viewType;

  /// On event view tap callback
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (event is AllDayCalendarEvent) {
      return Card(
        color: Colors.transparent,
        elevation: allDayEventsTheme.elevation,
        shape: allDayEventsTheme.shape,
        borderOnForeground: false,
        margin: allDayEventsTheme.margin,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Builder(
            builder: _getEventBuilder(event.runtimeType),
          ),
        ),
      );
    }

    // TODO : This Event Card
    return Card(
      color: event.color,
      elevation: theme.elevation,
      shape: theme.shape,
      borderOnForeground: false,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Builder(
          builder: _getEventBuilder(event.runtimeType),
        ),
      ),
    );
  }

  WidgetBuilder _getEventBuilder(Type type) {
    if (eventBuilders[type] == null) {
      return _createBody[type]!;
    }

    return (context) {
      return eventBuilders[type]!.call(context, event);
    };
  }

  Map<Type, WidgetBuilder> get _createBody => {
        SimpleEvent: (context) => SimpleEventView(
              event as SimpleEvent,
              theme: _viewEventTheme,
              viewType: viewType,
            ),
        TaskDue: (context) => TaskDueView(
              event as TaskDue,
              viewType: viewType,
              theme: _viewEventTheme,
            ),
        SimpleAllDayEvent: (context) => SimpleAllDayEventView(
              event as SimpleAllDayEvent,
              theme: allDayEventsTheme,
              viewType: viewType,
            ),
      };

  ViewEventTheme get _viewEventTheme {
    switch (viewType) {
      case CalendarView.days:
        return theme.dayTheme;
      case CalendarView.week:
        return theme.weekTheme;
      case CalendarView.month:
        return theme.monthTheme;
      case CalendarView.scheduleList:
        return theme.dayTheme;
    }
  }
}

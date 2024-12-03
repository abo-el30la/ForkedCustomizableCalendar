import 'dart:async';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_customizable_calendar/src/domain/models/models.dart';
import 'package:flutter_customizable_calendar/src/ui/controllers/controllers.dart';
import 'package:flutter_customizable_calendar/src/ui/custom_widgets/all_days_events_list.dart';
import 'package:flutter_customizable_calendar/src/ui/custom_widgets/custom_widgets.dart';
import 'package:flutter_customizable_calendar/src/ui/themes/themes.dart';
import 'package:flutter_customizable_calendar/src/utils/utils.dart';

/// A key holder of all DaysView keys
@visibleForTesting
abstract class DaysViewKeys {
  /// A key for the timeline view
  static final timeline = GlobalKey();

  /// Map of keys for the events layouts (by day date)
  static final layouts = <DateTime, GlobalKey>{};

  /// Map of keys for the displayed events (by event object)
  static final events = <CalendarEvent, GlobalKey>{};
}

/// Days view displays a timeline and has ability to move to a specific date.
class DaysView<T extends FloatingCalendarEvent> extends StatefulWidget {
  /// Creates a Days view, Parameters [controller]
  const DaysView({
    required this.controller,
    super.key,
    this.saverConfig,
    this.overrideOnEventLongPress,
    this.monthPickerTheme = const DisplayedPeriodPickerTheme(),
    this.monthPickerBuilder,
    this.daysListTheme = const DaysListTheme(),
    this.daysListBuilder,
    this.timelineTheme = const TimelineTheme(),
    this.floatingEventTheme = const FloatingEventsTheme(),
    this.allDayEventsTheme = const AllDayEventsTheme(),
    this.breaks = const [],
    this.events = const [],
    this.eventBuilders = const {},
    this.onDateLongPress,
    this.onEventTap,
    this.onEventUpdated,
    this.onDiscardChanges,
    this.allDayEventsShowMoreBuilder,
    this.onAllDayEventsShowMoreTap,
    this.onAllDayEventTap,
    this.enableFloatingEvents = true,
  });

  /// Controller which allows to control the view
  final DaysViewController controller;

  /// The month picker customization params
  /// Works only if [monthPickerBuilder] not specified
  final DisplayedPeriodPickerTheme monthPickerTheme;

  /// The builder for the month picker
  /// @events - the events which are displayed on the timeline
  /// @focusedDate - the date which is currently focused
  final Widget Function(
    BuildContext,
    DateTime focusedDate,
    List<T> events,
  )? monthPickerBuilder;

  /// The days list customization params
  /// Works only if [daysListBuilder] not specified
  final DaysListTheme daysListTheme;

  /// The builder for the days list
  final Widget Function(
    BuildContext context,

    /// the date which is currently focused
    DateTime focusedDate,

    ///  the events which are displayed on the timeline
    List<T> events,
  )? daysListBuilder;

  /// The timeline customization params
  final TimelineTheme timelineTheme;

  /// Floating events customization params
  final FloatingEventsTheme floatingEventTheme;

  /// All day events theme
  final AllDayEventsTheme allDayEventsTheme;

  /// On all day events show more tap callback
  final void Function(
    List<AllDayCalendarEvent> visibleEvents,
    List<AllDayCalendarEvent> events,
  )? onAllDayEventsShowMoreTap;

  /// On all day event tap callback
  final void Function(AllDayCalendarEvent event)? onAllDayEventTap;

  /// Builder for all day events show more button
  final Widget Function(
    BuildContext context,
    List<AllDayCalendarEvent> visibleEvents,
    List<AllDayCalendarEvent> events,
  )? allDayEventsShowMoreBuilder;

  /// Breaks list to display
  final List<Break> breaks;

  /// Events list to display
  final List<T> events;

  /// Event builders
  final Map<Type, EventBuilder> eventBuilders;

  /// Returns selected timestamp
  final Future<CalendarEvent?> Function(DateTime)? onDateLongPress;

  /// Overrides the default behavior of the event view's long press
  final void Function(LongPressStartDetails details, T event)? overrideOnEventLongPress;

  /// Returns the tapped event
  final void Function(T)? onEventTap;

  /// Is called after an event is modified by user
  final void Function(T)? onEventUpdated;

  /// Is called after user discards changes for event
  final void Function(T)? onDiscardChanges;

  /// Properties for widget which is used to save edited event
  final SaverConfig? saverConfig;

  /// enable floating events
  ///
  /// If true, floating events will be saved
  /// after the user clicks the save button
  ///
  /// If false, floating events will be saved
  /// as soon as the user releases the tap
  ///
  /// Note: if set to false, the user will not be able to
  /// change the size of floating events
  final bool enableFloatingEvents;

  @override
  State<DaysView<T>> createState() => _DaysViewState<T>();
}

class _DaysViewState<T extends FloatingCalendarEvent> extends State<DaysView<T>> with SingleTickerProviderStateMixin {
  final _overlayKey = GlobalKey<DraggableEventOverlayState<T>>();
  final _elevatedEvent = FloatingEventNotifier<T>();
  late final PageController _monthPickerController;
  late final ScrollController _timelineController;
  var _pointerLocation = Offset.zero;
  var _scrolling = false;
  ScrollController? _daysListController;

  static DateTime get _now => clock.now();

  DateTime get _initialDate => widget.controller.initialDate;

  DateTime? get _endDate => widget.controller.endDate;

  DateTime get _displayedDate => widget.controller.state.displayedDate;

  double get _minuteExtent => _hourExtent / Duration.minutesPerHour;

  double get _hourExtent => widget.timelineTheme.timeScaleTheme.hourExtent;

  double get _dayExtent => _hourExtent * Duration.hoursPerDay;

  RenderBox? _getTimelineBox() => DaysViewKeys.timeline.currentContext?.findRenderObject() as RenderBox?;

  RenderBox? _getLayoutBox(DateTime dayDate) =>
      DaysViewKeys.layouts[dayDate]?.currentContext?.findRenderObject() as RenderBox?;

  RenderBox? _getEventBox(T event) => DaysViewKeys.events[event]?.currentContext?.findRenderObject() as RenderBox?;

  List<AllDayCalendarEvent> get _allDayEvents => widget.events.whereType<AllDayCalendarEvent>().toList();

  List<T> get _events => widget.events.where((event) => event is! AllDayCalendarEvent).toList();

  void _stopTimelineScrolling() => _timelineController.jumpTo(_timelineController.offset);

  Future<void> _scrollIfNecessary() async {
    final timelineBox = _getTimelineBox();

    _scrolling = timelineBox != null;

    if (!_scrolling) return; // Scrollable isn't found

    final fingerPosition = timelineBox!.globalToLocal(_pointerLocation);
    final timelineScrollPosition = _timelineController.position;
    var timelineScrollOffset = timelineScrollPosition.pixels;

    const detectionArea = 25;
    const moveDistance = 25;

    if (fingerPosition.dy > timelineBox.size.height - detectionArea &&
        timelineScrollOffset < timelineScrollPosition.maxScrollExtent) {
      timelineScrollOffset = min(
        timelineScrollOffset + moveDistance,
        timelineScrollPosition.maxScrollExtent,
      );
    } else if (fingerPosition.dy < detectionArea && timelineScrollOffset > timelineScrollPosition.minScrollExtent) {
      timelineScrollOffset = max(
        timelineScrollOffset - moveDistance,
        timelineScrollPosition.minScrollExtent,
      );
    } else {
      _scrolling = false;
      return;
    }

    await timelineScrollPosition.animateTo(
      timelineScrollOffset,
      duration: const Duration(milliseconds: 100),
      curve: Curves.linear,
    );

    if (_scrolling) await _scrollIfNecessary();
  }

  void _stopAutoScrolling() {
    _stopTimelineScrolling();
    _scrolling = false;
  }

  void _autoScrolling(DragUpdateDetails details) {
    _pointerLocation = details.globalPosition;
    if (!_scrolling) _scrollIfNecessary();
  }

  void _updateFocusedDate() {
    final daysOffset = _timelineController.offset ~/ _dayExtent;
    final displayedDay = DateUtils.addDaysToDate(_initialDate, daysOffset);
    final offsetInMinutes = (_timelineController.offset % _minuteExtent).truncate();
    final displayedDate = displayedDay.add(Duration(minutes: offsetInMinutes));

    widget.controller.setFocusedDate(displayedDate);
  }

  int _getMonthsDeltaForDate(DateTime date) => DateUtils.monthDelta(_initialDate, date);

  double _getDaysListOffsetForDate(DateTime date) => min(
        (date.day - 1) * widget.daysListTheme.itemExtent,
        _daysListController!.position.maxScrollExtent,
      );

  double _getTimelineOffsetForDate(DateTime date) {
    final timeZoneDiff = date.timeZoneOffset - _initialDate.timeZoneOffset;
    final timeDiff = date.difference(_initialDate) + timeZoneDiff;
    return timeDiff.inHours * _hourExtent;
  }

  @override
  void initState() {
    super.initState();
    _monthPickerController = PageController(
      initialPage: DateUtils.monthDelta(_initialDate, _displayedDate),
    );
    _timelineController = ScrollController(
      initialScrollOffset: _getTimelineOffsetForDate(_displayedDate),
    )..addListener(_updateFocusedDate);
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<DaysViewController, DaysViewState>(
      bloc: widget.controller,
      listener: (context, state) {
        if (state is DaysViewDaySelected || state is DaysViewCurrentDateIsSet) {
          final timelineOffset = _getTimelineOffsetForDate(_displayedDate);

          if (timelineOffset != _timelineController.offset) {
            _timelineController
              ..removeListener(_updateFocusedDate)
              ..animateTo(
                timelineOffset,
                duration: const Duration(milliseconds: 450),
                curve: Curves.fastLinearToSlowEaseIn,
              ).whenComplete(() {
                // Checking if scroll is finished
                if (!_timelineController.position.isScrollingNotifier.value) {
                  _timelineController.addListener(_updateFocusedDate);
                }
              });
          }

          if (state is DaysViewCurrentDateIsSet) {
            // Reset displayed month

            if (widget.monthPickerBuilder == null) {
              final displayedMonth = _getMonthsDeltaForDate(_displayedDate);

              if (displayedMonth != _monthPickerController.page?.round()) {
                // Switch displayed month
                _monthPickerController.animateToPage(
                  displayedMonth,
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.linear,
                );
              }
            }

            if (widget.daysListBuilder != null) {
              final daysListOffset = _getDaysListOffsetForDate(_displayedDate);

              if (daysListOffset != _daysListController!.offset) {
                _daysListController!.animateTo(
                  daysListOffset,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.fastLinearToSlowEaseIn,
                );
              }
            }
          }
        } else if (state is DaysViewFocusedDateIsSet) {
          // User scrolls a timeline
          final focusedDate = state.focusedDate;

          if (widget.monthPickerBuilder == null) {
            final displayedMonth = _getMonthsDeltaForDate(focusedDate);

            if (displayedMonth != _monthPickerController.page?.round()) {
              // Switch displayed month
              _monthPickerController.animateToPage(
                displayedMonth,
                duration: const Duration(milliseconds: 150),
                curve: Curves.linear,
              );
            }
          }

          if (widget.daysListBuilder == null) {
            final daysListOffset = _getDaysListOffsetForDate(focusedDate);

            if (daysListOffset != _daysListController!.offset) {
              _daysListController!.animateTo(
                daysListOffset,
                duration: const Duration(milliseconds: 100),
                curve: Curves.linear,
              );
            }
          }
        } else if (state is DaysViewNextMonthSelected || state is DaysViewPrevMonthSelected) {
          _stopTimelineScrolling();
          // Change a displayed month
          if (widget.daysListBuilder == null) {
            _monthPickerController.animateToPage(
              _getMonthsDeltaForDate(state.displayedDate),
              duration: const Duration(milliseconds: 450),
              curve: Curves.fastLinearToSlowEaseIn,
            );
          }
        }
      },
      child: Column(
        children: [
          _monthPicker(),
          _daysList(),
          _buildAllDayEvents(),
          Expanded(
            child: DraggableEventOverlay<T>(
              _elevatedEvent,
              key: _overlayKey,
              enableFloatingEvents: widget.enableFloatingEvents,
              onEventLongPressStart: widget.overrideOnEventLongPress,
              viewType: CalendarView.days,
              eventBuilders: widget.eventBuilders,
              timelineTheme: widget.timelineTheme,
              onDateLongPress: _onDateLongPress,
              onDragDown: _stopTimelineScrolling,
              onDragUpdate: _autoScrolling,
              onDragEnd: _stopAutoScrolling,
              onSizeUpdate: _autoScrolling,
              onResizingEnd: _stopAutoScrolling,
              onDropped: widget.onDiscardChanges,
              onChanged: widget.onEventUpdated,
              getTimelineBox: _getTimelineBox,
              getLayoutBox: _getLayoutBox,
              getEventBox: _getEventBox,
              saverConfig: widget.saverConfig ?? SaverConfig.def(),
              child: _timeline(),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _elevatedEvent.dispose();
    _monthPickerController.dispose();
    _daysListController?.dispose();
    _timelineController.dispose();
    super.dispose();
  }

  Widget _monthPicker() => BlocBuilder<DaysViewController, DaysViewState>(
        bloc: widget.controller,
        builder: (context, state) {
          if (widget.monthPickerBuilder != null) {
            return widget.monthPickerBuilder!(
              context,
              state.focusedDate,
              widget.events.where((element) {
                return DateUtils.isSameMonth(
                      element.start,
                      state.focusedDate,
                    ) ||
                    DateUtils.isSameMonth(element.end, state.focusedDate);
              }).toList(),
            );
          }

          return DisplayedPeriodPicker(
            period: DisplayedPeriod(state.displayedDate),
            theme: widget.monthPickerTheme,
            reverseAnimation: state.reverseAnimation,
            onLeftButtonPressed:
                DateUtils.isSameMonth(state.displayedDate, _initialDate) ? null : widget.controller.prev,
            onRightButtonPressed: DateUtils.isSameMonth(state.displayedDate, _endDate) ? null : widget.controller.next,
          );
        },
        buildWhen: (previous, current) => !DateUtils.isSameMonth(
          previous.displayedDate,
          current.displayedDate,
        ),
      );

  Widget _buildAllDayEvents() {
    final theme = widget.allDayEventsTheme;

    return BlocBuilder<DaysViewController, DaysViewState>(
      bloc: widget.controller,
      builder: (context, state) {
        return SizedBox(
          width: double.maxFinite,
          child: AllDaysEventsList(
            eventKeys: DaysViewKeys.events,
            eventBuilders: widget.eventBuilders,
            theme: theme,
            visibleDays: 1,
            allDayEvents: _allDayEvents
                .where(
                  (element) => DateTimeRange(start: element.start, end: element.end).days.any(
                        (d) => DateUtils.isSameDay(d, state.focusedDate),
                      ),
                )
                .toList(),
            onShowMoreTap: widget.onAllDayEventsShowMoreTap,
            showMoreBuilder: widget.allDayEventsShowMoreBuilder,
            onEventTap: widget.onAllDayEventTap,
            width: MediaQuery.of(context).size.width,
            view: CalendarView.days,
          ),
        );
      },
    );
  }

  Widget _daysList() {
    final theme = widget.daysListTheme;

    if (widget.daysListBuilder != null) {
      return BlocBuilder<DaysViewController, DaysViewState>(
        bloc: widget.controller,
        builder: (context, state) {
          final start = DateTime(
            state.focusedDate.year,
            state.focusedDate.month,
          );
          final end = DateTime(
            state.focusedDate.year,
            state.focusedDate.month,
            DateUtils.getDaysInMonth(
              state.focusedDate.year,
              state.focusedDate.month,
            ),
          );

          final events = widget.events.where((event) {
            return DateUtils.isSameDay(start, state.focusedDate) ||
                DateUtils.isSameDay(end, state.focusedDate) ||
                (event.start.isAfter(start) && event.start.isBefore(end)) ||
                (event.end.isAfter(start) && event.end.isBefore(end));
          }).toList();

          return widget.daysListBuilder!(
            context,
            state.focusedDate,
            events.cast<T>(),
          );
        },
      );
    }

    return SizedBox(
      height: theme.height,
      child: PageView.builder(
        controller: _monthPickerController,
        physics: const NeverScrollableScrollPhysics(),
        itemBuilder: (context, pageIndex) {
          final monthDate = DateUtils.addMonthsToMonthDate(_initialDate, pageIndex);
          final daysInMonth = DateUtils.getDaysInMonth(monthDate.year, monthDate.month);

          return LayoutBuilder(
            builder: (context, constraints) {
              // Dispose the previous list controller
              _daysListController?.dispose();
              _daysListController = ScrollController(
                initialScrollOffset: min(
                  (_displayedDate.day - 1) * theme.itemExtent,
                  daysInMonth * theme.itemExtent - constraints.maxWidth,
                ),
              );

              return NotificationListener<UserScrollNotification>(
                onNotification: (event) {
                  // Stop scrolling the timeline if user scrolls the list
                  if (event.direction != ScrollDirection.idle) {
                    _stopTimelineScrolling();
                  }
                  return true;
                },
                child: ListView.builder(
                  controller: _daysListController,
                  scrollDirection: Axis.horizontal,
                  physics: theme.physics,
                  itemExtent: theme.itemExtent,
                  itemCount: daysInMonth,
                  itemBuilder: (context, index) {
                    final dayDate = DateUtils.addDaysToDate(monthDate, index);

                    return BlocBuilder<DaysViewController, DaysViewState>(
                      bloc: widget.controller,
                      builder: (context, state) => Padding(
                        padding: theme.padding,
                        child: DaysListItem(
                          dayDate: dayDate,
                          isFocused: DateUtils.isSameDay(state.focusedDate, dayDate),
                          theme: theme.itemTheme,
                          onTap: () => widget.controller.selectDay(dayDate),
                        ),
                      ),
                      buildWhen: (previous, current) =>
                          DateUtils.isSameDay(current.focusedDate, dayDate) ||
                          DateUtils.isSameDay(previous.focusedDate, dayDate),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _timeline() {
    final theme = widget.timelineTheme;

    return ListView.builder(
      key: DaysViewKeys.timeline,
      controller: _timelineController,
      padding: EdgeInsets.only(
        top: theme.padding.top,
        bottom: theme.padding.bottom,
      ),
      itemExtent: _dayExtent,
      itemCount: (_endDate != null) ? _endDate!.difference(_initialDate).inDays + 1 : null,
      itemBuilder: (context, index) {
        final dayDate = DateUtils.addDaysToDate(_initialDate, index);
        final isToday = DateUtils.isSameDay(dayDate, _now);

        return RenderIdProvider(
          id: dayDate,
          child: ValueListenableBuilder(
            valueListenable: _elevatedEvent,
            builder: (context, elevatedEvent, child) => AbsorbPointer(
              absorbing: elevatedEvent != null,
              child: child,
            ),
            child: Padding(
              padding: EdgeInsets.only(
                left: theme.padding.left,
                right: theme.padding.right,
              ),
              child: Row(
                children: [
                  TimeScale(
                    showCurrentTimeMark: isToday,
                    theme: theme.timeScaleTheme,
                  ),
                  Expanded(
                    child: ColoredBox(
                      color: Colors.transparent, // Needs for hitTesting
                      child: EventsLayout<T>(
                        dayDate: dayDate,
                        viewType: CalendarView.days,
                        overlayKey: _overlayKey,
                        layoutsKeys: DaysViewKeys.layouts,
                        eventsKeys: DaysViewKeys.events,
                        timelineTheme: widget.timelineTheme,
                        breaks: widget.breaks,
                        events: _events,
                        elevatedEvent: _elevatedEvent,
                        onEventTap: widget.onEventTap,
                        eventBuilders: widget.eventBuilders,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _onDateLongPress(DateTime timestamp) {
    if (timestamp.isBefore(_initialDate)) return;
    if ((_endDate != null) && timestamp.isAfter(_endDate!)) return;

    widget.onDateLongPress?.call(timestamp);
  }
}

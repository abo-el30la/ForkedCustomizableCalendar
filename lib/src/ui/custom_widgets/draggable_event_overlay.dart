import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_customizable_calendar/src/domain/models/models.dart';
import 'package:flutter_customizable_calendar/src/ui/custom_widgets/custom_widgets.dart';
import 'package:flutter_customizable_calendar/src/ui/themes/themes.dart';
import 'package:flutter_customizable_calendar/src/utils/utils.dart';

/// A key holder of all DraggableEventView keys
@visibleForTesting
abstract class DraggableEventOverlayKeys {
  /// A key for the elevated (floating) event view
  static const elevatedEvent = ValueKey('elevatedEvent');
// static GlobalKey elevatedEvent = GlobalKey(debugLabel: 'elevatedEvent');
}

/// Wrapper which needs to wrap a scrollable [child] widget and display an
/// elevated event view over it.
class DraggableEventOverlay<T extends FloatingCalendarEvent> extends StatefulWidget {
  /// Creates an overlay for draggable event view over given [child] widget.
  const DraggableEventOverlay(
    this.event, {
    required this.getTimelineBox,
    required this.viewType,
    required this.timelineTheme,
    required this.getLayoutBox,
    required this.saverConfig,
    required this.getEventBox,
    required this.child,
    super.key,
    this.padding = EdgeInsets.zero,
    this.eventBuilders = const {},
    this.onEventLongPressStart,
    this.onDragDown,
    this.onDragUpdate,
    this.onDragEnd,
    this.onSizeUpdate,
    this.onResizingEnd,
    this.onDropped,
    this.onChanged,
    this.onDateLongPress,
    this.enableFloatingEvents = true,
  });

  /// Event builders
  final Map<Type, EventBuilder> eventBuilders;

  /// A notifier which needs to control elevated event
  final FloatingEventNotifier<T> event;

  /// Which [CalendarView]'s timeline is wrapped
  final CalendarView viewType;

  /// The timeline customization params
  final TimelineTheme timelineTheme;

  /// Offset for the overlay
  final EdgeInsets padding;

  /// Is called just after user start to interact with the event view
  final void Function()? onDragDown;

  /// Overrides the default behavior of the event view's long press
  final void Function(LongPressStartDetails details, T event)? onEventLongPressStart;

  /// Is called when user tap outside events
  final void Function(DateTime)? onDateLongPress;

  /// Is called during user drags the event view
  final void Function(DragUpdateDetails)? onDragUpdate;

  /// Is called just after user stops dragging the event view
  final void Function()? onDragEnd;

  /// Is called during user resizes the event view
  final void Function(DragUpdateDetails)? onSizeUpdate;

  /// Is called just after user stops resizing the event view
  final void Function()? onResizingEnd;

  /// Is called just after the event is changed
  final void Function(T)? onChanged;

  /// Is called just after the event is dropped
  final void Function(T)? onDropped;

  /// Function which allows to find the timeline's [RenderBox] in context
  final RenderBox? Function() getTimelineBox;

  /// Function which allows to find the layout's [RenderBox] in context
  final RenderBox? Function(DateTime) getLayoutBox;

  /// Function which allows to find the event view's [RenderBox] in context
  final RenderBox? Function(T) getEventBox;

  /// Properties for widget which is used to save edited event
  final SaverConfig saverConfig;

  /// Scrollable view which needs to be wrapped
  final Widget child;

  /// Enable floating events
  final bool enableFloatingEvents;

  @override
  State<DraggableEventOverlay<T>> createState() => DraggableEventOverlayState<T>();
}

/// State of [DraggableEventOverlay] which allows to set a floating event
/// and create it's draggable [OverlayEntry].
class DraggableEventOverlayState<T extends FloatingCalendarEvent> extends State<DraggableEventOverlay<T>>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final _overlayKey = GlobalKey<OverlayState>();
  final _layerLink = LayerLink();
  final _eventBounds = RectNotifier();
  late AnimationController _animationController;
  late Animation<double> _animation;
  late RectTween _boundsTween;
  late DateTime _pointerTimePoint = DateTime.now();
  late Duration _startDiff = Duration.zero;
  var _pointerLocation = Offset.zero;
  var _dragging = false;
  var _resizing = false;
  OverlayEntry? _eventEntry;
  OverlayEntry? _sizerEntry;

  List<int> _dayOffsets = [];

  OverlayState get _overlay => _overlayKey.currentState!;

  double get _minuteExtent => _hourExtent / Duration.minutesPerHour;

  double get _hourExtent => widget.timelineTheme.timeScaleTheme.hourExtent;

  int get _cellExtent => widget.timelineTheme.cellExtent;

  DraggableEventTheme get _draggableEventTheme => widget.timelineTheme.draggableEventTheme;

  bool _edited = false;
  List<Rect> _rects = [];
  bool _scrolling = false;

  bool _needsBeforeEventUpdate = false;

  T? _getEventAt(Offset globalPosition) {
    final renderIds = _timelineHitTest(globalPosition);
    final targets = renderIds.whereType<RenderId<T>>();

    return targets.isNotEmpty ? targets.first.id : null;
  }

  /// Needs to make interaction between a timeline and the overlay
  bool onEventLongPressStart(LongPressStartDetails details) {
    _pointerLocation = details.globalPosition;

    if (_animationController.isAnimating) {
      _removeEntries();
      _animationController.reset();
    }

    final renderIds = _timelineHitTest(_pointerLocation);
    final hitTestedEvents = renderIds.whereType<RenderId<T>>();

    if (hitTestedEvents.isEmpty) return false;

    final eventBox = hitTestedEvents.first;
    final event = eventBox.id;
    final layoutBox = renderIds.singleWhere((renderId) => renderId.id == Constants.layoutId);

    final timelineBox = widget.getTimelineBox();
    final eventPosition = eventBox.localToGlobal(Offset.zero, ancestor: timelineBox);
    final layoutPosition = layoutBox.localToGlobal(Offset.zero, ancestor: timelineBox);

    widget.event.value = event;
    _pointerTimePoint = _getTimePointAt(_pointerLocation)!;
    _startDiff = _pointerTimePoint.difference(event.start);

    _updateDayOffsets(event);

    final dayWidth = layoutBox.size.width / 13;
    _boundsTween = RectTween(
      begin: Rect.fromLTWH(
        widget.viewType == CalendarView.month ? eventPosition.dx + dayWidth : eventPosition.dx,
        eventPosition.dy + 24,
        eventBox.size.width,
        eventBox.size.height,
      ),
      end: Rect.fromLTWH(
        layoutPosition.dx,
        eventPosition.dy,
        widget.viewType == CalendarView.month ? dayWidth : layoutBox.size.width,
        eventBox.size.height,
      ),
    );
    final rect = _boundsTween.end!;
    _eventBounds.update(
      dx: rect.left,
      dy: rect.top,
      width: rect.width,
      height: rect.height,
    );
    _createEntriesFor(event);
    _animationController.forward();

    _dragging = true;
    return true;
  }

  /// Needs to make interaction between a timeline and the overlay
  void onEventLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    var delta = details.globalPosition - _pointerLocation;
    if (_scrolling) {
      delta = Offset.zero;
    }

    final dragUpdateDetails = DragUpdateDetails(
      delta: delta,
      globalPosition: details.globalPosition,
      localPosition: details.localPosition,
    );

    widget.onDragUpdate?.call(dragUpdateDetails);
    _eventBounds.origin += dragUpdateDetails.delta;
    if (!_resetPointerLocation(details.globalPosition)) return;
    _pointerTimePoint = _getTimePointAt(_pointerLocation) ?? _pointerTimePoint;
    _scrolling = false;
  }

  /// Needs to make interaction between a timeline and the overlay
  void onEventLongPressEnd(LongPressEndDetails details) {
    if (widget.event.value == null) {
      return;
    }

    _dragging = false;
    widget.onDragEnd?.call();
    _pointerTimePoint = _getTimePointAt(_pointerLocation) ?? _pointerTimePoint;
    _updateEventOriginAndStart();
    _updateDayOffsets(widget.event.value!);
    if (!_edited) {
      _edited = true;
      if (mounted) {
        setState(() {});
      }
    }

    if (!widget.enableFloatingEvents) {
      _saveAndFinish();
    }
  }

  /// Needs to make interaction between a timeline and the overlay
  void onEventLongPressCancel() {
    _dragging = false;
  }

  DateTime? _getTargetDayAt(Offset globalPosition) {
    final renderIds = _timelineHitTest(globalPosition);
    final targets = renderIds.whereType<RenderId<DateTime>>();

    return targets.isNotEmpty ? targets.first.id : null;
  }

  DateTime? _getTimePointAt(Offset globalPosition) {
    final dayDate = _getTargetDayAt(globalPosition);

    if (dayDate == null) return null;

    if (widget.viewType == CalendarView.month) {
      return dayDate.add(const Duration(hours: 12));
    }

    final layoutBox = widget.getLayoutBox(dayDate);
    if (layoutBox == null) return null;

    final minutes = layoutBox.globalToLocal(globalPosition).dy ~/ _minuteExtent;

    return dayDate.add(Duration(minutes: minutes));
  }

  Iterable<RenderId<dynamic>> _globalHitTest(Offset globalPosition) {
    final result = HitTestResult();

    WidgetsBinding.instance.hitTest(result, globalPosition);

    return result.path.map((entry) => entry.target).whereType<RenderId<dynamic>>();
  }

  Iterable<RenderId<dynamic>> _timelineHitTest(Offset globalPosition) {
    final timelineBox = widget.getTimelineBox();

    if (timelineBox == null) return const Iterable.empty();

    final result = BoxHitTestResult();
    final localPosition = timelineBox.globalToLocal(globalPosition);
    timelineBox.hitTest(result, position: localPosition);

    return result.path.map((entry) => entry.target).whereType<RenderId<dynamic>>();
  }

  bool _resetPointerLocation(Offset globalPosition) {
    final timelineBox = widget.getTimelineBox();

    if (timelineBox == null) return false;

    final origin = timelineBox.localToGlobal(Offset.zero);
    final bounds = origin & timelineBox.size;

    if (!bounds.contains(globalPosition)) return false;

    // Update _pointerLocation if it's position is within the timeline rect
    _pointerLocation = globalPosition;

    return true;
  }

  void _createEntriesFor(T event) {
    _eventEntry = OverlayEntry(builder: _floatingEventBuilder);
    _overlay.insert(_eventEntry!);
  }

  void _removeEntries() {
    _eventEntry?.remove();
    _eventEntry = null;
    _sizerEntry?.remove();
    _sizerEntry = null;
  }

  void _dropEvent(T event) {
    _edited = false;
    if (mounted) {
      setState(() {});
    }

    if (_animationController.isAnimating) _animationController.stop();

    _boundsTween.end = _eventBounds.value;
    _animationController.reverse().whenComplete(() {
      widget.event.value = null;
      _removeEntries();
      widget.onDropped?.call(event);
    });
    _dragging = false;
  }

  bool _updateEventOriginAndStart() {
    final isMonth = widget.viewType == CalendarView.month;
    final dayDate = _getTargetDayAt(_pointerLocation); // <- temporary
    if (dayDate == null) return false;

    final layoutBox = widget.getLayoutBox(dayDate);
    if (layoutBox == null) return false;

    final timelineBox = widget.getTimelineBox();
    final layoutPosition = layoutBox.localToGlobal(Offset.zero, ancestor: timelineBox);
    final originTimePoint = _pointerTimePoint.subtract(_startDiff);
    final originDayDate = DateUtils.dateOnly(originTimePoint);
    final minutes = originTimePoint.minute + (originTimePoint.hour * Duration.minutesPerHour);
    final roundedMinutes = (minutes / _cellExtent).round() * _cellExtent;
    final eventStartDate = originDayDate.add(Duration(minutes: roundedMinutes));
    final offset = (minutes - roundedMinutes) * _minuteExtent;

    _eventBounds.update(
      dx: layoutPosition.dx,
      dy: isMonth ? layoutPosition.dy : _eventBounds.dy - offset,
    );

    if (mounted) {
      setState(() {});
    }

    SchedulerBinding.instance.addPostFrameCallback((timeStamp) {
      widget.event.value = widget.event.value?.copyWith(start: eventStartDate) as T?;
      if (mounted) {
        setState(() {});
      }
    });

    return true;
  }

  void _updateDayOffsets(T event) {
    final range = DateTimeRange(
      start: DateUtils.dateOnly(event.start),
      end: DateUtils.dateOnly(event.end),
    );
    final firstOffset = range.start.difference(_pointerTimePoint).inDays;
    var dayOffsetLength = range.days.length + 1;
    if (event.end.isAtSameMomentAs(DateUtils.dateOnly(event.end))) {
      dayOffsetLength -= 1;
    }

    _dayOffsets = List.generate(dayOffsetLength, (index) => firstOffset + index);
  }

  void _updateEventHeightAndDuration() {
    final event = widget.event.value;
    if (event == null) return;

    final dayDate = DateUtils.dateOnly(event.start);
    final minutes = event.start.minute + (event.start.hour * Duration.minutesPerHour) + (_eventBounds.height ~/ _minuteExtent);
    final roundedMinutes = (minutes / _cellExtent).round() * _cellExtent;
    final eventEndDate = dayDate.add(Duration(minutes: roundedMinutes));
    final eventDuration = eventEndDate.difference(event.start);

    _eventBounds.height = eventDuration.inMinutes * _minuteExtent;

    if (widget.viewType != CalendarView.month && event is EditableCalendarEvent) {
      widget.event.value = event.copyWith(duration: eventDuration) as T;
    }
  }

  void _animateBounds() {
    _eventBounds.value = _boundsTween.transform(_animation.value)!;
  }

  void _initAnimationController() => _animationController = AnimationController(
        duration: _draggableEventTheme.animationDuration,
        vsync: this,
      )..addListener(_animateBounds);

  void _initAnimation() => _animation = CurvedAnimation(
        parent: _animationController,
        curve: _draggableEventTheme.animationCurve,
      );

  void _eventHeightLimiter() => _eventBounds.height = max(_eventBounds.height, _minuteExtent * _cellExtent);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initAnimationController();
    _initAnimation();
    _eventBounds.addListener(_eventHeightLimiter);
  }

  Future<void> _beforeEventUpdate() async {
    try {
      if (!_needsBeforeEventUpdate && widget.viewType != CalendarView.month) {
        return;
      }

      _pointerTimePoint = _getTimePointAt(_pointerLocation) ?? _pointerTimePoint;
      if (!_updateEventOriginAndStart()) {
        await Future.delayed(
          const Duration(milliseconds: 100),
          _beforeEventUpdate,
        );
        return;
      }
      if (widget.event.value != null) {
        _updateDayOffsets(widget.event.value!);
      }
      _updateEventHeightAndDuration();
    } on Exception {
      // ignore
    }
  }

  @override
  void didUpdateWidget(covariant DraggableEventOverlay<T> oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (_draggableEventTheme != oldWidget.timelineTheme.draggableEventTheme) {
      _animationController.dispose();
      _initAnimationController();
      _initAnimation();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (LongPressStartDetails details) {
        if (widget.onEventLongPressStart != null) {
          final event = _getEventAt(details.globalPosition);
          if (event != null) {
            widget.onEventLongPressStart!(details, event);
            return;
          }
        }

        if (!_dragging && !onEventLongPressStart(details)) {
          final dayDate = _getTimePointAt(details.globalPosition);
          if (dayDate != null) {
            widget.onDateLongPress?.call(dayDate);
          }
        }
        if (mounted) {
          setState(() {});
        }
      },
      onLongPressMoveUpdate: onEventLongPressMoveUpdate,
      onLongPressEnd: onEventLongPressEnd,
      child: ColoredBox(
        color: Colors.transparent,
        child: ValueListenableBuilder<T?>(
          valueListenable: widget.event,
          builder: (context, elevatedEvent, child) {
            if (elevatedEvent == null) return child!;

            return GestureDetector(
              // Prevent parent's onLongPress reaction
              onLongPress: () {},

              onTap: () {
                _dropEvent(elevatedEvent);
              },
              onPanDown: (details) {
                final renderIds = _globalHitTest(details.globalPosition);
                final ids = renderIds.map((renderId) => renderId.id);

                if (ids.contains(Constants.sizerId)) {
                  _resizing = true;
                  widget.onDragDown?.call();
                } else if (ids.contains(Constants.elevatedEventId)) {
                  _dragging = true;
                  _dayOffsets.clear();
                  widget.onDragDown?.call();
                }
              },
              onPanStart: (details) {
                if (!_dragging) return;
                final event = widget.event.value!;
                _pointerLocation = details.globalPosition;
                _pointerTimePoint = _getTimePointAt(_pointerLocation) ?? _pointerTimePoint;
                _startDiff = _pointerTimePoint.difference(event.start);

                // Prevent accident day addition on WeekView
                if (widget.viewType == CalendarView.week) {
                  _startDiff -= Duration(days: _startDiff.inDays);
                  if (_startDiff.isNegative) {
                    _startDiff += const Duration(days: 1);
                  }
                }

                _updateDayOffsets(event);
              },
              onPanUpdate: (details) {
                if (_resizing) {
                  widget.onSizeUpdate?.call(details);
                  _eventBounds.height += details.delta.dy;
                } else if (_dragging) {
                  widget.onDragUpdate?.call(details);
                  _eventBounds.origin += details.delta;
                  if (!_resetPointerLocation(details.globalPosition)) return;
                  _pointerTimePoint = _getTimePointAt(_pointerLocation) ?? _pointerTimePoint;
                }
              },
              onPanEnd: (details) {
                if (_resizing) {
                  _resizing = false;
                  widget.onResizingEnd?.call();
                  _updateEventHeightAndDuration();
                } else if (_dragging) {
                  _dragging = false;
                  widget.onDragEnd?.call();
                  _pointerTimePoint = _getTimePointAt(_pointerLocation) ?? _pointerTimePoint;
                  _updateEventOriginAndStart();
                  _updateDayOffsets(widget.event.value!);
                }
                if (!_edited) {
                  _edited = true;
                  if (mounted) {
                    setState(() {});
                  }
                }
              },
              child: Container(
                padding: const EdgeInsets.all(18.0),
                height: double.infinity,
                color: Colors.red,
                child: child,
              ),
            );
          },
          child: Stack(
            children: [
              NotificationListener<ScrollUpdateNotification>(
                onNotification: (event) {
                  final scrollDelta = event.scrollDelta ?? 0;

                  _needsBeforeEventUpdate = event.metrics.axis == Axis.horizontal;

                  if (_dragging && event.metrics.axis == Axis.vertical) {
                    _scrolling = scrollDelta.abs() > 0;
                  }

                  if (!_dragging && event.metrics.axis == Axis.vertical) {
                    _eventBounds.update(
                      dy: _eventBounds.dy - scrollDelta,
                      height: _eventBounds.height + (_resizing ? scrollDelta : 0),
                    );
                  }

                  if (!_dragging &&
                      event.metrics.axis == Axis.horizontal &&
                      widget.event.value != null &&
                      ((widget.viewType == CalendarView.week && scrollDelta.abs() < 1) ||
                          (widget.viewType == CalendarView.month && scrollDelta.abs() < 3))) {
                    _pointerTimePoint = _getTimePointAt(_pointerLocation) ?? _pointerTimePoint;
                    // _updateEventOriginAndStart();
                  }
                  return true;
                },
                child: widget.child,
              ),
              Positioned.fill(
                left: widget.padding.left,
                top: widget.padding.top,
                right: widget.padding.right,
                bottom: widget.padding.bottom,
                child: Overlay(key: _overlayKey),
              ),
              if (_edited)
                Saver(
                  alignment: widget.saverConfig.alignment,
                  onPressed: _saveAndFinish,
                  child: widget.saverConfig.child,
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _saveAndFinish() {
    _beforeEventUpdate().then((value) {
      WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
        widget.onChanged?.call(widget.event.value!);
        // _dropEvent(widget.event.value!);
        _edited = false;
        _removeEntries();
        widget.event.value = null;
        _resizing = false;
        _dragging = false;
        if (mounted) {
          setState(() {});
        }
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _animationController.dispose();
    _eventBounds.dispose();
    super.dispose();
  }

  Widget _elevatedEventView() {
    return EventView(
      widget.event.value!,
      key: DraggableEventOverlayKeys.elevatedEvent,
      viewType: widget.viewType,
      eventBuilders: widget.eventBuilders,
      theme: widget.timelineTheme.floatingEventsTheme.copyWith(elevation: _draggableEventTheme.elevation),
    );
  }

  Widget _sizerView() {
    final theme = _draggableEventTheme.sizerTheme;

    return ClipOval(
      child: GestureDetector(
        onTap: () {}, // Needs to avoid unnecessary event drops
        child: ColoredBox(
          color: Colors.transparent, // Needs for hitTesting
          child: Padding(
            padding: EdgeInsets.all(theme.extraSpace),
            child: DecoratedBox(
              decoration: theme.decoration,
            ),
          ),
        ),
      ),
    );
  }

  List<Rect> _rectForDay(Rect bounds, DateTime initialDayDate) {
    if (widget.event.value == null) {
      return [];
    }

    final dayDate = DateUtils.dateOnly(initialDayDate);
    final layoutBox = widget.getLayoutBox(dayDate);
    if (layoutBox == null) {
      return [];
    }
    final timelineBox = widget.getTimelineBox();
    Offset layoutPosition;
    try {
      layoutPosition = layoutBox.localToGlobal(Offset.zero, ancestor: timelineBox);
    } catch (e) {
      layoutPosition = bounds.topLeft;
    }
    final delta = bounds.topLeft - layoutPosition;

    final result = <Rect>[];

    if (widget.viewType == CalendarView.week) {
      var dateBefore = dayDate.copyWith();
      var dateAfter = dayDate.add(const Duration(days: 1));

      var i = 1;
      while (i <= 7) {
        final layoutBox = widget.getLayoutBox(dateAfter);
        if (layoutBox == null) {
          break;
        }
        Offset layoutPosition;
        try {
          layoutPosition = layoutBox.localToGlobal(Offset.zero, ancestor: timelineBox);
        } catch (e) {
          break;
        }
        result.add(
          Rect.fromLTWH(
            layoutPosition.dx + delta.dx,
            bounds.top - 24 * i * _hourExtent,
            bounds.width,
            bounds.height,
          ),
        );
        i++;
        dateAfter = dateAfter.add(const Duration(days: 1));
      }

      i = 1;
      while (i <= 7) {
        dateBefore = dateBefore.subtract(const Duration(days: 1));
        final layoutBox = widget.getLayoutBox(dateBefore);
        if (layoutBox == null) {
          break;
        }
        Offset layoutPosition;
        try {
          layoutPosition = layoutBox.localToGlobal(Offset.zero, ancestor: timelineBox);
        } catch (e) {
          break;
        }
        result.add(
          Rect.fromLTWH(
            layoutPosition.dx + delta.dx,
            bounds.top + 24 * i * _hourExtent,
            bounds.width,
            bounds.height,
          ),
        );
        i++;
      }
    }

    if (widget.viewType == CalendarView.month) {
      final weekOffsetY = layoutBox.size.height * 1.5;
      final dayWidth = layoutBox.size.width / 13;
      for (var i = -5; i <= 5; i++) {
        result.add(
          Rect.fromLTWH(
            layoutPosition.dx + delta.dx + i * dayWidth * 7,
            bounds.top - weekOffsetY * i,
            bounds.width,
            bounds.height,
          ),
        );
      }
    }

    return result;
  }

  Widget _floatingEventBuilder(BuildContext context) {
    final event = widget.event.value;

    return ValueListenableBuilder<Rect>(
      valueListenable: _eventBounds,
      builder: (context, rect, child) {
        SchedulerBinding.instance.addPostFrameCallback((timeStamp) {
          _rects = _rectForDay(rect, _pointerTimePoint);
        });

        return Stack(
          children: [
            Positioned.fromRect(
              rect: rect,
              child: child!,
            ),
            if (widget.viewType != CalendarView.month && event is EditableCalendarEvent) _sizerBuilder(context, rect.bottomCenter),
            if (mounted && widget.viewType != CalendarView.days)
              for (final Rect rect in _rects) ...[
                Positioned.fromRect(
                  rect: rect,
                  child: CompositedTransformFollower(
                    offset: rect.topLeft - rect.topLeft,
                    link: _layerLink,
                    child: RenderIdProvider(
                      id: Constants.elevatedEventId,
                      child: _elevatedEventView(),
                    ),
                  ),
                ),
              ],
            if (widget.viewType != CalendarView.month && event is EditableCalendarEvent) _sizerBuilder(context, rect.bottomCenter),
          ],
        );
      },
      child: CompositedTransformTarget(
        link: _layerLink,
        child: RenderIdProvider(
          id: Constants.elevatedEventId,
          child: _elevatedEventView(),
        ),
      ),
    );
  }

  Widget _sizerBuilder(BuildContext context, Offset offset) => ValueListenableBuilder<double>(
        valueListenable: _animation,
        builder: (context, scale, child) {
          final theme = _draggableEventTheme.sizerTheme;
          final width = theme.size.width * scale + theme.extraSpace * 2;
          final height = theme.size.height * scale + theme.extraSpace * 2;

          return Positioned(
            top: offset.dy - height / 2,
            left: offset.dx - width / 2,
            width: width,
            height: height,
            child: child!,
          );
        },
        child: RenderIdProvider(
          id: Constants.sizerId,
          child: _sizerView(),
        ),
      );
}

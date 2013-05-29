// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of dart.async;

// -------------------------------------------------------------------
// Controller for creating and adding events to a stream.
// -------------------------------------------------------------------

/**
 * A controller with the stream it controls.
 *
 * This controller allows sending data, error and done events on
 * its [stream].
 * This class can be used to create a simple stream that others
 * can listen on, and to push events to that stream.
 *
 * It's possible to check whether the stream is paused or not, and whether
 * it has subscribers or not, as well as getting a callback when either of
 * these change.
 *
 * If the stream starts or stops having listeners (first listener subscribing,
 * last listener unsubscribing), the `onSubscriptionStateChange` callback
 * is notified as soon as possible. If the subscription stat changes during
 * an event firing or a callback being executed, the change will not be reported
 * until the current event or callback has finished.
 * If the pause state has also changed during an event or callback, only the
 * subscription state callback is notified.
 *
 * If the subscriber state has not changed, but the pause state has, the
 * `onPauseStateChange` callback is notified as soon as possible, after firing
 * a current event or completing another callback. This happens if the stream
 * is not paused, and a listener pauses it, or if the stream has been resumed
 * from pause and has no pending events. If the listeners resume a paused stream
 * while it still has queued events, the controller will still consider the
 * stream paused until all queued events have been dispatched.
 *
 * Whether to invoke a callback depends only on the state before and after
 * a stream action, for example firing an event. If the state changes multiple
 * times during the action, and then ends up in the same state as before, no
 * callback is performed.
 *
 * If listeners are added after the stream has completed (sent a "done" event),
 * the listeners will be sent a "done" event eventually, but they won't affect
 * the stream at all, and won't trigger callbacks. From the controller's point
 * of view, the stream is completely inert when has completed.
 */
abstract class StreamController<T> implements EventSink<T> {
  /** The stream that this controller is controlling. */
  Stream<T> get stream;

  /**
   * A controller with a [stream] that supports only one single subscriber.
   *
   * The controller will buffer all incoming events until the subscriber is
   * registered.
   *
   * The [onPause] function is called when the stream becomes
   * paused. [onResume] is called when the stream resumed.
   *
   * The [onListen] callback is called when the stream
   * receives its listener and [onCancel] when the listener ends
   * its subscription.
   *
   * If the stream is canceled before the controller needs new data the
   * [onResume] call might not be executed.
   */
  factory StreamController({void onListen(),
                            void onPause(),
                            void onResume(),
                            void onCancel()})
      => new _StreamControllerImpl<T>(onListen, onPause, onResume, onCancel);

  /**
   * A controller where [stream] can be listened to more than once.
   *
   * The [Stream] returned by [stream] is a broadcast stream. It can be listened
   * to more than once.
   *
   * The controller distributes any events to all currently subscribed
   * listeners.
   * It is not allowed to call [add], [addError], or [close] before a previous
   * call has returned.
   *
   * Each listener is handled independently, and if they pause, only the pausing
   * listener is affected. A paused listener will buffer events internally until
   * unpaused or canceled.
   *
   * The [onListen] callback is called when the first listener is subscribed,
   * and the [onCancel] is called when there are no longer any active listeners.
   * If a listener is added again later, after the [onCancel] was called,
   * the [onListen] will be called again.
   */
  factory StreamController.broadcast({void onListen(), void onCancel()}) {
    return new _MultiplexStreamController<T>(onListen, onCancel);
  }

  /**
   * Returns a view of this object that only exposes the [EventSink] interface.
   */
  EventSink<T> get sink;

  /**
   * Whether the stream is closed for adding more events.
   *
   * If true, the "done" event might not have fired yet, but it has been
   * scheduled, and it is too late to add more events.
   */
  bool get isClosed;

  /**
   * Whether the subscription would need to buffer events.
   *
   * This is the case if the controller's stream has a listener and it is
   * paused, or if it has not received a listener yet. In that case, the
   * controller is considered paused as well.
   *
   * A broadcast stream controller is never considered paused. It always
   * forwards its events to all uncanceled listeners, if any, and let them
   * handle their own pausing.
   */
  bool get isPaused;

  /** Whether there is a subscriber on the [Stream]. */
  bool get hasListener;

  /**
   * Send or enqueue an error event.
   *
   * Also allows an objection stack trace object, on top of what [EventSink]
   * allows.
   */
  void addError(Object error, [Object stackTrace]);
}


abstract class _StreamControllerLifecycle<T> {
  void _recordListen(StreamSubscription<T> subscription) {}
  void _recordPause(StreamSubscription<T> subscription) {}
  void _recordResume(StreamSubscription<T> subscription) {}
  void _recordCancel(StreamSubscription<T> subscription) {}
}

/**
 * Default implementation of [StreamController].
 *
 * Controls a stream that only supports a single controller.
 */
class _StreamControllerImpl<T> implements StreamController<T>,
                                          _StreamControllerLifecycle<T> {
  static const int _STATE_OPEN = 0;
  static const int _STATE_CANCELLED = 1;
  static const int _STATE_CLOSED = 2;

  final _NotificationHandler _onListen;
  final _NotificationHandler _onPause;
  final _NotificationHandler _onResume;
  final _NotificationHandler _onCancel;
  _StreamImpl<T> _stream;

  // An active subscription on the stream, or null if no subscripton is active.
  _ControllerSubscription<T> _subscription;

  // Whether we have sent a "done" event.
  int _state = _STATE_OPEN;

  // Events added to the stream before it has an active subscription.
  _PendingEvents _pendingEvents = null;

  _StreamControllerImpl(this._onListen,
                        this._onPause,
                        this._onResume,
                        this._onCancel) {
    _stream = new _ControllerStream<T>(this);
  }

  Stream<T> get stream => _stream;

  /**
   * Returns a view of this object that only exposes the [EventSink] interface.
   */
  EventSink<T> get sink => new _EventSinkView<T>(this);

  /**
   * Whether a listener has existed and been cancelled.
   *
   * After this, adding more events will be ignored.
   */
  bool get _isCancelled => (_state & _STATE_CANCELLED) != 0;

  bool get isClosed => (_state & _STATE_CLOSED) != 0;

  bool get isPaused => hasListener ? _subscription._isInputPaused
                                   : !_isCancelled;

  bool get hasListener => _subscription != null;

  /**
   * Send or queue a data event.
   */
  void add(T value) {
    if (isClosed) throw new StateError("Adding event after close");
    if (_subscription != null) {
      _subscription._add(value);
    } else if (!_isCancelled) {
      _addPendingEvent(new _DelayedData<T>(value));
    }
  }

  /**
   * Send or enqueue an error event.
   */
  void addError(Object error, [Object stackTrace]) {
    if (isClosed) throw new StateError("Adding event after close");
    if (stackTrace != null) {
      // Force stack trace overwrite. Even if the error already contained
      // a stack trace.
      _attachStackTrace(error, stackTrace);
    }
    if (_subscription != null) {
      _subscription._addError(error);
    } else if (!_isCancelled) {
      _addPendingEvent(new _DelayedError(error));
    }
  }

  /**
   * Closes this controller.
   *
   * After closing, no further events may be added using [add] or [addError].
   *
   * You are allowed to close the controller more than once, but only the first
   * call has any effect.
   *
   * The first time a controller is closed, a "done" event is sent to its
   * stream.
   */
  void close() {
    if (isClosed) return;
    _state |= _STATE_CLOSED;
    if (_subscription != null) {
      _subscription._close();
    } else if (!_isCancelled) {
      _addPendingEvent(const _DelayedDone());
    }
  }

  void _addPendingEvent(_DelayedEvent event) {
    if (_isCancelled) return;
    _StreamImplEvents events = _pendingEvents;
    if (events == null) {
      events = _pendingEvents = new _StreamImplEvents();
    }
    events.add(event);
  }

  void _recordListen(_BufferingStreamSubscription<T> subscription) {
    assert(_subscription == null);
    _subscription = subscription;
    subscription._setPendingEvents(_pendingEvents);
    _pendingEvents = null;
    subscription._guardCallback(() {
      _runGuarded(_onListen);
    });
  }

  void _recordCancel(StreamSubscription<T> subscription) {
    assert(identical(_subscription, subscription));
    _subscription = null;
    _state |= _STATE_CANCELLED;
    _runGuarded(_onCancel);
  }

  void _recordPause(StreamSubscription<T> subscription) {
    _runGuarded(_onPause);
  }

  void _recordResume(StreamSubscription<T> subscription) {
    _runGuarded(_onResume);
  }
}

typedef void _NotificationHandler();

void _runGuarded(_NotificationHandler notificationHandler) {
  if (notificationHandler == null) return;
  try {
    notificationHandler();
  } catch (e, s) {
    _throwDelayed(e, s);
  }
}

class _ControllerStream<T> extends _StreamImpl<T> {
  _StreamControllerLifecycle<T> _controller;
  bool _hasListener = false;

  _ControllerStream(this._controller);

  StreamSubscription<T> _createSubscription(
      void onData(T data),
      void onError(Object error),
      void onDone(),
      bool cancelOnError) {
    if (_hasListener) {
      throw new StateError("The stream has already been listened to.");
    }
    _hasListener = true;
    return new _ControllerSubscription<T>(
        _controller, onData, onError, onDone, cancelOnError);
  }

  void _onListen(_BufferingStreamSubscription subscription) {
    _controller._recordListen(subscription);
  }
}

class _ControllerSubscription<T> extends _BufferingStreamSubscription<T> {
  final _StreamControllerLifecycle<T> _controller;

  _ControllerSubscription(this._controller,
                          void onData(T data),
                          void onError(Object error),
                          void onDone(),
                          bool cancelOnError)
      : super(onData, onError, onDone, cancelOnError);

  void _onCancel() {
    _controller._recordCancel(this);
  }

  void _onPause() {
    _controller._recordPause(this);
  }

  void _onResume() {
    _controller._recordResume(this);
  }
}

class _MultiplexStream<T> extends _StreamImpl<T> {
  _MultiplexStreamController _controller;

  _MultiplexStream(this._controller);

  bool get isBroadcast => true;

  StreamSubscription<T> _createSubscription(
      void onData(T data),
      void onError(Object error),
      void onDone(),
      bool cancelOnError) {
    return new _MultiplexSubscription<T>(
        _controller, onData, onError, onDone, cancelOnError);
  }

  void _onListen(_BufferingStreamSubscription subscription) {
    _controller._recordListen(subscription);
  }
}

abstract class _MultiplexSubscriptionLink {
  _MultiplexSubscriptionLink _next;
  _MultiplexSubscriptionLink _previous;
}

class _MultiplexSubscription<T> extends _ControllerSubscription<T>
                                implements _MultiplexSubscriptionLink {
  static const int _STATE_EVENT_ID = 1;
  static const int _STATE_FIRING = 2;
  static const int _STATE_REMOVE_AFTER_FIRING = 4;
  int _eventState;

  _MultiplexSubscriptionLink _next;
  _MultiplexSubscriptionLink _previous;

  _MultiplexSubscription(_StreamControllerLifecycle controller,
                         void onData(T data),
                         void onError(Object error),
                         void onDone(),
                         bool cancelOnError)
      : super(controller, onData, onError, onDone, cancelOnError) {
    _next = _previous = this;
  }

  _MultiplexStreamController get _controller => super._controller;

  bool _expectsEvent(int eventId) {
    return (_eventState & _STATE_EVENT_ID) == eventId;
  }

  void _toggleEventId() {
    _eventState ^= _STATE_EVENT_ID;
  }

  bool get _isFiring => (_eventState & _STATE_FIRING) != 0;

  bool _setRemoveAfterFiring() {
    assert(_isFiring);
    _eventState |= _STATE_REMOVE_AFTER_FIRING;
  }

  bool get _removeAfterFiring =>
      (_eventState & _STATE_REMOVE_AFTER_FIRING) != 0;
}


class _MultiplexStreamController<T> implements StreamController<T>,
                                               _StreamControllerLifecycle<T>,
                                               _MultiplexSubscriptionLink {
  static const int _STATE_INITIAL = 0;
  static const int _STATE_EVENT_ID = 1;
  static const int _STATE_FIRING = 2;
  static const int _STATE_CLOSED = 4;

  final _NotificationHandler _onListen;
  final _NotificationHandler _onCancel;

  // State of the controller.
  int _state;

  // Double-linked list of active listeners.
  _MultiplexSubscriptionLink _next;
  _MultiplexSubscriptionLink _previous;

  _MultiplexStreamController(this._onListen, this._onCancel)
      : _state = _STATE_INITIAL {
    _next = _previous = this;
  }

  // StreamController interface.

  Stream<T> get stream => new _MultiplexStream<T>(this);

  EventSink<T> get sink => new _EventSinkView<T>(this);

  bool get isClosed => (_state & _STATE_CLOSED) != 0;

  /**
   * A multiplex controller is never paused.
   *
   * Each receiving stream may be paused individually, and they handle their
   * own buffering.
   */
  bool get isPaused => false;

  /** Whether there are currently a subscriber on the [Stream]. */
  bool get hasListener => !_isEmpty;

  // Linked list helpers

  bool get _isEmpty => identical(_next, this);

  /** Adds subscription to linked list of active listeners. */
  void _addListener(_MultiplexSubscription<T> subscription) {
    _MultiplexSubscriptionLink previous = _previous;
    previous._next = subscription;
    _previous = subscription._previous;
    subscription._previous._next = this;
    subscription._previous = previous;
    subscription._eventState = (_state & _STATE_EVENT_ID);
  }

  void _removeListener(_MultiplexSubscription<T> subscription) {
    assert(identical(subscription._controller, this));
    assert(!identical(subscription._next, subscription));
    subscription._previous._next = subscription._next;
    subscription._next._previous = subscription._previous;
    subscription._next = subscription._previous = subscription;
  }

  // _StreamControllerLifecycle interface.

  void _recordListen(_MultiplexSubscription<T> subscription) {
    _addListener(subscription);
    if (identical(_next, _previous)) {
      // Only one listener, so it must be the first listener.
      _runGuarded(_onListen);
    }
  }

  void _recordCancel(_MultiplexSubscription<T> subscription) {
    if (subscription._isFiring) {
      subscription._setRemoveAfterFiring();
    } else {
      _removeListener(subscription);
      // If we are currently firing an event, the empty-check is performed at
      // the end of the listener loop instead of here.
      if ((_state & _STATE_FIRING) == 0 && _isEmpty) {
        _runGuarded(_onCancel);
      }
    }
  }

  void _recordPause(StreamSubscription<T> subscription) {}
  void _recordResume(StreamSubscription<T> subscription) {}

  // EventSink interface.

  void add(T data) {
    assert(!isClosed);
    if (_isEmpty) return;
    _forEachListener((_BufferingStreamSubscription<T> subscription) {
      subscription._add(data);
    });
  }

  void addError(Object error, [Object stackTrace]) {
    assert(!isClosed);
    if (_isEmpty) return;
    _forEachListener((_BufferingStreamSubscription<T> subscription) {
      subscription._addError(error);
    });
  }

  void close() {
    assert(!isClosed);
    _state |= _STATE_CLOSED;
    if (_isEmpty) return;
    _forEachListener((_MultiplexSubscription<T> subscription) {
      subscription._close();
      subscription._eventState |=
          _MultiplexSubscription._STATE_REMOVE_AFTER_FIRING;
    });
  }

  void _forEachListener(
      void action(_BufferingStreamSubscription<T> subscription)) {
    if ((_state & _STATE_FIRING) != 0) {
      throw new StateError(
          "Cannot fire new event. Controller is already firing an event");
    }
    if (_isEmpty) return;

    // Get event id of this event.
    int id = (_state & _STATE_EVENT_ID);
    // Start firing (set the _STATE_FIRING bit). We don't do [_onCancel]
    // callbacks while firing, and we prevent reentrancy of this function.
    //
    // Set [_state]'s event id to the next event's id.
    // Any listeners added while firing this event will expect the next event,
    // not this one, and won't get notified.
    _state ^= _STATE_EVENT_ID | _STATE_FIRING;
    _MultiplexSubscriptionLink link = _next;
    while (!identical(link, this)) {
      _MultiplexSubscription<T> subscription = link;
      if (subscription._expectsEvent(id)) {
        subscription._eventState |= _MultiplexSubscription._STATE_FIRING;
        action(subscription);
        subscription._toggleEventId();
        link = subscription._next;
        if (subscription._removeAfterFiring) {
          _removeListener(subscription);
        }
        subscription._eventState &= ~_MultiplexSubscription._STATE_FIRING;
      } else {
        link = subscription._next;
      }
    }
    _state &= ~_STATE_FIRING;

    if (_isEmpty) {
      _runGuarded(_onCancel);
    }
  }
}

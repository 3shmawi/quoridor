import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/online_chat.dart';
import '../services/app_strings.dart';
import '../services/online/online_game_controller.dart';

/// Names and colours a seat the way the rest of the screen does.
typedef SeatName = String Function(int seat);
typedef SeatColor = Color Function(int seat);

// --- The face -------------------------------------------------------------

/// A reaction's emoji, moving the way its [QuickChat.motion] says.
///
/// Still when [animate] is false, and always still when the platform asks
/// for reduced motion.
class ChatGlyph extends StatefulWidget {
  const ChatGlyph(this.item, {super.key, this.size = 32, this.animate = true});

  final QuickChat item;
  final double size;
  final bool animate;

  @override
  State<ChatGlyph> createState() => _ChatGlyphState();
}

class _ChatGlyphState extends State<ChatGlyph>
    with SingleTickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: _periodOf(widget.item.motion),
  );

  static Duration _periodOf(ChatMotion motion) => switch (motion) {
    ChatMotion.bounce => const Duration(milliseconds: 700),
    ChatMotion.sway => const Duration(milliseconds: 1600),
    ChatMotion.shake => const Duration(milliseconds: 900),
    ChatMotion.tremble => const Duration(milliseconds: 1000),
    ChatMotion.pulse => const Duration(milliseconds: 1000),
    ChatMotion.float => const Duration(milliseconds: 1800),
    ChatMotion.spin => const Duration(milliseconds: 1600),
    ChatMotion.wave => const Duration(milliseconds: 1000),
    ChatMotion.nod => const Duration(milliseconds: 1100),
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(ChatGlyph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.motion != widget.item.motion) {
      _loop.duration = _periodOf(widget.item.motion);
    }
    _sync();
  }

  void _sync() {
    final moving =
        widget.animate &&
        !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    if (moving && !_loop.isAnimating) {
      _loop.repeat();
    } else if (!moving && _loop.isAnimating) {
      _loop
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final emoji = Text(
      widget.item.emoji,
      // Emoji fonts carry their own colour; a fixed height keeps every face
      // the same size whatever the font's line metrics.
      style: TextStyle(fontSize: size, height: 1.15),
      textAlign: TextAlign.center,
    );
    return SizedBox(
      width: size * 1.3,
      height: size * 1.3,
      child: Center(
        child: AnimatedBuilder(
          animation: _loop,
          child: emoji,
          builder: (context, child) =>
              _move(widget.item.motion, _loop.value, size, child!),
        ),
      ),
    );
  }

  static Widget _move(ChatMotion motion, double t, double size, Widget child) {
    final wave = math.sin(2 * math.pi * t);
    switch (motion) {
      case ChatMotion.bounce:
        return Transform.translate(
          offset: Offset(0, -wave.abs() * size * 0.16),
          child: Transform.rotate(
            angle: math.sin(4 * math.pi * t) * 0.12,
            child: child,
          ),
        );
      case ChatMotion.sway:
        return Transform.rotate(
          angle: wave * 0.2,
          alignment: Alignment.bottomCenter,
          child: child,
        );
      case ChatMotion.shake:
        return Transform.translate(
          offset: Offset(math.sin(12 * math.pi * t) * size * 0.06, 0),
          child: Transform.scale(
            scale: 1 + 0.08 * math.sin(6 * math.pi * t).abs(),
            child: child,
          ),
        );
      case ChatMotion.tremble:
        return Transform.translate(
          offset: Offset(
            math.sin(28 * math.pi * t) * size * 0.03,
            math.cos(22 * math.pi * t) * size * 0.02,
          ),
          child: child,
        );
      case ChatMotion.pulse:
        // Two beats and a rest, like a heart.
        final beat = _bump(t, 0.0, 0.18) + 0.7 * _bump(t, 0.22, 0.4);
        return Transform.scale(scale: 1 + 0.16 * beat, child: child);
      case ChatMotion.float:
        return Transform.translate(
          offset: Offset(0, wave * size * 0.08),
          child: child,
        );
      case ChatMotion.spin:
        final turn = Curves.easeInOutBack.transform((t / 0.6).clamp(0, 1));
        return Transform.translate(
          offset: Offset(0, -_bump(t, 0, 0.6) * size * 0.14),
          child: Transform.rotate(angle: turn * 2 * math.pi, child: child),
        );
      case ChatMotion.wave:
        return Transform.rotate(
          angle: math.sin(4 * math.pi * t) * 0.35,
          alignment: Alignment.bottomCenter,
          child: child,
        );
      case ChatMotion.nod:
        final dip = math.max(0.0, math.sin(4 * math.pi * t));
        return Transform.translate(
          offset: Offset(0, dip * size * 0.08),
          child: Transform.scale(
            scaleY: 1 - dip * 0.06,
            scaleX: 1 + dip * 0.04,
            child: child,
          ),
        );
    }
  }

  /// A smooth 0 → 1 → 0 hump between [from] and [to], flat elsewhere.
  static double _bump(double t, double from, double to) {
    if (t < from || t > to) return 0;
    return math.sin(math.pi * (t - from) / (to - from));
  }
}

// --- Bubbles on the board ---------------------------------------------------

/// Pops each new message up in a corner of the board, then lets it float
/// away.
///
/// The others' messages come in at the top, the side of the board they play
/// from; this device's own come up at the bottom, by the chat button they
/// were sent from. Taps go straight through to the board.
class ChatBubbleLayer extends StatefulWidget {
  const ChatBubbleLayer({
    super.key,
    required this.arrivals,
    required this.localSeat,
    required this.nameOf,
    required this.colorOf,
  });

  final Stream<ChatMessage> arrivals;
  final int? localSeat;
  final SeatName nameOf;
  final SeatColor colorOf;

  /// How long a face stays up. Lines stay a little longer, to be read.
  static const Duration faceLife = Duration(milliseconds: 3200);
  static const Duration lineLife = Duration(milliseconds: 4000);

  /// The most bubbles one corner holds; the oldest leaves for a newer one.
  static const int perCorner = 3;

  @override
  State<ChatBubbleLayer> createState() => _ChatBubbleLayerState();
}

class _ChatBubbleLayerState extends State<ChatBubbleLayer> {
  final List<ChatMessage> _top = [];
  final List<ChatMessage> _bottom = [];
  StreamSubscription<ChatMessage>? _subscription;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(ChatBubbleLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.arrivals != widget.arrivals) {
      _subscription?.cancel();
      _top.clear();
      _bottom.clear();
      _listen();
    }
  }

  void _listen() {
    _subscription = widget.arrivals.listen((message) {
      if (!mounted) return;
      setState(() {
        final corner = message.seat == widget.localSeat ? _bottom : _top;
        corner.add(message);
        if (corner.length > ChatBubbleLayer.perCorner) corner.removeAt(0);
      });
    });
  }

  void _remove(ChatMessage message) {
    if (!mounted) return;
    setState(() {
      _top.remove(message);
      _bottom.remove(message);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          PositionedDirectional(
            top: 4,
            end: 4,
            child: _corner(_top, fromTop: true),
          ),
          PositionedDirectional(
            bottom: 4,
            end: 4,
            child: _corner(_bottom, fromTop: false),
          ),
        ],
      ),
    );
  }

  Widget _corner(List<ChatMessage> messages, {required bool fromTop}) {
    // The newest sits nearest the corner, pushing the older ones inwards.
    final ordered = fromTop ? messages.reversed.toList() : messages;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final message in ordered)
          ChatBubble(
            key: ValueKey(message.id),
            message: message,
            fromTop: fromTop,
            isMine: message.seat == widget.localSeat,
            name: widget.nameOf(message.seat),
            color: widget.colorOf(message.seat),
            onDone: () => _remove(message),
          ),
      ],
    );
  }
}

/// One message on the board: it springs out of its corner, shows its face,
/// and drifts off when its time is up.
class ChatBubble extends StatefulWidget {
  const ChatBubble({
    super.key,
    required this.message,
    required this.fromTop,
    required this.isMine,
    required this.name,
    required this.color,
    required this.onDone,
  });

  final ChatMessage message;
  final bool fromTop;
  final bool isMine;
  final String name;
  final Color color;
  final VoidCallback onDone;

  @override
  State<ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<ChatBubble> with TickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );
  late final AnimationController _exit = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );
  Timer? _life;

  @override
  void initState() {
    super.initState();
    _enter.forward();
    final life = widget.message.item.isLine
        ? ChatBubbleLayer.lineLife
        : ChatBubbleLayer.faceLife;
    _life = Timer(life, _leave);
  }

  Future<void> _leave() async {
    if (!mounted) return;
    await _exit.forward();
    if (mounted) widget.onDone();
  }

  @override
  void dispose() {
    _life?.cancel();
    _enter.dispose();
    _exit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final item = widget.message.item;
    final label = context.l10n.chatLabel(item);
    final corner = widget.fromTop
        ? AlignmentDirectional.topEnd
        : AlignmentDirectional.bottomEnd;

    final background = widget.isMine
        ? Color.alphaBlend(widget.color.withValues(alpha: 0.22), scheme.surface)
        : scheme.surface;

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ChatGlyph(item, size: item.isLine ? 26 : 38),
        if (item.isLine) ...[
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ],
    );

    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 230),
      padding: EdgeInsets.fromLTRB(
        10,
        widget.fromTop ? 14 : 6,
        10,
        widget.fromTop ? 6 : 14,
      ),
      decoration: ShapeDecoration(
        color: background,
        shape: ChatBubbleShape(
          tailAtTop: widget.fromTop,
          side: BorderSide(
            color: widget.color.withValues(alpha: 0.9),
            width: 2,
          ),
        ),
        shadows: [
          BoxShadow(
            color: widget.color.withValues(alpha: 0.35),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: content,
    );

    // Who said it, unless it was this device.
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (!widget.fromTop) bubble,
        if (!widget.isMine)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                widget.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        if (widget.fromTop) bubble,
      ],
    );

    return Semantics(
      liveRegion: true,
      label: widget.isMine ? label : '${widget.name}: $label',
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: AnimatedBuilder(
          animation: Listenable.merge([_enter, _exit]),
          child: ExcludeSemantics(child: body),
          builder: (context, child) {
            final pop = Curves.elasticOut.transform(_enter.value);
            final fade = Curves.easeOut.transform(
              (_enter.value * 3).clamp(0.0, 1.0),
            );
            final away = Curves.easeIn.transform(_exit.value);
            return Opacity(
              opacity: (fade * (1 - away)).clamp(0.0, 1.0),
              child: Transform.translate(
                // Leaving, it rises like a let-go balloon.
                offset: Offset(0, -away * 22),
                child: Transform.rotate(
                  angle: (1 - _enter.value) * -0.25,
                  alignment: corner.resolve(Directionality.of(context)),
                  child: Transform.scale(
                    scale: (0.25 + 0.75 * pop) * (1 - away * 0.25),
                    alignment: corner.resolve(Directionality.of(context)),
                    child: child,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// A rounded speech bubble whose tail points into its corner of the board.
class ChatBubbleShape extends ShapeBorder {
  const ChatBubbleShape({
    required this.tailAtTop,
    this.side = BorderSide.none,
    this.radius = 18,
    this.tail = 9,
  });

  final bool tailAtTop;
  final BorderSide side;
  final double radius;
  final double tail;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  Path _path(Rect rect, TextDirection? direction) {
    final rtl = direction == TextDirection.rtl;
    // The body leaves room for the tail on its side.
    final body = tailAtTop
        ? Rect.fromLTRB(rect.left, rect.top + tail, rect.right, rect.bottom)
        : Rect.fromLTRB(rect.left, rect.top, rect.right, rect.bottom - tail);
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(body, Radius.circular(radius)));

    // Near the end edge, where the corner is.
    final x = rtl ? body.left + radius + 4 : body.right - radius - 4;
    final edge = tailAtTop ? body.top : body.bottom;
    final tip = tailAtTop ? rect.top : rect.bottom;
    final lean = rtl ? -tail * 0.6 : tail * 0.6;
    final tailPath = Path()
      ..moveTo(x - tail, edge)
      ..quadraticBezierTo(x + lean * 0.4, edge, x + lean, tip)
      ..quadraticBezierTo(x + lean * 0.2, edge, x + tail * 0.4, edge)
      ..close();
    return Path.combine(PathOperation.union, path, tailPath);
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _path(rect.deflate(side.width), textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      _path(rect, textDirection);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width == 0) return;
    canvas.drawPath(
      _path(rect.deflate(side.width / 2), textDirection),
      side.toPaint(),
    );
  }

  @override
  ShapeBorder scale(double t) => ChatBubbleShape(
    tailAtTop: tailAtTop,
    side: side.scale(t),
    radius: radius * t,
    tail: tail * t,
  );
}

// --- The button -------------------------------------------------------------

/// Opens the chat. Counts what came in unread, and gives a wiggle each time
/// something does, so a message is noticed even when its bubble was missed.
class ChatButton extends StatefulWidget {
  const ChatButton({
    super.key,
    required this.unread,
    required this.onPressed,
    this.arrivals,
    this.localSeat,
  });

  final int unread;
  final VoidCallback onPressed;
  final Stream<ChatMessage>? arrivals;
  final int? localSeat;

  @override
  State<ChatButton> createState() => _ChatButtonState();
}

class _ChatButtonState extends State<ChatButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wiggle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  StreamSubscription<ChatMessage>? _subscription;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(ChatButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.arrivals != widget.arrivals) {
      _subscription?.cancel();
      _listen();
    }
  }

  void _listen() {
    _subscription = widget.arrivals?.listen((message) {
      if (mounted && message.seat != widget.localSeat) {
        _wiggle.forward(from: 0);
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _wiggle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final unread = widget.unread;
    return Tooltip(
      message: unread > 0 ? context.l10n.chatUnread(unread) : context.l10n.chat,
      child: AnimatedBuilder(
        animation: _wiggle,
        builder: (context, child) {
          final t = _wiggle.value;
          final fade = 1 - t;
          return Transform.rotate(
            angle: math.sin(t * math.pi * 6) * 0.3 * fade,
            child: Transform.scale(
              scale: 1 + math.sin(t * math.pi) * 0.18,
              child: child,
            ),
          );
        },
        child: SizedBox(
          width: 42,
          height: 42,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Material(
                  color: scheme.primary,
                  shape: const CircleBorder(),
                  elevation: 2,
                  child: InkWell(
                    key: const Key('chatButton'),
                    customBorder: const CircleBorder(),
                    onTap: widget.onPressed,
                    child: Icon(
                      Icons.add_reaction_rounded,
                      size: 22,
                      color: scheme.onPrimary,
                    ),
                  ),
                ),
              ),
              PositionedDirectional(
                top: -4,
                end: -4,
                child: AnimatedScale(
                  scale: unread > 0 ? 1 : 0,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutBack,
                  child: Container(
                    key: const Key('chatUnread'),
                    constraints: const BoxConstraints(minWidth: 18),
                    height: 18,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: scheme.error,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: scheme.surface, width: 1.5),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      unread > 9 ? '9+' : '$unread',
                      style: TextStyle(
                        fontSize: 10,
                        height: 1,
                        fontWeight: FontWeight.bold,
                        color: scheme.onError,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- The sheet ----------------------------------------------------------------

/// Opens the chat: the conversation so far above, and every face and line
/// below, one tap from being sent. Sending closes it, so the bubble is seen
/// popping up on the board.
Future<void> showChatSheet(
  BuildContext context, {
  required OnlineGameController controller,
  required SeatName nameOf,
  required SeatColor colorOf,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) =>
        ChatSheet(controller: controller, nameOf: nameOf, colorOf: colorOf),
  );
}

class ChatSheet extends StatefulWidget {
  const ChatSheet({
    super.key,
    required this.controller,
    required this.nameOf,
    required this.colorOf,
  });

  final OnlineGameController controller;
  final SeatName nameOf;
  final SeatColor colorOf;

  @override
  State<ChatSheet> createState() => _ChatSheetState();
}

class _ChatSheetState extends State<ChatSheet> {
  /// What was already there when the sheet opened; only later messages
  /// slide in.
  late final Set<String> _seen = {for (final m in widget.controller.chat) m.id};

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    // After this frame: the page under the sheet rebuilds on it.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.controller.markChatRead(),
    );
  }

  void _changed() {
    if (!mounted) return;
    // Anything arriving while the chat is open has been read.
    if (widget.controller.unreadChat > 0) widget.controller.markChatRead();
    setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  Future<void> _send(QuickChat item) async {
    if (!widget.controller.canChat) {
      HapticFeedback.heavyImpact();
      return;
    }
    HapticFeedback.lightImpact();
    Navigator.of(context).pop();
    await widget.controller.sendChat(item);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    final controller = widget.controller;

    return Container(
      constraints: BoxConstraints(maxHeight: media.size.height * 0.8),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: EdgeInsets.only(bottom: media.padding.bottom + 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: scheme.outline.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Row(
              children: [
                Icon(Icons.forum_rounded, color: scheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  context.l10n.chat,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: math.min(200, media.size.height * 0.24),
            child: _history(controller),
          ),
          Divider(height: 1, color: scheme.outline.withValues(alpha: 0.2)),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle(context.l10n.chatFaces),
                  _faces(),
                  const SizedBox(height: 14),
                  _sectionTitle(context.l10n.chatLines),
                  _lines(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4, right: 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          letterSpacing: 1.1,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface.withValues(alpha: 0.5),
        ),
      ),
    );
  }

  Widget _history(OnlineGameController controller) {
    final messages = controller.chat;
    if (messages.isEmpty) {
      final scheme = Theme.of(context).colorScheme;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ChatGlyph(QuickChat.hello, size: 34),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                context.l10n.chatEmpty,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: scheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final localSeat = controller.localPlayerId;
    // Reversed, so the list starts at the newest and stays there as more
    // come in.
    return ListView.builder(
      key: const Key('chatHistory'),
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final position = messages.length - 1 - index;
        final message = messages[position];
        // A run of messages from one player is named once, at its start.
        final startsRun =
            position == 0 || messages[position - 1].seat != message.seat;
        return _HistoryRow(
          key: ValueKey(message.id),
          message: message,
          startsRun: startsRun,
          isMine: message.seat == localSeat,
          name: widget.nameOf(message.seat),
          color: widget.colorOf(message.seat),
          slideIn: !_seen.contains(message.id),
        );
      },
    );
  }

  Widget _faces() {
    final faces = QuickChat.faces;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Six across on a phone, more when there is room for them.
        final columns = math.max(6, (constraints.maxWidth / 72).floor());
        final cell = constraints.maxWidth / columns;
        return Wrap(
          children: [
            for (var i = 0; i < faces.length; i++)
              SizedBox(
                width: cell,
                height: cell.clamp(48, 64),
                child: _PopIn(
                  delay: Duration(milliseconds: 30 * i),
                  child: _FaceKey(
                    item: faces[i],
                    label: context.l10n.chatLabel(faces[i]),
                    onTap: () => _send(faces[i]),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _lines() {
    final scheme = Theme.of(context).colorScheme;
    final lines = QuickChat.lines;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < lines.length; i++)
          _PopIn(
            delay: Duration(milliseconds: 200 + 30 * i),
            child: Material(
              color: scheme.primary.withValues(alpha: 0.08),
              shape: StadiumBorder(
                side: BorderSide(color: scheme.primary.withValues(alpha: 0.25)),
              ),
              child: InkWell(
                key: Key('chat_${lines[i].name}'),
                customBorder: const StadiumBorder(),
                onTap: () => _send(lines[i]),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        lines[i].emoji,
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        context.l10n.chatLabel(lines[i]),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A face in the picker. It plays its motion while held or hovered, so the
/// player sees what it will do before sending it.
class _FaceKey extends StatefulWidget {
  const _FaceKey({
    required this.item,
    required this.label,
    required this.onTap,
  });

  final QuickChat item;
  final String label;
  final VoidCallback onTap;

  @override
  State<_FaceKey> createState() => _FaceKeyState();
}

class _FaceKeyState extends State<_FaceKey> {
  bool _active = false;

  void _set(bool value) {
    if (_active != value) setState(() => _active = value);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: widget.label,
      child: InkWell(
        key: Key('chat_${widget.item.name}'),
        borderRadius: BorderRadius.circular(16),
        onTap: widget.onTap,
        onHighlightChanged: _set,
        onHover: _set,
        child: AnimatedScale(
          scale: _active ? 1.15 : 1,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutBack,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: _active
                  ? scheme.primary.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: ChatGlyph(widget.item, size: 28, animate: _active),
            ),
          ),
        ),
      ),
    );
  }
}

/// One message in the conversation: the others' on the start side with
/// their name, this device's own on the end side in its colour.
class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    super.key,
    required this.message,
    required this.startsRun,
    required this.isMine,
    required this.name,
    required this.color,
    required this.slideIn,
  });

  final ChatMessage message;
  final bool startsRun;
  final bool isMine;
  final String name;
  final Color color;
  final bool slideIn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = context.l10n.chatLabel(message.item);

    final bubble = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isMine
            ? color.withValues(alpha: 0.18)
            : scheme.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadiusDirectional.only(
          topStart: const Radius.circular(16),
          topEnd: const Radius.circular(16),
          bottomStart: Radius.circular(isMine ? 16 : 4),
          bottomEnd: Radius.circular(isMine ? 4 : 16),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message.item.emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: message.item.isLine
                    ? FontWeight.w600
                    : FontWeight.w400,
                fontStyle: message.item.isLine
                    ? FontStyle.normal
                    : FontStyle.italic,
                color: scheme.onSurface.withValues(
                  alpha: message.item.isLine ? 1 : 0.7,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    final time = Text(
      _ago(context, message.sentAt),
      style: TextStyle(
        fontSize: 10,
        color: scheme.onSurface.withValues(alpha: 0.4),
      ),
    );

    final avatar = CircleAvatar(
      radius: 12,
      backgroundColor: color,
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: isMine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMine) ...[
            // Later messages in a run line up under the first one's avatar.
            if (startsRun) avatar else const SizedBox(width: 24),
            const SizedBox(width: 6),
          ],
          if (isMine) ...[time, const SizedBox(width: 6)],
          Flexible(
            child: Column(
              crossAxisAlignment: isMine
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isMine && startsRun)
                  Padding(
                    padding: const EdgeInsets.only(
                      bottom: 2,
                      left: 4,
                      right: 4,
                    ),
                    child: Text(
                      name,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ),
                bubble,
              ],
            ),
          ),
          if (!isMine) ...[const SizedBox(width: 6), time],
        ],
      ),
    );

    if (!slideIn) return row;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 16),
          child: child,
        ),
      ),
      child: row,
    );
  }

  static String _ago(BuildContext context, DateTime? sentAt) {
    if (sentAt == null) return context.l10n.chatJustNow;
    final minutes = DateTime.now().difference(sentAt).inMinutes;
    return minutes < 1
        ? context.l10n.chatJustNow
        : context.l10n.chatMinutesAgo(minutes);
  }
}

/// Springs [child] in after [delay], once, when it is first built.
class _PopIn extends StatefulWidget {
  const _PopIn({required this.delay, required this.child});

  final Duration delay;
  final Widget child;

  @override
  State<_PopIn> createState() => _PopInState();
}

class _PopInState extends State<_PopIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  Timer? _start;

  @override
  void initState() {
    super.initState();
    _start = Timer(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _start?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = Curves.easeOutBack.transform(_controller.value);
        return Opacity(
          opacity: _controller.value,
          child: Transform.scale(scale: 0.6 + 0.4 * t, child: child),
        );
      },
    );
  }
}

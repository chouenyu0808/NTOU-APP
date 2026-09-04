import 'package:flutter/material.dart';

import '../transit/transit_models.dart' show ArrivalTone;
import '../ui/theme.dart';
import 'timetable_widget_data.dart';
import 'transit_widget_data.dart';

/// 桌面小組件畫的那張圖。
///
/// **這裡的東西是被 `HomeWidget.renderFlutterWidget` 離線畫成 PNG 的，
/// 不是掛在 App 的 widget tree 上。** 三個後果，每一個都會安靜地出錯：
///
/// - **沒有 `MaterialApp`，也就沒有 `Theme.of(context)`。** 顏色一律從
///   [NtouTheme.of] 自己取，不要用 `Theme.of` —— 拿到的會是 Flutter 的
///   預設紫色主題，畫面上「有顏色」所以看不出是錯的。
/// - **沒有 `DefaultTextStyle`。** 每一段字都要自己帶完整的 [TextStyle]，
///   少帶 color 的話畫出來是 debug 用的黃底紅字。
/// - **高度必須寫死。** render 的時候外面包的是 `Column`，它給子元素的
///   主軸約束是無限的 —— 沒有 [SizedBox] 就是 unbounded height 例外。
///
/// 尺寸從原生那邊傳過來（使用者可以把小組件拉大縮小），所以塞得下幾列
/// 是**畫的時候算的**，不是 payload 先砍好的。

/// 小組件外框的圓角。跟 Android 12 的 `system_app_widget_background_radius`
/// 對齊 —— 差太多的話貼在桌面上會跟旁邊的小組件形狀不一樣。
const double _kRadius = 16;

const EdgeInsets _kPad = EdgeInsets.fromLTRB(14, 12, 14, 10);

/// 右上角留給原生那顆重新整理鈕的位置。
///
/// **按鈕不能畫進 PNG 裡** —— 圖是不能點的。真正的按鈕是 layout 疊在
/// ImageView 上面的 `ImageButton`，這裡只是把字讓開，不然會被蓋住。
const double _kActionSlot = 36;

/// 「還有 N 堂」那一行的高度。**刻意比一整列矮很多** ——
/// 理由見 [TimetableWidgetView._rows]。
const double _kMoreHeight = 18;

// ---------------------------------------------------------------- 課表

/// 課表小組件。
class TimetableWidgetView extends StatelessWidget {
  const TimetableWidgetView({
    super.key,
    required this.payload,
    required this.size,
    required this.brightness,
  });

  final TimetableWidgetPayload payload;
  final Size size;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    final scheme = NtouTheme.of(brightness).colorScheme;
    const rowHeight = 44.0;
    const headerHeight = 34.0;

    final body = size.height - headerHeight - _kPad.vertical;

    return _Shell(
      size: size,
      scheme: scheme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: headerHeight,
            child: _Header(
              title: payload.dateLabel,
              subtitle: payload.weekdayLabel,
              badge: _statusBadge,
              scheme: scheme,
            ),
          ),
          Expanded(
            child: payload.isEmpty
                ? _Empty(text: payload.emptyMessage ?? '今天沒有課', scheme: scheme)
                : _rows(scheme, body, rowHeight),
          ),
        ],
      ),
    );
  }

  /// 右上角那個小標。
  ///
  /// 三種話分得很清楚，因為使用者的下一步完全不同：**「現在」是已經在上課
  /// （可能遲到了）、「下一堂」是還沒開始、「今天結束」是可以走了。**
  /// 節次時間表不可用時說「今天第一堂」—— 那時候我們分不出哪幾堂上完了，
  /// 說「下一堂」會是錯的，跟首頁那張卡片同一套規則。
  String? get _statusBadge {
    if (payload.isEmpty) return null;
    if (!payload.timesKnown) return '今天第一堂';
    if (payload.highlightIndex < 0) return '今天結束';
    return payload.highlightStarted ? '現在' : '下一堂';
  }

  Widget _rows(ColorScheme scheme, double body, double rowHeight) {
    final rows = payload.rows;
    if (rows.isEmpty || body < rowHeight) return const SizedBox.shrink();

    // 全部塞得下就全部畫，不留「還有 N 堂」那一行的位置。
    final fits = (body / rowHeight).floor();
    if (rows.length <= fits) {
      return _column(rows, 0, rows.length, 0, scheme, rowHeight);
    }

    // 塞不下：**寧可少顯示一堂也要說有東西被藏起來** —— 直接切掉的話
    // 畫面上跟「今天就這幾堂」長得一模一樣。
    //
    // 那一行用 [_kMoreHeight]，不是一整列的高度。小尺寸時（只塞得下一列）
    // 讓它吃掉一整列的話，畫面上就會變成一堂課都沒有、只有一句
    // 「還有 6 堂」—— 那比不說還糟。
    final visible = ((body - _kMoreHeight) / rowHeight).floor().clamp(1, rows.length);

    // 把視窗捲到反白那一列 —— **不是永遠從第一堂開始切。** 下午四點的時候
    // 使用者要看的是接下來那堂，不是早上已經上完的兩堂。
    //
    // 塞得下兩列以上才往前多留一列當脈絡；只塞得下一列的時候往前留就等於
    // 把反白那堂本身擠出畫面，那正好是唯一非看不可的一列。
    var start = 0;
    if (payload.highlightIndex >= 0) {
      final lead = visible >= 2 ? 1 : 0;
      start = (payload.highlightIndex - lead).clamp(0, rows.length - visible);
    }

    return _column(
      rows,
      start,
      start + visible,
      rows.length - (start + visible),
      scheme,
      rowHeight,
    );
  }

  Widget _column(
    List<TimetableWidgetRow> rows,
    int start,
    int end,
    int hiddenAfter,
    ColorScheme scheme,
    double rowHeight,
  ) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = start; i < end; i++)
            SizedBox(
              height: rowHeight,
              child: _CourseRow(
                row: rows[i],
                highlight: i == payload.highlightIndex,
                scheme: scheme,
              ),
            ),
          if (hiddenAfter > 0)
            SizedBox(
              height: _kMoreHeight,
              child: _More(text: '還有 $hiddenAfter 堂', scheme: scheme),
            ),
        ],
      );
}

class _CourseRow extends StatelessWidget {
  const _CourseRow({
    required this.row,
    required this.highlight,
    required this.scheme,
  });

  final TimetableWidgetRow row;
  final bool highlight;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    // 上完的變淡，但**不要淡到看不見** —— 使用者還是會想確認「我剛才那堂
    // 是不是在這間教室」。0.45 是還讀得出來的下限。
    final fade = row.done ? 0.45 : 1.0;
    final fg = highlight ? scheme.onPrimaryContainer : scheme.onSurface;
    final sub =
        highlight ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;

    return Opacity(
      opacity: fade,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: highlight
            ? BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              )
            : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 節次和時間固定寬度。**不要跟著字數縮放** ——「第1節」和
            // 「第10-12節」寬度不同的話，整欄的課名會左右參差，
            // 而這一欄是拿來上下掃的。
            SizedBox(
              width: 74,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    row.period,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.15,
                      fontWeight: FontWeight.w600,
                      color: sub,
                    ),
                  ),
                  if (row.time.isNotEmpty)
                    Text(
                      row.time,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: TextStyle(
                        fontSize: 10,
                        height: 1.2,
                        color: sub,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    row.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
                  ),
                  if (row.room.isNotEmpty)
                    Text(
                      row.room,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, height: 1.25, color: sub),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- 交通

/// 交通小組件。
class TransitWidgetView extends StatelessWidget {
  const TransitWidgetView({
    super.key,
    required this.payload,
    required this.size,
    required this.brightness,
  });

  final TransitWidgetPayload payload;
  final Size size;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    final scheme = NtouTheme.of(brightness).colorScheme;
    const rowHeight = 30.0;
    const stopHeight = 22.0;
    const headerHeight = 34.0;

    final body = size.height - headerHeight - _kPad.vertical;

    return _Shell(
      size: size,
      scheme: scheme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: headerHeight,
            child: _Header(
              title: '交通',
              subtitle: _timeLabel,
              // 右上角那個位置是重新整理鈕的，所以這裡不放標。
              badge: null,
              reserveAction: true,
              scheme: scheme,
              subtitleColor: payload.refreshFailed ? scheme.error : null,
            ),
          ),
          Expanded(
            child: payload.stops.isEmpty
                ? _Empty(text: '還沒有交通資料', scheme: scheme)
                : _body(scheme, body, rowHeight, stopHeight),
          ),
        ],
      ),
    );
  }

  /// 「資料時間 10:32」。
  ///
  /// **一定要有。** Android 小組件最快只能 30 分鐘自動更新一次，所以上面的
  /// 「12 分」必然是舊的 —— 不標時間的話它跟即時資料長得一模一樣，
  /// 使用者會照著出門。更新失敗時把這件事講出來，而且**不動時間**：
  /// 那個時間講的是資料多舊，拿失敗的時刻蓋上去等於謊報新鮮度。
  String get _timeLabel {
    final at = payload.updatedAt;
    if (at == null) return payload.refreshFailed ? '更新失敗' : '尚未更新';
    final hhmm = '${at.hour.toString().padLeft(2, '0')}'
        ':${at.minute.toString().padLeft(2, '0')}';
    return payload.refreshFailed ? '$hhmm 的資料 · 更新失敗' : '資料時間 $hhmm';
  }

  Widget _body(
    ColorScheme scheme,
    double body,
    double rowHeight,
    double stopHeight,
  ) {
    // 由上往下填，填滿為止。**取捨在這裡做不在 payload** ——
    // 使用者把小組件拉大就會多看到幾列，那是他期待的行為。
    final children = <Widget>[];
    var used = 0.0;

    for (final stop in payload.stops) {
      if (used + stopHeight > body) break;
      children.add(
        SizedBox(
          height: stopHeight,
          child: _StopHeading(name: stop.name, scheme: scheme),
        ),
      );
      used += stopHeight;

      final note = stop.note;
      if (note != null) {
        if (used + stopHeight > body) break;
        children.add(
          SizedBox(
            height: stopHeight,
            child: Text(
              note,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                height: 1.4,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        );
        used += stopHeight;
        continue;
      }

      for (final row in stop.rows) {
        if (used + rowHeight > body) break;
        children.add(
          SizedBox(
            height: rowHeight,
            child: _ArrivalRow(row: row, scheme: scheme),
          ),
        );
        used += rowHeight;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

class _StopHeading extends StatelessWidget {
  const _StopHeading({required this.name, required this.scheme});

  final String name;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            height: 1.2,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: scheme.onSurfaceVariant,
          ),
        ),
      );
}

class _ArrivalRow extends StatelessWidget {
  const _ArrivalRow({required this.row, required this.scheme});

  final TransitWidgetRow row;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    // 跟交通分頁同一組配色，不要在這裡另外訂一套 ——
    // 「進站中」在 App 裡是紅的、在桌面上是灰的，會讓人以為看錯了。
    final color = switch (row.tone) {
      ArrivalTone.now => scheme.error,
      ArrivalTone.soon => scheme.primary,
      ArrivalTone.normal => scheme.onSurface,
      ArrivalTone.idle => scheme.onSurfaceVariant,
    };

    return Row(
      children: [
        // 路線號固定寬度，理由跟交通分頁一樣：「103」和「1579」寬度不同的話
        // 整欄的「往哪裡」會左右參差。
        SizedBox(
          width: 46,
          child: Text(
            row.route,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: TextStyle(
              fontSize: 13,
              height: 1.2,
              fontWeight: FontWeight.w700,
              color: row.favorite ? scheme.primary : scheme.onSurface,
            ),
          ),
        ),
        Expanded(
          child: Text(
            row.towards,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              height: 1.2,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 6),
        // 到站時間是這一頁的主角，右對齊成一欄讓人上下掃。
        SizedBox(
          width: 76,
          child: Text(
            row.eta,
            maxLines: 1,
            overflow: TextOverflow.clip,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 13,
              height: 1.2,
              fontWeight: FontWeight.w700,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- 共用零件

/// 小組件的外框：圓角、底色、內距、固定尺寸。
class _Shell extends StatelessWidget {
  const _Shell({
    required this.size,
    required this.scheme,
    required this.child,
  });

  final Size size;
  final ColorScheme scheme;
  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size.width,
        height: size.height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            // **不透明。** 半透明的底配上使用者自己的桌布，對比度就變成
            // 隨機的，而我們完全沒辦法測。
            color: scheme.surface,
            borderRadius: BorderRadius.circular(_kRadius),
          ),
          child: Padding(padding: _kPad, child: child),
        ),
      );
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.scheme,
    this.reserveAction = false,
    this.subtitleColor,
  });

  final String title;
  final String subtitle;
  final String? badge;
  final ColorScheme scheme;

  /// 右上角要留給原生那顆重新整理鈕。
  final bool reserveAction;

  final Color? subtitleColor;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.3,
                    color: subtitleColor ?? scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (badge != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                badge!,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ),
          if (reserveAction) const SizedBox(width: _kActionSlot),
        ],
      );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text, required this.scheme});

  final String text;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) => Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            height: 1.4,
            color: scheme.onSurfaceVariant,
          ),
        ),
      );
}

class _More extends StatelessWidget {
  const _More({required this.text, required this.scheme});

  final String text;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 8, top: 2),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            height: 1.2,
            color: scheme.onSurfaceVariant,
          ),
        ),
      );
}

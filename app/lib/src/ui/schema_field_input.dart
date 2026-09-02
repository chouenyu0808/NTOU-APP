import 'package:flutter/material.dart';

import '../ais/form_schema.dart';

/// 學校那一頁上的一個欄位，畫成 App 上的一格。
///
/// **只有這一份。** 通用功能頁和畢業必修頁以前各自抄了一份 `_FieldInput`，
/// 兩份還長得不一樣 —— 畢業必修那份對「不是下拉」的欄位一律畫成
/// disabled 的 TextField，等於學校哪天在那一頁加一個文字條件，那一格就是死的。
///
/// 欄位的種類全部由 [SchemaField.kind] 決定，而那是從學校頁面自己的宣告讀出來的。
class SchemaFieldInput extends StatelessWidget {
  const SchemaFieldInput({
    super.key,
    required this.field,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final SchemaField field;
  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  bool get _live => enabled && !field.readOnly;

  @override
  Widget build(BuildContext context) {
    // 0 個選項的下拉。送出去會踩 event validation，所以擋在這裡，
    // 並且說清楚要先動哪一格 —— 不然使用者只會覺得這個欄位壞了。
    if (field.needsCascade) {
      return _frozen(context, '', helper: '要先選上面的條件，這一格才會有選項');
    }

    // 不要畫成文字框 —— 使用者會在裡面打字，然後送出一個伺服器看不懂的值，
    // 而失敗訊息不會提到檔案。
    if (field.kind == FieldKind.file) {
      return _frozen(context, '', icon: Icons.attach_file);
    }

    return switch (field.kind) {
      FieldKind.select => _select(context),
      FieldKind.radio => _choices(context),
      FieldKind.checkboxes => _checkboxes(context),
      FieldKind.textarea => _text(context, lines: 4),
      _ => _text(context, lines: 1),
    };
  }

  /// 學校標成 disabled 的欄位（自己的性別、學生類別那一類）。
  ///
  /// 顯示但不能改 —— 那是使用者的資料，藏起來只會讓他以為 App 沒抓到。
  /// 送出時也不會送（見 `AisRepository._sendable`），跟瀏覽器一致。
  Widget _frozen(
    BuildContext context,
    String text, {
    String? helper,
    IconData? icon,
  }) =>
      TextField(
        enabled: false,
        controller: TextEditingController(text: text),
        decoration: InputDecoration(
          labelText: field.label,
          border: const OutlineInputBorder(),
          helperText: helper,
          helperMaxLines: 2,
          prefixIcon: icon == null ? null : Icon(icon, size: 20),
        ),
      );

  Widget _select(BuildContext context) {
    if (field.readOnly) {
      final current = field.options
          .where((o) => o.value == value)
          .map((o) => o.label)
          .firstOrNull;
      return _frozen(context, current ?? value, helper: '學校鎖住了這一格，不能改');
    }

    final values = field.options.map((o) => o.value).toList();
    return DropdownButtonFormField<String>(
      initialValue: values.contains(value) ? value : values.firstOrNull,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: field.label,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final o in field.options)
          DropdownMenuItem(
            value: o.value,
            child: Text(o.label, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: _live ? (v) => onChanged(v ?? '') : null,
    );
  }

  /// 單選（一組同名的 radio）。
  ///
  /// 用 chip 不用 `RadioListTile`：這種組多半只有兩三個選項（課號 / 課名 / 老師），
  /// 一個選項佔一整列會把表單拉得很長，而且跟旁邊的下拉看起來不像同一種東西。
  Widget _choices(BuildContext context) => _group(
        context,
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final o in field.options)
              ChoiceChip(
                label: Text(o.label),
                selected: o.value == value,
                onSelected: _live ? (_) => onChanged(o.value) : null,
              ),
          ],
        ),
      );

  /// 複選（ASP.NET 的 CheckBoxList）。
  ///
  /// 這一組在 schema 裡是**一個**欄位，選中的存的是各自的欄位名
  /// （`M_PRESENT_TYPE$0`），送出時才展開 —— 見 `AisRepository._sendable`。
  Widget _checkboxes(BuildContext context) {
    final checked = SchemaField.splitChecked(value).toSet();
    return _group(
      context,
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final o in field.options)
            FilterChip(
              label: Text(o.label),
              selected: checked.contains(o.value),
              onSelected: _live
                  ? (on) {
                      final next = {...checked};
                      if (on) {
                        next.add(o.value);
                      } else {
                        next.remove(o.value);
                      }
                      // 照 options 的順序輸出，不要照使用者點的順序 ——
                      // 存檔和重畫之間值才會穩定。
                      onChanged(SchemaField.joinChecked(
                        field.options
                            .map((x) => x.value)
                            .where(next.contains),
                      ));
                    }
                  : null,
            ),
        ],
      ),
    );
  }

  /// chip 群組共用的外框，讓它跟旁邊的下拉、文字框對得齊。
  Widget _group(BuildContext context, {required Widget child}) {
    final theme = Theme.of(context);
    return InputDecorator(
      decoration: InputDecoration(
        labelText: field.label,
        border: const OutlineInputBorder(),
        helperText: field.readOnly ? '學校鎖住了這一組，不能改' : null,
        contentPadding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      ),
      child: DefaultTextStyle.merge(
        style: theme.textTheme.bodyMedium,
        child: child,
      ),
    );
  }

  Widget _text(BuildContext context, {required int lines}) {
    if (field.readOnly) {
      return _frozen(context, value, helper: '學校鎖住了這一格，不能改');
    }
    return TextFormField(
      // `key` 綁著現值：連動 postback 之後伺服器可能重填這一格，
      // 沒有 key 的話 `initialValue` 只在建立時生效，畫面會停在舊的值。
      key: ValueKey('${field.name}:$value'),
      initialValue: value,
      enabled: enabled,
      maxLength: field.maxLength,
      maxLines: field.kind == FieldKind.password ? 1 : lines,
      minLines: field.kind == FieldKind.password ? 1 : lines,
      obscureText: field.kind == FieldKind.password,
      keyboardType: switch (field.kind) {
        FieldKind.number => TextInputType.number,
        FieldKind.textarea => TextInputType.multiline,
        _ => null,
      },
      decoration: InputDecoration(
        labelText: field.label,
        border: const OutlineInputBorder(),
        alignLabelWithHint: lines > 1,
        // 長文字（自傳 2000 字）要看得到還剩多少；短欄位不要那行字佔位置。
        counterText: field.kind == FieldKind.textarea ? null : '',
      ),
      onChanged: onChanged,
    );
  }
}

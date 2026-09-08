import 'package:flutter/material.dart';

import '../ais/exceptions.dart';
import '../parsing/announcement_detail.dart';
import '../parsing/announcements.dart';
import 'app_controller.dart';

/// 一則公告的全文。
///
/// 點進來時手上已經有標題、日期、單位（清單那一列傳過來的），先把它們畫出來
/// —— 內文要再打一次學校的伺服器，那幾秒裡至少讓使用者確認「點對了」。
class AnnouncementDetailPage extends StatefulWidget {
  const AnnouncementDetailPage({
    super.key,
    required this.controller,
    required this.summary,
  });

  final AppController controller;

  /// 清單那一列的公告 —— 標題、日期、單位、還有點開內文要用的 id。
  final Announcement summary;

  @override
  State<AnnouncementDetailPage> createState() =>
      _AnnouncementDetailPageState();
}

class _AnnouncementDetailPageState extends State<AnnouncementDetailPage> {
  AnnouncementDetail? _detail;
  String? _error;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final path = widget.summary.detailPath;
    if (path == null) {
      setState(() {
        _busy = false;
        _error = '這則公告沒有編號，打不開全文。';
      });
      return;
    }
    try {
      final html = await widget.controller.repository.fetchAnnouncement(path);
      _detail = parseAnnouncementDetail(html);
    } on AisException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = '發生未預期的錯誤（${e.runtimeType}）。';
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('公告')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          // 標題／日期／單位先用清單傳來的畫，不必等內文回來。
          Text(
            widget.summary.title,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          _MetaLine(summary: widget.summary, detail: _detail),
          const Divider(height: 32),
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            _ErrorBody(message: _error!, onRetry: _load)
          else if (_detail != null)
            _DetailBody(detail: _detail!),
        ],
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.summary, this.detail});

  final Announcement summary;
  final AnnouncementDetail? detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 單位以內文頁的為準（比較完整），還沒回來就先用清單那一列的。
    final unit = (detail?.unit.isNotEmpty ?? false) ? detail!.unit : summary.unit;
    final parts = [
      if (summary.date != null)
        '${summary.date!.year}/${summary.date!.month}/${summary.date!.day}',
      if (unit.isNotEmpty) unit,
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Text(
      parts.join('　·　'),
      style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.detail});

  final AnnouncementDetail detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (detail.hasBody)
          SelectableText(
            detail.body,
            style: const TextStyle(height: 1.6),
          )
        else
          Text(
            '這則公告沒有內文。',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        const SizedBox(height: 24),
        // 底下這些是次要資訊，有才顯示。附件的「無」也顯示 —— 使用者想確認
        // 「是不是漏了附件」，一個明確的「無」比空白讓人安心。
        for (final row in [
          ('登載期間', detail.postingPeriod),
          ('附件', detail.attachment),
          ('承辦人', detail.handler),
          ('聯絡方式', detail.contact),
          ('發文字號', detail.documentNo),
          ('速別', detail.priority),
        ])
          if (row.$2.isNotEmpty) _MetaRow(label: row.$1, value: row.$2),
      ],
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        const SizedBox(height: 24),
        Icon(Icons.error_outline, size: 36, color: scheme.error),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        FilledButton.tonal(onPressed: onRetry, child: const Text('重試')),
      ],
    );
  }
}

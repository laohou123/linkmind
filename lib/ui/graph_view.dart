import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../app_state.dart';
import '../data/repository.dart';
import 'theme.dart';

/// 图谱画布。Cytoscape.js 打包在 assets 里，不依赖任何 CDN，断网也能看。
///
/// Dart 与页面之间只交换 JSON：
///   Dart → 页面：GraphAPI.setData / highlight / focus
///   页面 → Dart：ready / tapNode / tapEdge / positions
class GraphView extends StatefulWidget {
  final AppState state;
  const GraphView({super.key, required this.state});

  @override
  State<GraphView> createState() => _GraphViewState();
}

class _GraphViewState extends State<GraphView> {
  late final WebViewController _controller;
  bool _ready = false;

  int _lastGraphRevision = -1;
  int _lastHighlightRevision = -1;
  int _lastFocusRevision = -1;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColors.bg)
      ..addJavaScriptChannel('AndroidBridge', onMessageReceived: _onJsMessage)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          _ready = true;
          _pushGraph();
        },
      ))
      ..loadFlutterAsset('assets/graph/index.html');

    widget.state.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    widget.state.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    if (!_ready) return;
    final s = widget.state;
    if (s.graphRevision != _lastGraphRevision) {
      _pushGraph();
    } else if (s.highlightRevision != _lastHighlightRevision) {
      _applyHighlight();
    } else if (s.focusRevision != _lastFocusRevision) {
      _applyFocus();
    }
  }

  void _pushGraph() {
    final s = widget.state;
    _lastGraphRevision = s.graphRevision;
    _lastHighlightRevision = s.highlightRevision;
    _lastFocusRevision = s.focusRevision;
    final payload = jsonEncode({
      'nodes': s.graph['nodes'] ?? [],
      'edges': s.graph['edges'] ?? [],
    });
    _controller.runJavaScript('window.GraphAPI && window.GraphAPI.setData($payload);');
    if (s.highlightIds.isNotEmpty) {
      _applyHighlight();
    }
  }

  void _applyHighlight() {
    final s = widget.state;
    _lastHighlightRevision = s.highlightRevision;
    final ids = jsonEncode(s.highlightIds);
    _controller.runJavaScript('window.GraphAPI && window.GraphAPI.highlight($ids);');
  }

  void _applyFocus() {
    final s = widget.state;
    _lastFocusRevision = s.focusRevision;
    final id = s.focusNodeId;
    if (id == null) return;
    _controller.runJavaScript(
        'window.GraphAPI && window.GraphAPI.focus(${jsonEncode(id)});');
  }

  Future<void> _onJsMessage(JavaScriptMessage message) async {
    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(message.message);
      if (decoded is! Map<String, dynamic>) return;
      data = decoded;
    } catch (_) {
      return;
    }

    switch (data['type']) {
      case 'ready':
        _ready = true;
        _pushGraph();
        break;
      case 'tapNode':
        final id = data['id'] as String?;
        if (id != null) widget.state.openEntity(id);
        break;
      case 'tapEdge':
        final id = data['id'] as String?;
        if (id != null) widget.state.openFact(id);
        break;
      case 'tapBlank':
        widget.state.dismissTransientPanels();
        break;
      case 'positions':
        final list = data['positions'];
        if (list is List) {
          final mapped = list
              .whereType<Map>()
              .map((e) => <String, Object?>{
                    'id': e['id'],
                    'x': e['x'],
                    'y': e['y'],
                  })
              .toList();
          // 位置只是显示细节，写失败不影响主流程
          GraphRepository.instance.savePositions(mapped).catchError((_) {});
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}

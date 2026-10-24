// DshConnectionIndicator (packages/dsh_ui) against dsh's ConnectionIndicator.tsx. Props:
// {layout, labels: {disconnected, connecting, recovered, reconnectAction, restartAction}, items: [{id, state}]}.
import 'package:dsh_parity/dsh_parity.dart';
import 'package:dsh_ui/dsh_ui.dart';

DshConnectionIndicatorState _state(String name) =>
    DshConnectionIndicatorState.values.byName(name);

final Map<String, ParityCase> connectionCases = {
  'connection.indicator': ParityCase(
    widgets: const ['dsh_ui:DshConnectionIndicator'],
    build: (ctx) {
      final labels = (ctx.props['labels'] as Map).cast<String, String>();
      return ParityStack(
        layout: ctx.layout,
        children: [
          for (final item
              in (ctx.props['items'] as List).cast<Map<String, dynamic>>())
            parityItem(
              item['id'] as String,
              DshConnectionIndicator(
                state: _state(item['state'] as String),
                disconnectedLabel: labels['disconnected']!,
                connectingLabel: labels['connecting']!,
                recoveredLabel: labels['recovered']!,
                reconnectActionLabel: labels['reconnectAction']!,
                restartActionLabel: labels['restartAction']!,
                onReconnect: () {},
              ),
            ),
        ],
      );
    },
  ),
};

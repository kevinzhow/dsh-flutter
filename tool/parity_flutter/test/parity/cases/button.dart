// DshButton (packages/dsh_ui) against dsh's Button.tsx. Props: {layout, items:[{id,label,variant,size,disabled}]}.
import 'package:dsh_parity/dsh_parity.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

DshButtonVariant _variant(String? name) => switch (name) {
  'primary' => DshButtonVariant.primary,
  'outline' => DshButtonVariant.outline,
  'toolbar' => DshButtonVariant.toolbar,
  _ => DshButtonVariant.ghost,
};

final Map<String, ParityCase> buttonCases = {
  'button.items': ParityCase(
    widgets: const ['dsh_ui:DshButton'],
    build: (ctx) => ParityStack(
      layout: ctx.layout,
      children: [
        for (final item
            in (ctx.props['items'] as List).cast<Map<String, dynamic>>())
          parityItem(
            item['id'] as String,
            DshButton(
              variant: _variant(item['variant'] as String?),
              size: item['size'] == 'sm' ? DshButtonSize.sm : DshButtonSize.md,
              // Enabled buttons need a handler; a no-op keeps them interactive like the web ones.
              onPressed: item['disabled'] == true ? null : () {},
              child: Text(item['label'] as String),
            ),
          ),
      ],
    ),
  ),
};

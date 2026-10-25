import 'package:dsh_feature_sidebar_right/dsh_feature_sidebar_right.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('registered resource kinds remain independent and reopen with current memory parameters', () {
    final types = SidebarTabTypes();
    types.register(
      SidebarTabType(
        kind: 'plan',
        multiple: true,
        acceptsResource: (a) => a.startsWith('dsh-resource://plan/'),
        titleForResource: (_) => 'Plan',
      ),
    );
    final state = SidebarState('s', types: types);
    addTearDown(state.dispose);
    state.openResource(
      'dsh-resource://plan/s/a',
      params: const {
        'planReview': {'markdown': 'First'},
      },
    );
    state.openResource('dsh-resource://plan/s/b');
    final plans = state.tabs.where((t) => t.kind == 'plan').toList();
    expect(plans, hasLength(2));
    state.openResource(
      'dsh-resource://plan/s/a',
      params: const {
        'planReview': {'markdown': 'Revised'},
      },
    );
    expect(state.active.contentId, 'dsh-resource://plan/s/a');
    expect(state.active.params, {
      'planReview': {'markdown': 'Revised'},
    });
    expect(state.tabs.where((t) => t.kind == 'plan'), hasLength(2));
    state.close(state.active.id);
    state.openResource('dsh-resource://plan/s/a');
    expect(
      state.active.params,
      isEmpty,
    ); // no stale temporary document resurrection
  });
  test('unregistered resources cannot create a tab', () {
    final state = SidebarState('s');
    addTearDown(state.dispose);
    state.openResource('dsh-resource://unknown/s/a');
    expect(state.tabs, isEmpty);
  });
}

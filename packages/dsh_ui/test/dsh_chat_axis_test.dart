import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter_test/flutter_test.dart';

// The expected numbers were measured in dsh web (pinned checkout, Chromium
// 1280x720, 1920x1000 and 390x844 windows): the message column, the input card
// and the scroll body of the active conversation.
void main() {
  group('DshChatAxis against dsh web', () {
    test('1280 window: the conversation column is 1000px wide', () {
      const axis = DshChatAxis(1000, scrollbar: true);
      expect(axis.contentWidth, 680);
      // scroll body 998px with a 5px gutter: 993px to centre on.
      expect(axis.inner, 993);
      expect(axis.messageWidth, 680);
      expect(
        axis.leftOf(axis.messageWidth),
        156.5,
      ); // x 436.5 from the pane's 280
      expect(axis.cardWidth, 712);
      expect(axis.leftOf(axis.cardWidth), 140.5); // x 420.5
    });

    test('1920 window: the content width caps at 920', () {
      const axis = DshChatAxis(1640, scrollbar: true);
      expect(axis.contentWidth, 920);
      expect(axis.messageWidth, 920);
      expect(axis.leftOf(axis.messageWidth), 356.5); // x 636.5
      expect(axis.cardWidth, 952);
    });

    test(
      'a pane narrower than 680 + 64 shrinks the column, not the margins',
      () {
        const axis = DshChatAxis(334, scrollbar: true);
        expect(axis.contentWidth, 680);
        expect(axis.inner, 327);
        expect(
          axis.messageWidth,
          263,
        ); // x 88 from the pane's 56: 32px each side
        expect(axis.leftOf(axis.messageWidth), 32);
        expect(axis.cardWidth, 295); // x 72: 16px each side
        expect(axis.leftOf(axis.cardWidth), 16);
      },
    );

    test('a touch phone has no scrollbar gutter', () {
      const axis = DshChatAxis(390);
      expect(axis.inner, 388);
      expect(axis.trailing, 2);
      expect(axis.messageWidth, 324);
    });
  });
}

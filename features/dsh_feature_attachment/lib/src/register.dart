import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:flutter/widgets.dart';

import 'composer_attachments.dart';
import 'message_images.dart';

/// `conversation.input.attachments` as this feature uses it.
final Slot<SessionOwner, Widget> inputAttachmentsSlot = DshSlots
    .conversationInputAttachments
    .typed<SessionOwner, Widget>();

/// The image-group slots as this feature uses them.
final Slot<ImageGalleryOwner, Widget> userImagesSlot = DshSlots
    .conversationChatUserImages
    .typed<ImageGalleryOwner, Widget>();
final Slot<ImageGalleryOwner, Widget> messageImagesSlot = DshSlots
    .conversationChatMessageImages
    .typed<ImageGalleryOwner, Widget>();
final Slot<ImageGalleryOwner, Widget> toolImagesSlot = DshSlots.toolCallImages
    .typed<ImageGalleryOwner, Widget>();

/// Occupy the attachment slots (dsh registers its official `MessageImages` into
/// `conversation.chat.user.images`, `conversation.chat.message.images` and
/// `tool.call.images` at priority 100, and the rail into
/// `conversation.input.attachments`).
void registerAttachmentFeature(
  SlotRegistry slots, {
  required DshI18n Function() i18n,
}) {
  slots.register<SessionOwner, Widget>(
    inputAttachmentsSlot,
    (owner) => ComposerAttachmentsView(owner: owner, i18n: i18n()),
  );
  for (final slot in [userImagesSlot, messageImagesSlot, toolImagesSlot]) {
    slots.register<ImageGalleryOwner, Widget>(
      slot,
      (owner) => MessageImagesView(owner: owner, i18n: i18n()),
    );
  }
}

#!/usr/bin/env python3
"""Attachment surfaces: pending-file chips, the composer's draft rail, the sent-message file cards and the image gallery.

React host: host/attachment.tsx mounts dsh's real FileCard, ComposerAttachments (over AttachmentRail), UserContent and
ImageGallery. Flutter: features/dsh_feature_attachment/test/parity (chip, draft, gallery: DshFileCard, DshDraftImage,
DshImageFrame, DshImageGroup) and features/dsh_feature_chat/test/parity (sent: UserBubble over DshMessageFileCard).
Kinds and props (the same JSON reaches both providers; every image is a synthetic PNG shipped as base64):

  attachment.chip     {layout, items: [{id, name, bytes, state: ready|uploading|error, progress?}]}; parity id: the item id
  attachment.draft    {layout, images: {key: base64}, rails: [{items: [{id, kind: image|file, name, bytes, image?, state?,
                      progress?}]}]}; one composer rail per entry; parity id: the item id
  attachment.sent     {layout, files: [{name, bytes}]}: file attachments of a sent user message
  attachment.gallery  {layout, images: {key: {base64, width, height}}, galleries: [{id, align: start|end, thumbnail?,
                      compact?, items: [{id, image, state: loaded|loading|failed, name?}]}]}; parity id: <gallery>-<item>

Image sizes are chosen so the browser and Flutter map source pixels 1:1 at the case density (2): every frame has a
`0.5px` border, which Blink snaps to B device pixels (`border_device_px`: 1 in the native reference, 2 in the emulated one), so
a 64px tile shows a source cropped by `cover` into its (128 - 2B) device pixel content box (124 emulated, 126 native), a
240x160 single a (480 - 2B) x (320 - 2B) source, a 48px thumbnail (2px padding) an image of at most 96 - 2B - 8 device
pixels (84 emulated, 86 native). File names use glyph kinds the Flutter port draws like dsh
(other, pdf, md, docx, png, csv); the language-specific code artwork is not ported, so no code file names.

Ids: components.attachment.<surface>.<name>.<theme>. All content is invented. Chinese names avoid a hanzi next to a Latin
letter or digit: Chromium (text-autospace) adds an eighth-em gap there, which Flutter's text layout does not.
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from builders_api import base_case, border_device_px, replace_cases, themed  # noqa: E402
from parity_lib import fonts  # noqa: E402
import synthetic_images as img  # noqa: E402

ORDER = 400
PKG = 'packages/client/ui-attachment/src/'
COLUMN = {'direction': 'column', 'gap': 8, 'align': 'start'}
PHONE = 390

# ---- chip (FileCard) ---------------------------------------------------------------------------------------------


def chip(item_id, name, bytes_, state='ready', progress=None):
    item = {'id': item_id, 'name': name, 'bytes': bytes_, 'state': state}
    if progress is not None:
        item['progress'] = progress
    return item


ready_items = [
    chip('chip-txt', 'notes.txt', 2048), chip('chip-pdf', 'report.pdf', 482304), chip('chip-md', 'README.md', 5120),
    chip('chip-docx', 'proposal.docx', 73728), chip('chip-png', 'screenshot.png', 1258291), chip('chip-csv', 'table.csv', 18432),
]
state_items = [
    chip('chip-progress', 'archive.pdf', 9437184, 'uploading', 0.42),
    chip('chip-indeterminate', 'summary.docx', 52428, 'uploading'),
    chip('chip-failed', 'budget.csv', 1048576, 'error'),
]
long_items = [
    chip('chip-long-ready', 'quarterly-financial-review-final-version-2.pdf', 3355443),
    chip('chip-long-failed', 'quarterly-financial-review-final-version-3.docx', 3355443, 'error'),
]
zh_items = [
    chip('chip-zh-ready', '会议纪要.txt', 3072),
    chip('chip-zh-progress', '项目计划书.docx', 245760, 'uploading', 0.6),
    chip('chip-zh-failed', '销售数据汇总表第三季度.csv', 1048576, 'error'),
]


def card_height(count, gap=8):
    return 16 + count * 64 + (count - 1) * gap + 16


def chip_case(name, title, items, variants=None, locale='en'):
    props = {'layout': COLUMN, 'items': items}
    variants = variants or [('default', 'Default', props, None)]
    return themed(base_case('components.attachment.chip.' + name, title, 'attachment.chip',
                            {'width': 16 + 240 + 16, 'height': card_height(len(items)), 'density': 2}, variants, locale=locale,
                            category='extension/attachment', react_hint=PKG + 'FileCard.tsx'))


chip_cases = chip_case('ready-kinds', 'File cards, one per glyph kind', ready_items)
chip_cases += chip_case('upload-states-all', 'File cards: uploading with progress, indeterminate, failed', state_items)
long_props = {'layout': COLUMN, 'items': long_items}
chip_cases += chip_case('hover-long', 'Long names and the hover remove badge', long_items, [
    ('default', 'Default', long_props, None),
    ('hover', 'Hover on the first card', long_props, [{'type': 'hover', 'target': 'chip-long-ready'}]),
    ('hover-failed', 'Hover on the failed card', long_props, [{'type': 'hover', 'target': 'chip-long-failed'}])])
chip_cases += chip_case('zh-cn', 'File cards with Chinese names and labels', zh_items, locale='zh-CN')
replace_cases('components.attachment.chip.', chip_cases)

# ---- sent (UserContent file cards) -------------------------------------------------------------------------------
END_COLUMN = {'direction': 'column', 'gap': 8, 'align': 'end'}
sent_files = [{'name': 'notes.txt', 'bytes': 2048}, {'name': 'report.pdf', 'bytes': 482304}, {'name': 'README.md', 'bytes': 5120},
              {'name': 'proposal-for-the-next-quarter-with-a-long-title.docx', 'bytes': 73728}]
sent_zh = [{'name': '会议纪要.txt', 'bytes': 3072}, {'name': '销售数据汇总表第三季度.csv', 'bytes': 18432}]


def sent_case(name, title, files, locale='en'):
    height = 16 + len(files) * 64 + (len(files) - 1) * 8 + 16
    props = {'layout': END_COLUMN, 'files': files}
    return themed(base_case('components.attachment.sent.' + name, title, 'attachment.sent',
                            {'width': PHONE, 'height': height, 'density': 2}, [('default', 'Default', props, None)], locale=locale,
                            category='extension/attachment', react_hint='packages/client/ui-chat/src/client/chat/UserContent.tsx'))


sent_cases = sent_case('files-mixed', 'Sent message with file cards', sent_files)
sent_cases += sent_case('zh-cn', 'Sent message with Chinese file names', sent_zh, locale='zh-CN')
replace_cases('components.attachment.sent.', sent_cases)

# ---- draft rail (ComposerAttachments) ----------------------------------------------------------------------------
DENSITY = 2
B = border_device_px(0.5, DENSITY)   # device pixels of a 0.5px border in the reference
TILE = 64 * DENSITY - 2 * B          # content box of a 64px tile in device pixels (124 emulated, 126 native)
SINGLE_W, SINGLE_H = 240 * DENSITY - 2 * B, 160 * DENSITY - 2 * B
THUMB = 48 * DENSITY - 2 * B - 8     # 48px thumbnail minus the border and its 2px padding (84 emulated, 86 native)
DRAFT_IMAGES = {
    # The 64px box has a 0.5px border, so its content is TILE device px at density 2: a square source is shown 1:1,
    # a 1.5 TILE x TILE (or TILE x 1.5 TILE) one is cropped by `cover` without scaling.
    'draft-square': img.scene(TILE, TILE),
    'draft-landscape': img.scene(TILE * 3 // 2, TILE, (70, 120, 90), (230, 220, 150)),
    'draft-portrait': img.scene(TILE, TILE * 3 // 2, (150, 90, 170), (250, 200, 210)),
}
DRAFT_B64 = {k: img.png_base64(v) for k, v in DRAFT_IMAGES.items()}


def draft_image(item_id, name, key, bytes_=204800):
    return {'id': item_id, 'kind': 'image', 'name': name, 'bytes': bytes_, 'image': key}


def draft_file(item_id, name, bytes_, state='ready', progress=None):
    item = {'id': item_id, 'kind': 'file', 'name': name, 'bytes': bytes_, 'state': state}
    if progress is not None:
        item['progress'] = progress
    return item


# The rails are the real ComposerAttachments: padding 2px 10px 0 and a -6px bottom margin that the composer card's 12px
# flex gap absorbs, so two stacked rails sit 12 - 6 = 6px apart.
RAIL_GAP = 12
DRAFT_LAYOUT = {'direction': 'column', 'gap': RAIL_GAP, 'align': 'stretch'}


def rail_height(count):
    return count * 66 + (count - 1) * RAIL_GAP - count * 6 + 6


def draft_case(name, title, rails, variants=None, locale='en'):
    props = {'layout': DRAFT_LAYOUT, 'images': DRAFT_B64, 'rails': [{'items': r} for r in rails]}
    variants = [(v, n, props, i) for v, n, i in (variants or [('default', 'Default', None)])]
    return themed(base_case('components.attachment.draft.' + name, title, 'attachment.draft',
                            {'width': 480, 'height': 16 + rail_height(len(rails)) + 16, 'density': 2}, variants, locale=locale,
                            category='extension/attachment', react_hint='packages/client/ui-attachment/src/client/ComposerAttachments.tsx'))


mixed_rails = [
    [draft_image('d-img-1', 'sunrise.png', 'draft-square'), draft_image('d-img-2', 'harbor.png', 'draft-landscape'),
     draft_file('d-file-1', 'proposal.docx', 73728)],
    [draft_file('d-file-2', 'archive.pdf', 9437184, 'uploading', 0.6), draft_image('d-img-3', 'portrait.png', 'draft-portrait')],
    [draft_file('d-file-3', 'budget.csv', 1048576, 'error'), draft_image('d-img-4', 'sunrise.png', 'draft-square')],
]
draft_cases = draft_case('rail-mixed', 'Draft rail: image thumbnails and file cards', mixed_rails, [
    ('default', 'Default', None),
    ('hover-image', 'Hover on a thumbnail (remove badge)', [{'type': 'hover', 'target': 'd-img-1'}]),
    ('hover-file', 'Hover on a file card', [{'type': 'hover', 'target': 'd-file-1'}])])
draft_cases += draft_case('rail-indeterminate-all', 'Draft rail: indeterminate upload next to images', [
    [draft_file('d-file-4', 'summary.docx', 52428, 'uploading'), draft_image('d-img-5', 'harbor.png', 'draft-landscape'),
     draft_image('d-img-6', 'portrait.png', 'draft-portrait')]])
draft_cases += draft_case('rail-zh-cn', 'Draft rail with Chinese names', [
    [draft_image('d-img-7', '日落.png', 'draft-square'), draft_file('d-file-5', '会议纪要.txt', 3072),
     draft_image('d-img-8', '港口.png', 'draft-landscape')],
    [draft_file('d-file-6', '项目计划书.docx', 245760, 'uploading', 0.35), draft_image('d-img-9', '截图.png', 'draft-portrait')],
    [draft_file('d-file-7', '销售数据汇总表第三季度.csv', 1048576, 'error')],
], locale='zh-CN')
replace_cases('components.attachment.draft.', draft_cases)

# ---- gallery (ImageGallery) --------------------------------------------------------------------------------------
GALLERY_IMAGES = {
    # key: (declared width, declared height, PNG). The declared size is the attachment's natural size (it only sizes a
    # lone image: long edge 240px); the pixels are the content box of the frame in device pixels, so nothing is scaled:
    # a 240x160 single is (480 - 2B) x (320 - 2B) px; a tile TILE px; a thumbnail THUMB px (`contain`; a portrait one is
    # cut off instead, see thumb-portrait). B = device pixels of the frame's border (see the module docstring).
    'single-landscape': (480, 320, img.scene(SINGLE_W, SINGLE_H)),
    'single-portrait': (320, 480, img.scene(SINGLE_H, SINGLE_W, (150, 90, 170), (250, 200, 210))),
    'tile-landscape': (TILE * 3 // 2, TILE, img.scene(TILE * 3 // 2, TILE, (70, 120, 90), (230, 220, 150))),
    'tile-portrait': (TILE, TILE * 3 // 2, img.scene(TILE, TILE * 3 // 2, (200, 120, 70), (120, 190, 220))),
    'tile-square': (TILE, TILE, img.scene(TILE, TILE)),
    'thumb-landscape': (THUMB, THUMB * 2 // 3, img.scene(THUMB, THUMB * 2 // 3, (70, 120, 90), (230, 220, 150))),
    'thumb-square': (THUMB, THUMB, img.scene(THUMB, THUMB)),
    # A portrait picture in a thumbnail is laid out at the frame's width and cut off at the bottom (dsh grid quirk), so
    # its width is the THUMB content width.
    'thumb-portrait': (THUMB, THUMB * 3 // 2, img.scene(THUMB, THUMB * 3 // 2, (150, 90, 170), (250, 200, 210))),
}
GALLERY_PROPS_IMAGES = {k: {'base64': img.png_base64(d), 'width': w, 'height': h} for k, (w, h, d) in GALLERY_IMAGES.items()}
G_COLUMN = {'direction': 'column', 'gap': 12, 'align': 'stretch'}


def gal(gallery_id, align, items, **flags):
    return dict({'id': gallery_id, 'align': align, 'items': [dict(i) for i in items]}, **flags)


def gi(item_id, image, state='loaded', name=None):
    item = {'id': item_id, 'image': image, 'state': state}
    if name:
        item['name'] = name
    return item


def gallery_case(name, title, galleries, height, locale='en'):
    props = {'layout': G_COLUMN, 'images': GALLERY_PROPS_IMAGES, 'galleries': galleries}
    return themed(base_case('components.attachment.gallery.' + name, title, 'attachment.gallery',
                            {'width': PHONE, 'height': height, 'density': 2}, [('default', 'Default', props, None)], locale=locale,
                            category='extension/attachment', react_hint=PKG + 'MessageImage.tsx'))


gallery_cases = gallery_case('single-landscape-portrait', 'A lone landscape image (right) and a lone portrait image (left)', [
    gal('g-land', 'end', [gi('a', 'single-landscape')]), gal('g-port', 'start', [gi('a', 'single-portrait')])],
    16 + 160 + 12 + 240 + 16)
gallery_cases += gallery_case('tiles-many', 'Tiles of several images wrapping, and one compact image', [
    gal('g-tiles', 'end', [gi('t%d' % i, k) for i, k in enumerate(
        ['tile-landscape', 'tile-portrait', 'tile-square', 'tile-landscape', 'tile-square', 'tile-portrait', 'tile-landscape'])]),
    gal('g-compact', 'start', [gi('a', 'tile-portrait')], compact=True)],
    16 + 64 + 10 + 64 + 12 + 64 + 16)
gallery_cases += gallery_case('thumbnails-row', 'List thumbnails: landscape, square and portrait contained', [
    gal('g-thumbs', 'start', [gi('a', 'thumb-landscape'), gi('b', 'thumb-square'), gi('c', 'thumb-portrait')], thumbnail=True)],
    16 + 48 + 16)
state_galleries = [
    gal('g-tile-states', 'start', [gi('loaded', 'tile-square'), gi('loading', 'tile-square', 'loading'), gi('failed', 'tile-square', 'failed')],
        compact=True),
    gal('g-thumb-states', 'start', [gi('loaded', 'thumb-square'), gi('loading', 'thumb-square', 'loading'),
                                    gi('failed', 'thumb-square', 'failed')], thumbnail=True),
    gal('g-single-failed', 'start', [gi('failed', 'single-landscape', 'failed')]),
    gal('g-single-loading', 'start', [gi('loading', 'single-landscape', 'loading')]),
]
gallery_cases += gallery_case('loading-failed-states', 'Loaded, loading and failed images in every variant', state_galleries,
                              16 + 64 + 12 + 48 + 12 + 60 + 12 + 160 + 16)
gallery_cases += gallery_case('zh-cn', 'Loading and failed images with Chinese copy', state_galleries, 16 + 64 + 12 + 48 + 12 + 60 + 12 + 160 + 16,
                              locale='zh-CN')
replace_cases('components.attachment.gallery.', gallery_cases)

# Every character the Chinese cases draw must have a glyph in the pinned CJK subset (tool/parity-fonts).
zh_text = ''
for case in draft_cases + chip_cases + sent_cases + gallery_cases:
    if case['locale'] == 'zh-CN':
        zh_text += repr(case['variants'])
missing = fonts.uncovered_cjk(zh_text)
if missing:
    sys.exit('Chinese cases use characters outside the pinned CJK subset: %s' % ''.join(missing))

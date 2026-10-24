// Stand-in for dsh's `@deepseek-ai/dsh-client-ui-primitives` barrel (build-host.mjs aliases the package name here).
//
// dsh's ui-tool / ui-conversation / ui-plan sources import the whole barrel (ui-primitives/src/index.ts). That barrel
// re-exports every primitive, including the markdown renderer (katex, micromark, mdast), simple-icons and the settings
// form, which none of the parity surfaces draw. This file re-exports the SAME real modules for just the names the
// mounted surfaces import, so no primitive is replaced or edited: only the unused part of the graph (and its npm
// dependencies) stays out of the bundle. Add a line here when a new surface imports another primitive.
export { Button } from '@dsh/ui-primitives/src/Button.tsx'
export { StateDot } from '@dsh/ui-primitives/src/StateDot.tsx'
export { DisclosureRow } from '@dsh/ui-primitives/src/DisclosureRow.tsx'
export { TextShimmer } from '@dsh/ui-primitives/src/TextShimmer.tsx'
export { Tag } from '@dsh/ui-primitives/src/Tag.tsx'
export { FileTypeIcon, classifyFileType, fileExtension } from '@dsh/ui-primitives/src/FileTypeIcon.tsx'
export { fileSizeText } from '@dsh/ui-primitives/src/file-size.ts'
export { ImageLightbox } from '@dsh/ui-primitives/src/ImageLightbox.tsx'
export { JsonBlock } from '@dsh/ui-primitives/src/markdown/JsonBlock.tsx'
export { TerminalBlock } from '@dsh/ui-primitives/src/TerminalBlock.tsx'
export { CommandText } from '@dsh/ui-primitives/src/CommandText.tsx'
export { ReadBlock } from '@dsh/ui-primitives/src/ReadBlock.tsx'
export { DiffBlock, diffTotals } from '@dsh/ui-primitives/src/DiffBlock.tsx'
export { SearchBlock } from '@dsh/ui-primitives/src/SearchBlock.tsx'
export { WebBlock } from '@dsh/ui-primitives/src/WebBlock.tsx'
export { CodeBlock } from '@dsh/ui-primitives/src/markdown/CodeBlock.tsx'
export * from '@dsh/ui-primitives/src/icons/index.tsx'
export { MarkdownText } from '@dsh/ui-primitives/src/markdown/MarkdownText.tsx'
export { extractMarkdownPlainText } from '@dsh/ui-primitives/src/markdown/plain-text.ts'
// Settings rows (ui-theme, ui-permission-presets): the font-family text field, the permission selector's menu and its
// full-access risk confirmation dialog (both closed in every case).
export { Input } from '@dsh/ui-primitives/src/Input.tsx'
export { Menu } from '@dsh/ui-primitives/src/Menu.tsx'
export { RiskConfirmation } from '@dsh/ui-primitives/src/RiskConfirmation.tsx'

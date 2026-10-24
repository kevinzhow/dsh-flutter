// dsh's real workspace surfaces, mounted over fixture data (no host):
//
//   workspace.picker     ui-workspace WorkspacePickFlow with its menu open (the empty-state workspace chip's popover)
//                          props {workspaces: [{id, title}], phase?, selectedId?, anchorWidth?}
//   workspace.error      the same flow's adoption error dialog (a directory-flow occupant reports a failure on mount)
//                          props {message}
//   workspace.directory  ui-directory-picker-browse DirectoryBrowser, the in-app Select Workspace Directory dialog
//                          props {variant: home | two-pane | empty | truncated | error, hidden?}
//
// The picker menu portals into <body> at the anchor chip's rect (position: fixed), so the capture crops to `[role="menu"]`;
// the dialogs portal their own Modal, captured as `[role="dialog"]`. Directory listings come from a small fake tree.
import { useEffect, useMemo, useRef, useState } from 'react'
import { WorkspacePickFlow } from '@dsh/ui-workspace/src/client/WorkspacePicker.tsx'
import { en as workspaceEn, zh as workspaceZh } from '@dsh/ui-workspace/src/client/locales.ts'
import { DirectoryBrowser } from '@dsh/ui-directory-picker-browse/src/client/DirectoryBrowser.tsx'
import { createTranslator } from '../../parity-web/host/mocks/locale.ts'
import type { KindRenderer } from '../../parity-web/host/types.ts'
import { publishSettle } from './settle.ts'

// The dialog's copy: dsh registers it inline in ui-directory-picker-browse/src/client/index.ts (`apply`), where it is not
// importable; these are the same strings, the Flutter catalog extracts them from that file.
const browserEn = {
  'browser.title': 'Select Workspace Directory', 'browser.home': 'Home', 'browser.newFolder': 'New folder',
  'browser.folderName': 'Folder name', 'browser.createIn': 'New folder in "{name}"', 'browser.untitledFolder': 'Untitled folder',
  'browser.create': 'Create', 'browser.cancel': 'Cancel', 'browser.open': 'Open', 'browser.editPath': 'Edit path',
  'browser.loading': 'Loading…', 'browser.truncated': 'Too many folders to list; only the beginning is shown.',
  'browser.showHidden': 'Show hidden files',
}
const browserZh = {
  'browser.title': '选择工作区目录', 'browser.home': '主目录', 'browser.newFolder': '新建文件夹', 'browser.folderName': '文件夹名称',
  'browser.createIn': '在"{name}"中新建文件夹', 'browser.untitledFolder': '未命名文件夹', 'browser.create': '创建',
  'browser.cancel': '取消', 'browser.open': '打开', 'browser.editPath': '编辑路径', 'browser.loading': '加载中…',
  'browser.truncated': '文件夹过多，仅显示开头部分。', 'browser.showHidden': '显示隐藏文件',
}

const entry = (path: string, hidden = false) => ({ name: path.split('/').pop() ?? '/', path, hidden })
const HOME = '/home/u'
const crumbsOf = (path: string) => {
  const parts = path.split('/').filter(Boolean)
  return [{ name: '/', path: '/', hidden: false }, ...parts.map((_, i) => entry('/' + parts.slice(0, i + 1).join('/')))]
}
const TREE: Record<string, string[]> = {
  [HOME]: ['Desktop', 'Documents', 'Downloads', 'notes', 'projects', '.config'],
  [`${HOME}/projects`]: ['atlas', 'harbor', 'meadow', 'orchard'],
  [`${HOME}/projects/atlas`]: ['docs', 'src'],
  [`${HOME}/projects/empty`]: [],
}
function listing(path: string, extra: Record<string, unknown> = {}) {
  const names = TREE[path] ?? []
  return {
    path, home: HOME, crumbs: crumbsOf(path),
    entries: names.map(n => entry(`${path}/${n}`, n.startsWith('.'))), truncated: false, ...extra,
  }
}

function Directory({ props, locale }: { props: any; locale: string }) {
  const t = useMemo(() => createTranslator(locale, { en: browserEn, zh: browserZh }), [locale])
  const variant: string = props.variant ?? 'home'
  const listDirectory = useMemo(() => async (path?: string) => {
    if (path === undefined) {
      if (variant === 'error') throw Object.assign(new Error('Permission denied'), { rpcError: { message: 'Permission denied' } })
      if (variant === 'two-pane') return listing(`${HOME}/projects`)
      if (variant === 'empty') return listing(`${HOME}/projects/empty`)
      return listing(HOME, variant === 'truncated' ? { truncated: true } : {})
    }
    return listing(path, variant === 'truncated' && path === HOME ? { truncated: true } : {})
  }, [variant])
  useEffect(() => {
    publishSettle(() => document.querySelector('[role="dialog"] button[class*="row"], [role="dialog"] [role="alert"]') !== null
      || variant === 'empty', 'directory browser listing')
  }, [variant])
  return (
    <div style={{ width: 1, height: 1 }}>
      <DirectoryBrowser
        open
        busy={false}
        listDirectory={listDirectory as any}
        createDirectory={async (_p: string, name: string) => name}
        onOpen={() => {}}
        onClose={() => {}}
        t={t as any}
      />
    </div>
  )
}

function Picker({ props, locale }: { props: any; locale: string }) {
  const t = useMemo(() => createTranslator(locale, { en: workspaceEn, zh: workspaceZh }), [locale])
  const anchor = useRef<HTMLButtonElement>(null)
  const [ready, setReady] = useState(false)
  useEffect(() => { setReady(true) }, [])
  const snapshot = useMemo(() => ({
    phase: props.phase ?? 'ready', archivedSessionIds: [], pinnedSessionIds: [],
    items: props.workspaces.map((w: any) => ({
      workspaceId: w.id, path: `/work/${w.id}`, title: w.title, sessionIds: [], createdAt: '2026-10-01T00:00:00.000Z',
      updatedAt: '2026-10-01T00:00:00.000Z',
    })),
  }), [props])
  useEffect(() => {
    publishSettle(() => document.querySelector('[role="menu"]') !== null, 'workspace menu')
  }, [])
  return (
    <div style={{ width: 1, height: 1 }}>
      <button ref={anchor} type="button" style={{ position: 'absolute', left: 16, top: 16, width: props.anchorWidth ?? 160, height: 28, opacity: 0 }} />
      {ready && (
        <WorkspacePickFlow
          t={t as any}
          open
          anchorRef={anchor}
          useWorkspaces={((sel: (s: any) => any) => sel(snapshot)) as any}
          createWorkspace={async () => { throw new Error('not used') }}
          useDirectoryFlow={((sel: (s: boolean) => any) => sel(props.flow !== false)) as any}
          renderDirectoryFlow={() => null}
          onPick={() => {}}
          onClose={() => {}}
          selectedId={props.selectedId}
        />
      )}
    </div>
  )
}

/** A directory-flow occupant that reports a failure as soon as the flow asks for it: opens the adoption error dialog. */
function ErrorPicker({ props, locale }: { props: any; locale: string }) {
  const t = useMemo(() => createTranslator(locale, { en: workspaceEn, zh: workspaceZh }), [locale])
  const snapshot = useMemo(() => ({ phase: 'ready', archivedSessionIds: [], pinnedSessionIds: [], items: [] }), [])
  const owner = useRef<any>(null)
  const [fired, setFired] = useState(false)
  useEffect(() => {
    if (fired || owner.current === null) return
    setFired(true)
    owner.current.onError(props.message)
  })
  useEffect(() => {
    publishSettle(() => document.querySelector('[role="dialog"] [role="alert"]') !== null, 'folder error dialog')
  }, [])
  return (
    <div style={{ width: 1, height: 1 }}>
      <WorkspacePickFlow
        t={t as any}
        open={false}
        useWorkspaces={((sel: (s: any) => any) => sel(snapshot)) as any}
        createWorkspace={async () => { throw new Error('not used') }}
        useDirectoryFlow={((sel: (s: boolean) => any) => sel(true)) as any}
        renderDirectoryFlow={(o: any) => { owner.current = o; return null }}
        onPick={() => {}}
        onClose={() => {}}
        addOnly
      />
    </div>
  )
}

export const kinds: Record<string, KindRenderer> = {
  'workspace.picker': (props, ctx) => <Picker props={props} locale={ctx.case.locale} />,
  'workspace.error': (props, ctx) => <ErrorPicker props={props} locale={ctx.case.locale} />,
  'workspace.directory': (props, ctx) => <Directory props={props} locale={ctx.case.locale} />,
}

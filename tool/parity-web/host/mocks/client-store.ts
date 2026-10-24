// Stand-in for dsh's `@deepseek-ai/dsh-client-store` (zustand-backed snapshot stores). ui-commands' popup.ts imports it for the
// headless PopupSelectController, which the parity host never constructs: the mounted view only reads `filterOptions` and
// `groupOptions` from the same module. The stub keeps the module graph free of zustand, which the harness does not install.
export interface SnapshotStore<T> {
  getSnapshot(): T
  subscribe(listener: () => void): () => void
  set(next: T): void
}

export function createSnapshotStore<T>(initial: T): SnapshotStore<T> {
  let value = initial
  const listeners = new Set<() => void>()
  return {
    getSnapshot: () => value,
    subscribe: (listener) => { listeners.add(listener); return () => { listeners.delete(listener) } },
    set: (next) => { value = next; for (const l of listeners) l() },
  }
}

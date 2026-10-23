// Settling for kinds whose content arrives asynchronously (images decoding, a lazy highlight grammar, a rejected
// loader). The capture script awaits `window.__parityReady` (tool/parity-web/capture.mjs) before it screenshots.
//
// Not a kind module: the registry only globs *.tsx.

/**
 * Publish a promise that resolves once `ready()` held for two consecutive animation frames and an extra 60 ms of
 * quiet, and rejects after `timeoutMs` (the capture then fails loudly instead of recording a half-rendered page).
 */
export function publishSettle(ready: () => boolean, what: string, timeoutMs = 8000): void {
  const started = performance.now()
  ;(window as unknown as { __parityReady: Promise<void> }).__parityReady = new Promise<void>((resolve, reject) => {
    let stable = 0
    const tick = () => {
      if (ready()) stable += 1
      else stable = 0
      if (stable >= 2) return void setTimeout(resolve, 60)
      if (performance.now() - started > timeoutMs) return reject(new Error(`parity settle timed out: ${what}`))
      requestAnimationFrame(tick)
    }
    requestAnimationFrame(tick)
  })
}

/** Every <img> under the document has decoded (loaded and non-empty). */
export function imagesDecoded(): boolean {
  return [...document.images].every((img) => img.complete && img.naturalWidth > 0)
}

/** Tag the first element child of `host`'s wrapper(s) with a parity id: used where the real component renders its own root. */
export function tagChild(el: Element | null, id: string): void {
  el?.setAttribute('data-parity-id', id)
}

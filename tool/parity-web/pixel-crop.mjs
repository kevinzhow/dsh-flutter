// Match Flutter's native element capture: intersect the logical viewport, then
// enclose both edges in device pixels. Never resample or paint missing pixels.
export function enclosingDeviceRect(box, viewport, density) {
  const values = [box?.x, box?.y, box?.width, box?.height, viewport?.width, viewport?.height, density]
  if (!values.every(Number.isFinite) || density <= 0 || box.width <= 0 || box.height <= 0 ||
      viewport.width <= 0 || viewport.height <= 0) throw new Error('Invalid capture geometry')
  const left = Math.max(0, box.x)
  const top = Math.max(0, box.y)
  const right = Math.min(viewport.width, box.x + box.width)
  const bottom = Math.min(viewport.height, box.y + box.height)
  if (right <= left || bottom <= top) throw new Error('Capture target is outside the viewport')
  // DOMRect's float32 conversion can leave ~1e-5 device-pixel noise at an
  // integral edge. This epsilon is still far below one Blink layout unit
  // (1/64 device px), so genuine fractional edges remain enclosed.
  const lo = (v) => Math.floor(v * density + 1e-4)
  const hi = (v) => Math.ceil(v * density - 1e-4)
  const x = lo(left), y = lo(top)
  return { x, y, width: hi(right) - x, height: hi(bottom) - y }
}

export function cropRgba(image, rect) {
  const { x, y, width, height } = rect
  if (![x, y, width, height].every(Number.isInteger) || x < 0 || y < 0 || width <= 0 || height <= 0 ||
      x + width > image.width || y + height > image.height || image.data.length !== image.width * image.height * 4) {
    throw new Error('Device crop is outside the captured raster')
  }
  const data = Buffer.alloc(width * height * 4)
  for (let row = 0; row < height; row++) {
    const start = ((y + row) * image.width + x) * 4
    image.data.copy(data, row * width * 4, start, start + width * 4)
  }
  return { width, height, data }
}

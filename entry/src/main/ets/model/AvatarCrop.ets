// 头像裁剪的纯几何计算：视口为正方形，源图按 cover 铺满后叠加缩放与拖动。
export interface AvatarCropRegion {
  x: number;
  y: number;
  size: number;
}

export function clampAvatarScale(scale: number): number {
  if (!isFinite(scale) || scale < 1) return 1;
  if (scale > 3) return 3;
  return scale;
}

export function avatarCropRegion(width: number, height: number, viewport: number,
  scale: number, dx: number, dy: number): AvatarCropRegion {
  const w = width > 0 ? width : 1;
  const h = height > 0 ? height : 1;
  const view = viewport > 0 ? viewport : 1;
  const s = clampAvatarScale(scale);
  const cover = Math.max(view / w, view / h);
  const k = cover * s;
  let size = view / k;
  const maxSize = Math.min(w, h);
  if (size > maxSize) size = maxSize;
  if (size < 1) size = 1;
  const half = size / 2;
  let cx = w / 2 - dx / k;
  let cy = h / 2 - dy / k;
  const minX = half;
  const maxX = w - half;
  const minY = half;
  const maxY = h - half;
  cx = cx < minX ? minX : (cx > maxX ? maxX : cx);
  cy = cy < minY ? minY : (cy > maxY ? maxY : cy);
  let x = Math.round(cx - half);
  let y = Math.round(cy - half);
  const side = Math.round(size);
  if (x < 0) x = 0;
  if (y < 0) y = 0;
  if (x + side > w) x = Math.max(0, w - side);
  if (y + side > h) y = Math.max(0, h - side);
  return { x: x, y: y, size: side };
}

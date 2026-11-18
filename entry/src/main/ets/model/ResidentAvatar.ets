export function residentAvatar(gender: string, id: string = ''): Resource {
  const alternate = id.length > 0 && id.charCodeAt(id.length - 1) % 2 !== 0;
  if (gender === '男') return alternate ? $r('app.media.avatar_m3') : $r('app.media.avatar_m1');
  if (gender === '女') return alternate ? $r('app.media.avatar_f3') : $r('app.media.avatar_f1');
  return $r('app.media.avatar_f2');
}

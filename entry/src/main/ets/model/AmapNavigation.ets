import { common, Want } from '@kit.AbilityKit';
import { LocationContext, navigableLocation, validCoordinate } from './MapLocationState';

export function amapRouteUrl(latitude: number, longitude: number, walking: boolean): string {
  if (!validCoordinate(latitude, longitude)) throw new Error('目的地坐标无效。');
  return 'https://uri.amap.com/navigation?to=' + longitude.toString() + ',' + latitude.toString() + ',' +
    encodeURIComponent('回访目的地') + '&mode=' + (walking ? 'walk' : 'car') + '&coordinate=gaode&callnative=1&src=nuanlin';
}

export function amapResidenceUrl(record: LocationContext, personId: string, walking: boolean): string {
  if (record.personId !== personId || !record.address.trim() || record.address.includes('*')) throw new Error('请先补充并保存当前住所。');
  try {
    const location = navigableLocation(record, personId);
    if (location.coordinateSystem === 'GCJ02') return amapRouteUrl(location.latitude, location.longitude, walking);
  } catch (e) {}
  return 'https://uri.amap.com/search?keyword=' + encodeURIComponent(record.address.trim()) +
    '&city=' + encodeURIComponent('武汉') + '&callnative=1&src=nuanlin';
}

export async function openAmapUrl(context: common.UIAbilityContext, url: string): Promise<void> {
  const want: Want = { action: 'ohos.want.action.viewData', uri: url };
  await context.startAbility(want);
}

import { amapRouteUrl, openAmapUrl } from './AmapNavigation';
import { common, Want, bundleManager } from '@kit.AbilityKit';
import { navi, site, petalMaps, mapCommon } from '@kit.MapKit';
import { mapRequest, isWuhanCity } from './MapLocationState';
import { VisitPlanPrepared, VisitPlanPayload, VisitRoadMatrix, VisitOrigin, VisitPlanNavigation, VisitCoordinate, visitPointValid } from './VisitPlanState';

export function visitMatrix(result: navi.MatrixResult, size: number): VisitRoadMatrix {
  if (size < 2 || size > 9 || !result || !Array.isArray(result.rows) || result.rows.length !== size) throw new Error('地图返回的路网矩阵不完整，请重试。');
  const durations: (number | null)[][] = [];
  const distances: (number | null)[][] = [];
  for (let row = 0; row < size; row++) {
    if (!Array.isArray(result.rows[row].cells) || result.rows[row].cells.length !== size) throw new Error('地图矩阵列数不一致，请重试。');
    const times: (number | null)[] = [];
    const meters: (number | null)[] = [];
    for (let col = 0; col < size; col++) {
      const cell = result.rows[row].cells[col];
      const valid = !!cell && typeof cell.duration === 'number' && Number.isFinite(cell.duration) && cell.duration >= 0 &&
        typeof cell.distance === 'number' && Number.isFinite(cell.distance) && cell.distance >= 0;
      if (row === col && (!valid || cell.duration !== 0 || cell.distance !== 0)) throw new Error('地图矩阵起终点校验失败，请重试。');
      times.push(valid ? cell.duration! : null); meters.push(valid ? cell.distance! : null);
    }
    durations.push(times); distances.push(meters);
  }
  return { durations: durations, distances: distances };
}

async function petalMapsInstalled(): Promise<boolean> {
  try {
    await bundleManager.getBundleInfo('com.huawei.hmos.petalmaps', bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
    return true;
  } catch (e) {
    return false;
  }
}

export async function openWebMap(context: common.UIAbilityContext, latitude: number, longitude: number): Promise<void> {
  const url = 'https://uri.amap.com/marker?position=' + longitude.toString() + ',' + latitude.toString() +
    '&name=' + encodeURIComponent('回访目的地') + '&coordinate=gaode&callnative=0';
  const want: Want = { action: 'ohos.want.action.viewData', uri: url };
  await context.startAbility(want);
}

export class VisitPlanMap {
  static async search(context: common.UIAbilityContext, query: string): Promise<site.Site[]> {
    if (!query.trim()) throw new Error('请输入武汉出发地点。');
    const result = await mapRequest(site.searchByText(context, { query: query.trim(), cityId: '420100', isCityLimit: true,
      countryCodes: ['CN'], language: 'zh', pageIndex: 1, pageSize: 20 }));
    return (result.sites ?? []).filter((item: site.Site) => !!item.location && isWuhanCity(item.addressComponent.adminLevel2));
  }
  static async origin(context: common.UIAbilityContext, item: site.Site): Promise<VisitOrigin> {
    if (!item.location) throw new Error('地点坐标无效，请重新选择。');
    const point: VisitCoordinate = { latitude: item.location.latitude, longitude: item.location.longitude };
    if (!visitPointValid(point)) throw new Error('地点坐标无效，请重新选择。');
    const result = await mapRequest(site.reverseGeocode(context, { location: point, language: 'zh' }));
    if (!isWuhanCity(result.addressComponent.adminLevel2)) throw new Error('请选择已核验的武汉市出发地点。');
    return { latitude: point.latitude, longitude: point.longitude, label: (result.addressDescription || item.name || '已核验武汉出发点').slice(0, 200) };
  }
  static async matrix(context: common.UIAbilityContext, prepared: VisitPlanPrepared, payload: VisitPlanPayload): Promise<VisitRoadMatrix> {
    if (prepared.points.length < 2 || prepared.points.length > 9 || prepared.points.some((point: VisitCoordinate) => !visitPointValid(point))) throw new Error('算路节点无效。');
    // Only coordinates go to the map provider; resident names, records and appointments stay in the app.
    const points: navi.RouteCoordinate[] = prepared.points.map((point: VisitCoordinate): navi.RouteCoordinate => ({ latitude: point.latitude, longitude: point.longitude }));
    let result: navi.MatrixResult;
    if (prepared.transport === 'driving') {
      const departure = Date.parse(payload.date + 'T' + payload.startTime + ':00+08:00');
      if (!Number.isFinite(departure) || departure < Date.now()) throw new Error('驾车出发时间已过，请修改计划时间。');
      result = await mapRequest(navi.getDrivingMatrix(context, { origins: points, destinations: points, language: 'zh_CN', departAt: Math.floor(departure / 1000) }));
    } else if (prepared.transport === 'walking') {
      result = await mapRequest(navi.getWalkingMatrix(context, { origins: points, destinations: points, language: 'zh_CN' }));
    } else throw new Error('不支持的出行方式。');
    return visitMatrix(result, points.length);
  }
  static async navigate(context: common.UIAbilityContext, target: VisitPlanNavigation): Promise<void> {
    if (!visitPointValid(target) || !['walking', 'driving'].includes(target.transport)) throw new Error('导航目的地无效，请重新读取计划。');
    await openAmapUrl(context, amapRouteUrl(target.latitude, target.longitude, target.transport === 'walking'));
  }
}

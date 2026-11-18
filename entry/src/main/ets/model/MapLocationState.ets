export interface ResidenceLocation {
  latitude: number;
  longitude: number;
  coordinateSystem: string;
  provider: string;
  cityCode: string;
  addressSnapshot: string;
  poiId?: string | null;
  entranceLabel: string;
  status: string;
  verifiedAt: string;
  verifiedBy: string;
}
export interface LocationContext {
  personId: string;
  revision: number;
  address: string;
  location: ResidenceLocation | null;
}
export interface LocationInput {
  latitude: number;
  longitude: number;
  coordinateSystem: string;
  provider: string;
  cityCode: string;
  addressSnapshot: string;
  poiId?: string | null;
  entranceLabel: string;
  confirmed: boolean;
}
export function validCoordinate(latitude: number, longitude: number): boolean {
  return Number.isFinite(latitude) && Number.isFinite(longitude) &&
    latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180;
}
export function requireLocationContext(context: LocationContext, personId: string): LocationContext {
  if (!context || context.personId !== personId || !Number.isInteger(context.revision) || context.revision < 1 ||
    typeof context.address !== 'string') throw new Error('位置档案与当前居民不一致，请重新读取。');
  return context;
}
export async function mapRequest<T>(request: Promise<T>): Promise<T> {
  let timer: number = -1;
  const timeout = new Promise<T>((resolve, reject) => {
    timer = setTimeout(() => reject(new Error('地图请求超时，请检查网络后重试。')), 15000);
  });
  try { return await Promise.race([request, timeout]); }
  finally { if (timer !== -1) clearTimeout(timer); }
}
export function isWuhanCity(name: string | undefined): boolean {
  return name === '武汉' || name === '武汉市';
}
export function navigableLocation(context: LocationContext, personId: string): ResidenceLocation {
  const location = context.location;
  if (context.personId !== personId || !context.address || context.address.includes('*') || !location ||
    location.status !== 'confirmed' || location.addressSnapshot !== context.address ||
    !validCoordinate(location.latitude, location.longitude) || location.cityCode !== '420100' ||
    !['GCJ02', 'WGS84'].includes(location.coordinateSystem)) {
    throw new Error('当前位置未核验或住址已变化，请重新选点确认。');
  }
  return location;
}

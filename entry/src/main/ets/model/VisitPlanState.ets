import { AssistantAction } from './AssistantChat';

export interface VisitPlanPayload {
  date: string;
  startTime: string;
  endTime: string;
  transport: string;
  returnToStart: boolean;
}
export interface VisitCoordinate { latitude: number; longitude: number; }
export interface VisitOrigin extends VisitCoordinate { label: string; }
export interface VisitCandidate {
  personId: string; name: string; address: string; personRevision: number;
  taskIds: string[]; taskRevisions: number[]; latitude?: number; longitude?: number;
  coordinateSystem?: string; eligible: boolean; reason: string;
}
export interface VisitStopInput {
  personId: string; windowStart: string; windowEnd: string; serviceMinutes: number; appointmentConfirmed: boolean;
}
export interface VisitPlanPrepareInput {
  revision: number; origin: VisitOrigin; stops: VisitStopInput[];
}
export interface VisitPlanPrepared {
  actionId: string; revision: number; token: string; nodeIds: string[]; points: VisitCoordinate[];
  transport: string; returnToStart: boolean;
}
export interface VisitPlanSolveInput {
  revision: number; token: string; nodeIds: string[]; durations: (number | null)[][];
  distances: (number | null)[][]; provider: string;
}
export interface VisitPlanStop {
  personId: string; name: string; address: string; arrival: string; departure: string;
  travelSeconds: number; distanceMeters: number;
}
export interface VisitPlanTotals {
  travelSeconds: number; distanceMeters: number; serviceMinutes: number; waitingSeconds: number; finishTime: string;
}
export interface VisitPlanContext {
  action: AssistantAction; actionId: string; revision: number; payload: VisitPlanPayload;
  candidates: VisitCandidate[]; itinerary?: VisitPlanStop[]; totals?: VisitPlanTotals;
  provenance?: string; saved: boolean; planId?: string; unselected?: VisitCandidate[]; pendingVerification?: VisitCandidate[];
  origin?: VisitOrigin; stale?: boolean; warning?: string;
}
export interface VisitPlanNavigation extends VisitCoordinate { transport: string; }
export interface VisitPlanSummary {
  actionId: string; planId: string; date: string; startTime: string; endTime: string; transport: string; createdAt: string;
}
export interface VisitPlanList { items: VisitPlanSummary[]; nextCursor: string | null; }
export interface VisitRoadMatrix { durations: (number | null)[][]; distances: (number | null)[][]; }

export function visitPointValid(point: VisitCoordinate): boolean {
  return !!point && Number.isFinite(point.latitude) && Number.isFinite(point.longitude) &&
    point.latitude >= -90 && point.latitude <= 90 && point.longitude >= -180 && point.longitude <= 180;
}
export function visitDateValid(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const time = new Date(value + 'T12:00:00Z');
  return Number.isFinite(time.getTime()) && time.toISOString().slice(0, 10) === value;
}
export function visitTimeValid(value: string): boolean { return /^([01]\d|2[0-3]):[0-5]\d$/.test(value); }
export function visitPayloadError(payload: VisitPlanPayload): string {
  if (!visitDateValid(payload.date)) return '请填写真实日期，格式为YYYY-MM-DD。';
  if (!visitTimeValid(payload.startTime) || !visitTimeValid(payload.endTime) || payload.startTime >= payload.endTime) return '请填写当天起止时间，结束须晚于开始。';
  if (!['walking', 'driving'].includes(payload.transport)) return '请选择步行或驾车。';
  return '';
}
export function requireVisitPlan(value: VisitPlanContext, actionId: string): VisitPlanContext {
  if (!value || value.actionId !== actionId || !value.action || value.action.id !== actionId ||
    value.action.kind !== 'create_visit_plan' || value.action.revision !== value.revision ||
    !Number.isInteger(value.revision) || value.revision < 1 || !Array.isArray(value.candidates)) {
    throw new Error('回访计划与当前草稿不一致，请重新读取。');
  }
  return value;
}
export function requireVisitPlanEditable(value: VisitPlanContext): void {
  if (value.saved || value.stale || value.action.status !== 'draft' || !Number.isFinite(Date.parse(value.action.expiresAt)) ||
    Date.parse(value.action.expiresAt) <= Date.now()) throw new Error('计划已保存、取消或过期，请重新生成草稿。');
}
export function visitStopsError(stops: VisitStopInput[]): string {
  if (!stops.length || stops.length > 8) return '每次请选择1～8位居民。';
  const ids: string[] = [];
  for (const stop of stops) {
    if (!stop.personId || ids.includes(stop.personId)) return '居民选择重复，请重新核对。';
    ids.push(stop.personId);
    if (!stop.appointmentConfirmed) return '请逐位核对上门预约，再勾选已确认。';
    if (!visitTimeValid(stop.windowStart) || !visitTimeValid(stop.windowEnd) || stop.windowStart > stop.windowEnd) return '预约时间窗格式有误，请逐位核对。';
    if (!Number.isInteger(stop.serviceMinutes) || stop.serviceMinutes < 5 || stop.serviceMinutes > 180) return '服务时长须为5～180分钟的整数。';
  }
  return '';
}
export function requireVisitPrepared(value: VisitPlanPrepared, context: VisitPlanContext, stops: VisitStopInput[]): VisitPlanPrepared {
  if (!value || value.actionId !== context.actionId || value.revision !== context.revision || !value.token ||
    !Array.isArray(value.nodeIds) || !Array.isArray(value.points) || value.nodeIds.length !== stops.length + 1 ||
    value.points.length !== value.nodeIds.length || value.nodeIds[0] !== 'origin' || value.points.some((point: VisitCoordinate) => !visitPointValid(point)) ||
    value.transport !== context.payload.transport || value.returnToStart !== context.payload.returnToStart) throw new Error('算路节点与当前计划不一致，未请求地图。');
  for (let index = 0; index < stops.length; index++) {
    if (value.nodeIds[index + 1] !== stops[index].personId) throw new Error('算路居民顺序不一致，未请求地图。');
  }
  return value;
}

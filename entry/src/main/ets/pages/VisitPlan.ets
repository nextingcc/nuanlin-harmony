import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { site } from '@kit.MapKit';
import { Api } from '../model/Api';
import { VisitPlanMap } from '../model/VisitPlanMap';
import { VisitPlanContext, VisitPlanPayload, VisitCandidate, VisitStopInput, VisitOrigin, VisitPlanPrepareInput, VisitPlanSolveInput, VisitPlanStop, VisitPlanSummary,
  requireVisitPlan, requireVisitPlanEditable, requireVisitPrepared, visitPayloadError, visitStopsError } from '../model/VisitPlanState';
import { Theme, Palette, palette } from '../model/Theme';
import { readableFont } from '../model/UserPreferences';

@Entry
@Component
struct VisitPlan {
  @StorageProp('darkMode') darkMode: boolean = false;
  @StorageProp('textSize') textSize: string = 'normal';
  @State plan: VisitPlanContext | null = null;
  @State date: string = '';
  @State start: string = '';
  @State end: string = '';
  @State walking: boolean = true;
  @State returnToStart: boolean = false;
  @State dirty: boolean = false;
  @State stops: VisitStopInput[] = [];
  @State query: string = '';
  @State results: site.Site[] = [];
  @State origin: VisitOrigin | null = null;
  @State originConfirmed: boolean = false;
  @State busy: boolean = false;
  @State message: string = '';
  @State solved: boolean = false;
  @State savedPlans: VisitPlanSummary[] = [];
  @State nextCursor: string = '';
  @State listMode: boolean = false;
  private actionId: string = '';
  private generation: number = 0;
  private active: boolean = false;
  private p(): Palette { return palette(this.darkMode); }
  private font(size: number): number { return readableFont(size, this.textSize); }
  private editable(): boolean {
    return !!this.plan && !this.plan.saved && !this.plan.stale && this.plan.action.status === 'draft' &&
      Number.isFinite(Date.parse(this.plan.action.expiresAt)) && Date.parse(this.plan.action.expiresAt) > Date.now();
  }
  aboutToAppear(): void {
    this.actionId = ((router.getParams() as Record<string, Object>)?.['actionId'] as string) ?? '';
    this.listMode = !this.actionId;
  }
  onPageShow(): void { this.active = true; this.load(); }
  onPageHide(): void { this.active = false; this.generation++; this.busy = false; }
  aboutToDisappear(): void { this.active = false; this.generation++; }
  private current(turn: number): boolean { return this.active && turn === this.generation; }
  private payload(): VisitPlanPayload { return { date: this.date, startTime: this.start, endTime: this.end,
    transport: this.walking ? 'walking' : 'driving', returnToStart: this.returnToStart }; }
  private changed(): void {
    const original = this.plan?.payload;
    this.dirty = !original || this.date !== original.date || this.start !== original.startTime ||
      this.end !== original.endTime || (this.walking ? 'walking' : 'driving') !== original.transport ||
      this.returnToStart !== original.returnToStart;
    if (this.dirty) this.solved = false;
  }
  private async load(): Promise<void> {
    if (!this.actionId) { await this.loadList(); return; }
    const turn = ++this.generation; this.busy = true;
    try {
      const value = requireVisitPlan(await Api.visitPlan(this.actionId), this.actionId);
      if (!this.current(turn)) return;
      this.plan = value; this.date = value.payload.date; this.start = value.payload.startTime; this.end = value.payload.endTime;
      this.walking = value.payload.transport === 'walking'; this.returnToStart = value.payload.returnToStart;
      this.origin = value.origin ?? null; this.originConfirmed = false;
      this.dirty = false; this.solved = !!value.itinerary?.length;
      this.message = value.warning || ((!value.saved && !this.editable()) ? '计划已取消、过期或资料有变，请从助手重新生成。' : '');
    } catch (e) { if (this.current(turn)) this.message = (e as Error).message || '计划读取失败。'; }
    finally { if (this.current(turn)) this.busy = false; }
  }
  private async loadList(next: boolean = false): Promise<void> {
    if (this.busy) return;
    const turn = ++this.generation; this.busy = true;
    try {
      const result = await Api.visitPlanList(next ? this.nextCursor : '');
      if (!this.current(turn)) return;
      if (!result || !Array.isArray(result.items)) throw new Error('已保存计划列表读取失败，请重试。');
      this.savedPlans = next ? this.savedPlans.concat(result.items) : result.items;
      this.nextCursor = result.nextCursor ?? ''; this.message = '';
    } catch (e) { if (this.current(turn)) this.message = (e as Error).message || '读取失败，请重试。'; }
    finally { if (this.current(turn)) this.busy = false; }
  }
  private openSaved(item: VisitPlanSummary): void {
    if (this.busy || !item.actionId) return;
    this.actionId = item.actionId; this.listMode = false; this.plan = null; this.load();
  }
  private async saveConditions(): Promise<void> {
    if (!this.plan || this.busy) return;
    const turn = ++this.generation; this.busy = true;
    try {
      requireVisitPlanEditable(this.plan);
      const problem = visitPayloadError(this.payload()); if (problem) throw new Error(problem);
      const input = this.payload();
      await Api.updateAssistantAction(this.actionId, this.plan.revision, { date: input.date, startTime: input.startTime,
        endTime: input.endTime, transport: input.transport, returnToStart: input.returnToStart });
      if (!this.current(turn)) return;
      this.stops = []; this.solved = false; this.busy = false; await this.load();
    } catch (e) { if (this.current(turn)) this.message = (e as Error).message; }
    finally { if (this.current(turn)) this.busy = false; }
  }
  private toggle(person: VisitCandidate): void {
    if (this.busy || !person.eligible) return;
    const existing = this.stops.find((item: VisitStopInput) => item.personId === person.personId);
    if (existing) this.stops = this.stops.filter((item: VisitStopInput) => item.personId !== person.personId);
    else {
      if (this.stops.length >= 8) { this.message = '每次最多选择8位居民。'; return; }
      this.stops = this.stops.concat([{ personId: person.personId, windowStart: this.start, windowEnd: this.end, serviceMinutes: 30, appointmentConfirmed: false }]);
    }
    this.solved = false;
  }
  private stopFor(id: string): VisitStopInput | undefined { return this.stops.find((item: VisitStopInput) => item.personId === id); }
  private editStop(id: string, field: string, value: string, confirmed: boolean = false): void {
    this.stops = this.stops.map((item: VisitStopInput) => {
      if (item.personId !== id) return item;
      return { personId: item.personId, windowStart: field === 'start' ? value : item.windowStart,
        windowEnd: field === 'end' ? value : item.windowEnd, serviceMinutes: field === 'minutes' ? Number(value) : item.serviceMinutes,
        appointmentConfirmed: field === 'confirmed' ? confirmed : false };
    });
    this.solved = false;
  }
  private async search(): Promise<void> {
    if (this.busy) return;
    const turn = ++this.generation; this.busy = true;
    try { const found = await VisitPlanMap.search(getContext(this) as common.UIAbilityContext, this.query);
      if (this.current(turn)) { this.results = found; this.message = found.length ? '请选择真实出发点。' : '未找到武汉地点，请补充地址关键词。'; }
    } catch (e) { if (this.current(turn)) this.message = (e as Error).message || '地图搜索失败，请检查地图服务配置。'; }
    finally { if (this.current(turn)) this.busy = false; }
  }
  private async selectOrigin(item: site.Site): Promise<void> {
    if (this.busy) return;
    const turn = ++this.generation; this.busy = true; this.originConfirmed = false; this.solved = false;
    try { const point = await VisitPlanMap.origin(getContext(this) as common.UIAbilityContext, item);
      if (this.current(turn)) { this.origin = point; this.results = []; this.message = '请核对出发点后勾选确认。'; }
    } catch (e) { if (this.current(turn)) this.message = (e as Error).message || '地点核验失败。'; }
    finally { if (this.current(turn)) this.busy = false; }
  }
  private async calculate(): Promise<void> {
    if (!this.plan || this.busy) return;
    const turn = ++this.generation; this.busy = true; this.solved = false;
    try {
      requireVisitPlanEditable(this.plan);
      if (this.dirty) throw new Error('请先保存时间和出行方式，再安排居民。');
      if (!this.origin || !this.originConfirmed) throw new Error('请选定并人工核对武汉出发点。');
      const problem = visitStopsError(this.stops); if (problem) throw new Error(problem);
      const input: VisitPlanPrepareInput = { revision: this.plan.revision, origin: this.origin, stops: this.stops };
      const prepared = requireVisitPrepared(await Api.prepareVisitPlan(this.actionId, this.plan.revision, input), this.plan, this.stops);
      if (!this.current(turn)) return;
      this.message = '正在读取华为真实路网，居民姓名和档案不会发送给地图。';
      const matrix = await VisitPlanMap.matrix(getContext(this) as common.UIAbilityContext, prepared, this.plan.payload);
      if (!this.current(turn)) return;
      const solve: VisitPlanSolveInput = { revision: prepared.revision, token: prepared.token, nodeIds: prepared.nodeIds,
        durations: matrix.durations, distances: matrix.distances, provider: 'huawei_native' };
      const result = requireVisitPlan(await Api.solveVisitPlan(this.actionId, prepared.revision, solve), this.actionId);
      if (!this.current(turn)) return;
      this.plan = result; this.solved = !!result.itinerary?.length; this.message = '路线已计算，请人工核对后保存。';
    } catch (e) { if (this.current(turn)) this.message = (e as Error).message || '真实路网不可用，原计划与居民选择已保留，请重试。'; }
    finally { if (this.current(turn)) this.busy = false; }
  }
  private async confirm(): Promise<void> {
    if (!this.plan || this.busy || !this.solved || this.dirty) return;
    const turn = ++this.generation; this.busy = true;
    try { requireVisitPlanEditable(this.plan); await Api.confirmAssistantAction(this.plan.action, '', false);
      if (this.current(turn)) { this.busy = false; await this.load(); }
    } catch (e) { if (this.current(turn)) this.message = (e as Error).message || '保存失败，请重新读取。'; }
    finally { if (this.current(turn)) this.busy = false; }
  }
  private async navigate(personId: string): Promise<void> {
    if (!this.plan?.saved || this.busy) return;
    const turn = ++this.generation; this.busy = true;
    try { const target = await Api.visitPlanNavigation(this.actionId, personId);
      if (!this.current(turn)) return;
      await VisitPlanMap.navigate(getContext(this) as common.UIAbilityContext, target);
    } catch (e) { if (this.current(turn)) this.message = (e as Error).message || '无法打开导航，请检查地图应用。'; }
    finally { if (this.current(turn)) this.busy = false; }
  }
  build() {
    Column() {
      Row() {
        Button('返回').onClick(() => router.back()).backgroundColor(this.p().surface).fontColor(this.p().ink)
        Text('回访计划').fontSize(this.font(24)).fontWeight(FontWeight.Bold).fontColor(this.p().ink).layoutWeight(1).margin({ left: 12 })
      }.width('100%').padding(16)
      Scroll() {
        Column({ space: 16 }) {
          if (this.message) { Text(this.message).fontSize(this.font(16)).fontColor(this.p().ink2).width('100%') }
          if (this.plan) {
            Text(this.plan.saved ? '已保存 · 按站导航' : '核对条件与预约后，计算真实路网路线').fontSize(this.font(20)).fontColor(this.p().ink)
            if (this.origin) { Text('路线出发点：' + this.origin.label).fontSize(this.font(18)).fontColor(this.p().ink).width('100%') }
            if (this.editable()) {
              Column({ space: 10 }) {
                Text('日期与工作时间').fontSize(this.font(19)).fontColor(this.p().ink)
                TextInput({ text: this.date, placeholder: 'YYYY-MM-DD' }).fontColor(this.p().ink).backgroundColor(this.p().surfaceSoft).fontSize(this.font(16)).onChange((value: string) => { this.date = value; this.changed(); }).enabled(!this.busy)
                TextInput({ text: this.start, placeholder: '开始 HH:mm' }).fontColor(this.p().ink).backgroundColor(this.p().surfaceSoft).fontSize(this.font(16)).onChange((value: string) => { this.start = value; this.changed(); }).enabled(!this.busy)
                TextInput({ text: this.end, placeholder: '结束 HH:mm' }).fontColor(this.p().ink).backgroundColor(this.p().surfaceSoft).fontSize(this.font(16)).onChange((value: string) => { this.end = value; this.changed(); }).enabled(!this.busy)
                Row() {
                  Checkbox().selectedColor(Theme.greenDeep).select(this.walking).onChange((value: boolean) => { this.walking = value; this.changed(); }).enabled(!this.busy)
                  Text(this.walking ? '步行（取消勾选为驾车）' : '驾车（勾选改为步行）').fontColor(this.p().ink).fontSize(this.font(16))
                }
                Row() {
                  Checkbox().selectedColor(Theme.greenDeep).select(this.returnToStart).onChange((value: boolean) => { this.returnToStart = value; this.changed(); }).enabled(!this.busy)
                  Text('结束后返回出发点').fontColor(this.p().ink).fontSize(this.font(16))
                }
                Button('保存时间与出行方式').backgroundColor(Theme.greenDeep).enabled(!this.busy && this.dirty).onClick(() => this.saveConditions())
              }.padding(16).backgroundColor(this.p().surface).borderRadius(20).width('100%')
              Column({ space: 10 }) {
                Text('真实出发点 · 武汉').fontSize(this.font(19)).fontColor(this.p().ink)
                TextInput({ text: this.query, placeholder: '输入社区或出发地址关键词' }).fontColor(this.p().ink).backgroundColor(this.p().surfaceSoft).fontSize(this.font(16)).onChange((value: string) => { this.query = value; }).enabled(!this.busy)
                Button('搜索出发点').backgroundColor(Theme.greenDeep).enabled(!this.busy).onClick(() => this.search())
                ForEach(this.results, (item: site.Site) => {
                  Button(item.name + ' · ' + item.formatAddress).fontColor(this.p().ink).backgroundColor(this.p().surfaceSoft).onClick(() => this.selectOrigin(item)).enabled(!this.busy)
                })
                if (this.origin) {
                  Text(this.origin.label).fontColor(this.p().ink).fontSize(this.font(17))
                  Row() {
                    Checkbox().selectedColor(Theme.greenDeep).select(this.originConfirmed).enabled(!this.busy).onChange((value: boolean) => { this.originConfirmed = value; this.solved = false; })
                    Text('已核对这是实际武汉出发点').fontColor(this.p().ink).fontSize(this.font(16))
                  }
                }
              }.padding(16).backgroundColor(this.p().surface).borderRadius(20).width('100%')
              Text('待回访居民 · 最多8位').fontSize(this.font(20)).fontColor(this.p().ink).width('100%')
              ForEach(this.plan.candidates, (person: VisitCandidate) => {
                Column({ space: 8 }) {
                  Row() {
                    Checkbox().selectedColor(Theme.greenDeep).select(!!this.stopFor(person.personId)).enabled(person.eligible && !this.busy && !this.dirty).onChange(() => this.toggle(person))
                    Text(person.name).fontSize(this.font(19)).fontColor(this.p().ink)
                  }
                  Text(person.address).fontColor(this.p().ink2).fontSize(this.font(16)).width('100%')
                  if (!person.eligible) { Text(person.reason || '居所尚未核验，请先补齐档案。').fontColor(this.p().ink2).fontSize(this.font(16)) }
                  if (this.stopFor(person.personId)) {
                    Text('预约窗口与服务分钟（请人工核对）').fontColor(this.p().ink).fontSize(this.font(16))
                    TextInput({ text: this.stopFor(person.personId)?.windowStart ?? '', placeholder: '预约最早 HH:mm' }).fontColor(this.p().ink).backgroundColor(this.p().surfaceSoft).fontSize(this.font(16)).enabled(!this.busy).onChange((value: string) => this.editStop(person.personId, 'start', value))
                    TextInput({ text: this.stopFor(person.personId)?.windowEnd ?? '', placeholder: '预约最晚 HH:mm' }).fontColor(this.p().ink).backgroundColor(this.p().surfaceSoft).fontSize(this.font(16)).enabled(!this.busy).onChange((value: string) => this.editStop(person.personId, 'end', value))
                    TextInput({ text: String(this.stopFor(person.personId)?.serviceMinutes ?? 30), placeholder: '5～180分钟' }).fontColor(this.p().ink).backgroundColor(this.p().surfaceSoft).fontSize(this.font(16)).type(InputType.Number).enabled(!this.busy).onChange((value: string) => this.editStop(person.personId, 'minutes', value))
                    Row() {
                      Checkbox().selectedColor(Theme.greenDeep).select(this.stopFor(person.personId)?.appointmentConfirmed ?? false).enabled(!this.busy).onChange((value: boolean) => this.editStop(person.personId, 'confirmed', '', value))
                      Text('已与居民核对预约').fontColor(this.p().ink).fontSize(this.font(16))
                    }
                  }
                }.padding(16).backgroundColor(this.p().surface).borderRadius(20).width('100%')
              }, (person: VisitCandidate) => person.personId)
              Button(this.busy ? '处理中…' : '读取真实路网并规划').backgroundColor(Theme.greenDeep).fontSize(this.font(18)).enabled(!this.busy && !this.dirty).onClick(() => this.calculate())
            }
            if (this.solved || this.plan.saved) {
              if (this.plan.totals) {
                Text('路程 ' + (this.plan.totals.distanceMeters / 1000).toFixed(1) + '公里 · 行进 ' + Math.ceil(this.plan.totals.travelSeconds / 60) + '分钟\n服务 ' + this.plan.totals.serviceMinutes + '分钟 · 等候 ' + Math.ceil(this.plan.totals.waitingSeconds / 60) + '分钟\n预计结束 ' + this.plan.totals.finishTime).fontSize(this.font(18)).fontColor(this.p().ink).width('100%')
              }
              ForEach(this.plan.itinerary ?? [], (stop: VisitPlanStop) => {
                Column({ space: 8 }) {
                  Text(stop.name + ' · 预计到达 ' + stop.arrival + ' / 离开 ' + stop.departure).fontSize(this.font(19)).fontColor(this.p().ink)
                  Text(stop.address).fontSize(this.font(16)).fontColor(this.p().ink2)
                  if (this.plan?.saved) { Button('导航到此处').backgroundColor(Theme.greenDeep).enabled(!this.busy).onClick(() => this.navigate(stop.personId)) }
                }.padding(16).backgroundColor(this.p().surface).borderRadius(20).width('100%')
              })
            Text('道路数据由手机华为地图取得，预计到达时间仅供参考，出发前请核对实时路况。').fontSize(this.font(15)).fontColor(this.p().ink2)
              if (this.plan.saved) { Text('逐站导航使用高德地图；未安装时可由浏览器打开高德页面。').fontSize(this.font(15)).fontColor(this.p().ink2) }
              if (this.editable()) { Button('已人工核对，确认保存计划').backgroundColor(Theme.greenDeep).enabled(!this.busy && !this.dirty).onClick(() => this.confirm()) }
            }
            ForEach(this.plan.unselected ?? [], (person: VisitCandidate) => {
              Text('未安排：' + person.name + ' · ' + (person.reason || '未纳入本次选择，可分批安排。')).fontColor(this.p().ink2).fontSize(this.font(16)).width('100%')
            })
            ForEach(this.plan.pendingVerification ?? [], (person: VisitCandidate) => {
              Text('待核验：' + person.name + ' · ' + person.reason).fontColor(this.p().ink2).fontSize(this.font(16)).width('100%')
            })
          } else if (this.listMode) {
            Text('已保存的回访计划').fontSize(this.font(22)).fontColor(this.p().ink).width('100%')
            ForEach(this.savedPlans, (item: VisitPlanSummary) => {
              Button(item.date + '  ' + item.startTime + '～' + item.endTime + ' · ' + (item.transport === 'walking' ? '步行' : '驾车'))
                .backgroundColor(this.p().surface).fontColor(this.p().ink).fontSize(this.font(18)).borderRadius(20)
                .width('100%').enabled(!this.busy).onClick(() => this.openSaved(item))
            }, (item: VisitPlanSummary) => item.actionId)
            if (!this.savedPlans.length && !this.busy) { Text('暂无已保存计划，可通过助手生成并确认保存。').fontSize(this.font(17)).fontColor(this.p().ink2) }
            if (this.nextCursor) { Button('下一页').backgroundColor(Theme.greenDeep).enabled(!this.busy).onClick(() => this.loadList(true)) }
            Button('重新读取列表').backgroundColor(Theme.greenDeep).enabled(!this.busy).onClick(() => this.loadList())
          } else { Button('重新读取计划').backgroundColor(Theme.greenDeep).enabled(!this.busy).onClick(() => this.load()) }
        }.padding(16).width('100%')
      }.layoutWeight(1).width('100%')
    }.width('100%').height('100%').backgroundColor(this.p().pageBg)
  }
}

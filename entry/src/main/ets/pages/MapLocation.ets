import { amapResidenceUrl, openAmapUrl } from '../model/AmapNavigation';
import { router } from '@kit.ArkUI';
import { common, Want, bundleManager } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { MapComponent, map, mapCommon, site, petalMaps } from '@kit.MapKit';
import { Api } from '../model/Api';
import { LocationContext, LocationInput, validCoordinate, isWuhanCity, navigableLocation, mapRequest } from '../model/MapLocationState';
import { Theme, Palette, palette } from '../model/Theme';
import { openWebMap } from '../model/VisitPlanMap';
import { readableFont } from '../model/UserPreferences';

@Entry
@Component
struct MapLocation {
  @StorageProp('darkMode') darkMode: boolean = false;
  @StorageProp('textSize') textSize: string = 'normal';
  @State context: LocationContext | null = null;
  @State query: string = '';
  @State results: site.Site[] = [];
  @State candidate: LocationInput | null = null;
  @State message: string = '';
  @State mapError: string = '';
  @State busy: boolean = false;
  @State mapLoaded: boolean = false;
  @State acknowledged: boolean = false;
  @State walking: boolean = true;
  private personId: string = '';
  private sequence: number = 0;
  private controller?: map.MapComponentController;
  private marker?: map.Marker;
  private mapTimer: number = -1;
  private searchPreview: site.Site | null = null;
  private options: mapCommon.MapOptions = {
    position: { target: { latitude: 30.5928, longitude: 114.3055 }, zoom: 12 }
  };
  private p(): Palette { return palette(this.darkMode); }
  private font(size: number): number { return readableFont(size, this.textSize); }

  onPageShow(): void {
    if (!this.mapLoaded) this.mapTimer = setTimeout(() => {
      if (!this.mapLoaded) this.mapError = '地图尚未加载，请检查服务开通、应用签名或网络后重新进入。';
    }, 15000);
    this.personId = ((router.getParams() as Record<string, Object>)?.['personId'] as string) ?? '';
    this.load();
  }
  aboutToDisappear(): void {
    this.sequence++;
    if (this.mapTimer !== -1) clearTimeout(this.mapTimer);
  }

  private clearCandidate(): void {
    this.candidate = null;
    this.acknowledged = false;
    this.marker?.remove();
    this.marker = undefined;
  }

  private async load(): Promise<void> {
    const sequence = ++this.sequence;
    this.busy = true;
    this.context = null;
    this.results = [];
    this.searchPreview = null;
    this.clearCandidate();
    this.message = '';
    try {
      const context = await Api.residenceLocation(this.personId);
      if (sequence !== this.sequence) return;
      this.context = context;
      this.query = context.address;
      await this.showSaved();
      if (!context.address || context.address.includes('*')) this.message = '请先在住所信息页补全当前地址。';
    } catch (e) { if (sequence === this.sequence) this.message = (e as Error).message || '读取位置失败，请重试。'; }
    finally { if (sequence === this.sequence) this.busy = false; }
    if (sequence === this.sequence && this.context?.address && !this.context.address.includes('*')) {
      try { navigableLocation(this.context, this.personId); }
      catch (e) { await this.search(); }
    }
  }

  private mapReady(error: BusinessError, controller: map.MapComponentController): void {
    if (error) {
      this.mapError = '地图暂不可用，请检查地图服务开通、应用签名或网络。';
      this.mapLoaded = false;
      this.clearCandidate();
      return;
    }
    this.controller = controller;
    controller.on('mapLoad', () => {
      this.mapLoaded = true; this.mapError = '';
      if (this.mapTimer !== -1) clearTimeout(this.mapTimer);
      this.showSaved();
      this.showSearchPreview();
    });
    controller.on('mapClick', (point: mapCommon.LatLng) => { this.selectPoint(point); });
  }

  private async showSaved(): Promise<void> {
    if (!this.mapLoaded || !this.controller || !this.context?.location) return;
    const sequence = this.sequence;
    try {
      const location = navigableLocation(this.context, this.personId);
      const point: mapCommon.LatLng = { latitude: location.latitude, longitude: location.longitude };
      this.controller.moveCamera(map.newLatLng(point, 17));
      const marker = await this.controller.addMarker({ position: point, title: '已核对上门入口' });
      if (sequence !== this.sequence) { marker.remove(); return; }
      this.marker?.remove();
      this.marker = marker;
    } catch (e) { this.mapError = '已保存位置暂未能在地图显示，请重新核对。'; }
  }

  private async search(): Promise<void> {
    if (this.busy || !this.context || !this.query.trim()) return;
    const sequence = ++this.sequence;
    this.busy = true;
    this.results = [];
    this.searchPreview = null;
    this.clearCandidate();
    this.message = '';
    try {
      const result = await mapRequest(site.searchByText(getContext(this) as common.UIAbilityContext, {
        query: this.query.trim(), cityId: '420100', isCityLimit: true, countryCodes: ['CN'],
        language: 'zh', pageIndex: 1, pageSize: 20
      }));
      if (sequence !== this.sequence) return;
      this.results = (result.sites ?? []).filter((item: site.Site) =>
        isWuhanCity(item.addressComponent.adminLevel2) && item.location !== undefined);
      this.searchPreview = this.results[0] ?? null;
      this.message = this.results.length > 1 ? '找到多个住址候选，地图先展示首项，请从列表核对正确地点；尚未保存。' :
        (this.results.length === 1 ? '已找到住址候选，正在地图标出，请核对上门入口。' : '未找到准确住址，请补充小区或楼栋信息后重试。');
    } catch (e) {
      if (sequence === this.sequence) this.message = '地点搜索失败，请检查地图服务开通、应用签名或网络后重试。';
    } finally { if (sequence === this.sequence) this.busy = false; }
    if (sequence === this.sequence) await this.showSearchPreview();
  }

  private async showSearchPreview(): Promise<void> {
    const item = this.searchPreview;
    if (!this.mapLoaded || !this.controller || !item?.location || this.busy) return;
    this.searchPreview = null;
    if (this.results.length === 1) {
      await this.selectPoint(item.location, item.siteId);
      return;
    }
    const sequence = this.sequence;
    const point = item.location;
    try {
      this.controller.moveCamera(map.newLatLng(point, 17));
      const marker = await this.controller.addMarker({ position: point, title: '住址候选（待核对）' });
      if (sequence !== this.sequence) { marker.remove(); return; }
      this.marker?.remove(); this.marker = marker;
    } catch (e) { if (sequence === this.sequence) this.message = '已找到住址候选，请点击列表中的地点查看。'; }
  }

  private async selectPoint(point: mapCommon.LatLng, poiId: string = ''): Promise<void> {
    if (this.busy || !this.mapLoaded || !this.context || !validCoordinate(point.latitude, point.longitude)) return;
    const sequence = ++this.sequence;
    this.busy = true;
    this.clearCandidate();
    this.message = '正在核对地点所属城市…';
    try {
      const result = await mapRequest(site.reverseGeocode(getContext(this) as common.UIAbilityContext, { location: point, language: 'zh' }));
      if (sequence !== this.sequence) return;
      if (!isWuhanCity(result.addressComponent.adminLevel2)) throw new Error('当前只支持核验武汉市地点，请重新选择。');
      const candidate: LocationInput = { latitude: point.latitude, longitude: point.longitude,
        coordinateSystem: 'GCJ02', provider: 'huawei', cityCode: '420100',
        addressSnapshot: this.context.address, entranceLabel: result.addressDescription, poiId: poiId || null, confirmed: true };
      this.controller?.moveCamera(map.newLatLng(point, 17));
      const marker = await this.controller?.addMarker({ position: point, title: '待核对上门入口' });
      if (sequence !== this.sequence) { marker?.remove(); return; }
      this.marker = marker;
      this.candidate = candidate;
      this.message = '请核对地图位置、当前住址及可通行入口后确认保存。';
    } catch (e) { if (sequence === this.sequence) this.message = (e as Error).message || '地点核对失败，尚未保存。'; }
    finally { if (sequence === this.sequence) this.busy = false; }
  }

  private async save(): Promise<void> {
    if (this.busy || !this.mapLoaded || !this.context || !this.candidate || !this.acknowledged) return;
    this.busy = true;
    try {
      this.context = await Api.saveResidenceLocation(this.personId, this.context.revision, this.candidate);
      this.clearCandidate();
      await this.showSaved();
      this.message = '位置已由工作人员确认保存。';
    } catch (e) { this.message = (e as Error).message || '保存失败，请重新读取档案核对。'; }
    finally { this.busy = false; }
  }

  private async navigate(): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    this.message = '';
    try {
      const fresh = await Api.residenceLocation(this.personId);
      this.context = fresh;
      await openAmapUrl(getContext(this) as common.UIAbilityContext, amapResidenceUrl(fresh, this.personId, this.walking));
      this.message = '已请求高德打开目的地，若有重名请在高德确认。';
    } catch (e) { this.message = '未打开导航：位置无效或浏览器不可用，请复制坐标后在手机地图中搜索。'; }
    finally { this.busy = false; }
  }

  build() {
    Column() {
      Row() {
        Button('返回').backgroundColor(this.p().iconB).fontColor(this.p().accentText).onClick(() => router.back())
        Text('武汉住所定位').fontSize(this.font(18)).fontColor(this.p().ink).layoutWeight(1).textAlign(TextAlign.Center)
      }.padding(12).width('100%')
      Scroll() {
        Column({ space: 12 }) {
          Text('当前住址：' + (this.context?.address || '尚未读取')).fontSize(this.font(16)).fontColor(this.p().ink)
          Button('重新读取位置').enabled(!this.busy).backgroundColor(this.p().iconB).fontColor(this.p().accentText).onClick(() => this.load())
          TextInput({ text: this.query, placeholder: '武汉市、区、街道或小区' }).fontSize(this.font(16))
            .fontColor(this.p().ink).backgroundColor(this.p().surface).enabled(!this.busy)
            .onChange((value: string) => { this.query = value; this.results = []; this.clearCandidate(); })
          Button('搜索武汉地点').enabled(!this.busy && this.context !== null && !!this.context?.address)
            .backgroundColor(Theme.greenDeep).fontColor('#FFFFFF').onClick(() => this.search())
          Text('候选最多20项；只核对武汉地点。请勿把小区中心当作上门入口。').fontSize(this.font(14)).fontColor(this.p().muted)
          ForEach(this.results, (item: site.Site) => {
            Button((item.name || '候选地点') + '\n' + (item.formatAddress || ''))
              .width('100%').fontSize(this.font(16)).backgroundColor(this.p().iconB).fontColor(this.p().accentText)
              .enabled(!this.busy && this.mapLoaded).onClick(() => { if (item.location) this.selectPoint(item.location, item.siteId); })
          }, (item: site.Site) => item.siteId)
          MapComponent({ mapOptions: this.options, mapCallback: (error: BusinessError, controller: map.MapComponentController) => this.mapReady(error, controller) })
            .width('100%').height(300)
          if (!this.mapLoaded && !this.mapError) { Text('地图加载中…').fontSize(this.font(16)).fontColor(this.p().muted) }
          if (this.mapError) { Text(this.mapError).fontSize(this.font(16)).fontColor(this.p().danger) }
          if (this.candidate) {
            Text('选中位置：' + this.candidate.entranceLabel).fontSize(this.font(16)).fontColor(this.p().ink)
            Row() {
              Checkbox().select(this.acknowledged).selectedColor(Theme.greenDeep).onChange((value: boolean) => this.acknowledged = value)
              Text('已核对住址及上门入口').fontSize(this.font(16)).fontColor(this.p().ink)
            }
            Button('确认并保存地图位置').enabled(!this.busy && this.mapLoaded && this.acknowledged)
              .backgroundColor(Theme.greenDeep).fontColor('#FFFFFF').onClick(() => this.save())
          }
          if (this.context?.location) {
            Text('已保存入口：' + this.context.location.entranceLabel).fontSize(this.font(16)).fontColor(this.p().ink)
            Row({ space: 10 }) {
              Button('步行').backgroundColor(this.walking ? Theme.greenDeep : this.p().iconB).fontColor(this.walking ? '#FFFFFF' : this.p().accentText).onClick(() => this.walking = true)
              Button('驾车').backgroundColor(!this.walking ? Theme.greenDeep : this.p().iconB).fontColor(!this.walking ? '#FFFFFF' : this.p().accentText).onClick(() => this.walking = false)
            }
            Button('导航到这里').enabled(!this.busy).backgroundColor(Theme.greenDeep).fontColor('#FFFFFF').onClick(() => this.navigate())
          }
          if (this.message) { Text(this.message).fontSize(this.font(16)).fontColor(this.p().ink2) }
          Text('导航由地图应用获取当前位置；打开导航不会完成回访任务。').fontSize(this.font(14)).fontColor(this.p().muted)
        }.width('100%').padding(18).alignItems(HorizontalAlign.Start)
      }.width('100%').layoutWeight(1).align(Alignment.Top)
    }.width('100%').height('100%').backgroundColor(this.p().pageBg)
  }
}

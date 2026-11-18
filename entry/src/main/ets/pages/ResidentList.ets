import { readableFont, readableLineHeight } from '../model/UserPreferences';
import { router, promptAction } from '@kit.ArkUI';
import { Theme, Palette, palette } from '../model/Theme';
import { Avatar, Tag } from '../components/Common';
import { residents, Resident } from '../model/Data';
import { Api, Person } from '../model/Api';
import { residentAvatar } from '../model/ResidentAvatar';
import { Layout } from '../model/Layout';
import { BasicDataSource } from '../model/ListSource';

interface CardItem {
  id: string;
  name: string;
  age: number;
  gender: string;
  community: string;
  status: string;
  score: string;
  risk: string;
  needsFollowup?: boolean;
  lastAssessmentAt?: string | null;
  avatar: Resource;
}

@Entry
@Component
struct ResidentList {
  @StorageProp('textSize') preferenceTextSize: string = 'normal';
  @StorageProp('darkMode') darkMode: boolean = false;

  private p(): Palette { return palette(this.darkMode); }

  private font(base: number): number { return readableFont(base, this.preferenceTextSize); }
  private line(base: number): number { return readableLineHeight(base, this.preferenceTextSize); }

  @State filter: number = 0;
  @State cards: CardItem[] = [];
  @State live: boolean = false;
  @State loading: boolean = true;
  @State loadError: string = '';
  @State viewWidth: number = 0;

  private wide(): boolean {
    // 名单卡片信息密度高，只在 lg（≥840vp，平板横屏 / 2in1）才分两栏。
    return this.viewWidth >= Layout.LARGE;
  }

  private source: BasicDataSource<CardItem> = new BasicDataSource<CardItem>();

  private communityLabel(): string {
    const names: string[] = [];
    for (let i = 0; i < this.cards.length; i++) {
      const name = this.cards[i].community;
      if (name.length > 0 && name !== '社区未填写' && names.indexOf(name) < 0) names.push(name);
    }
    if (names.length === 0) return '青禾社区';
    return names.length === 1 ? names[0] : names.length + ' 个社区';
  }

  private filteredCards(): CardItem[] {
    return this.cards.filter(item => this.filter === 0 ||
      (this.filter === 1 && item.status === '已填表') ||
      (this.filter === 2 && item.status === '未填完') ||
      (this.filter === 3 && item.needsFollowup === true));
  }

  private refreshSource(): void {
    this.source.setItems(this.filteredCards());
  }

  onPageShow(): void {
    this.load();
  }

  private async load(): Promise<void> {
    this.loading = true;
    this.loadError = '';
    try {
      const list: Person[] = await Api.people();
      const mapped: CardItem[] = [];
      for (let i = 0; i < list.length; i++) {
        const person = list[i];
        mapped.push({
          id: person.id,
          needsFollowup: person.needsFollowup === true,
          lastAssessmentAt: person.lastAssessmentAt,
          name: person.name,
          age: person.age,
          gender: person.gender,
          community: person.community.length > 0 ? person.community : '社区未填写',
          status: person.assessmentCount > 0 ? '已填表' : '未填完',
          score: '—',
          risk: person.assessmentCount > 0 ? '有访谈记录' : '待访谈',
          avatar: residentAvatar(person.gender, person.id)
        } as CardItem);
      }
      this.cards = mapped;
      this.refreshSource();
      this.live = true;
    } catch (e) {
      this.live = false;
      this.loadError = (e as Error).message || '无法读取档案，请检查连接后重试。';
    } finally {
      this.loading = false;
    }
  }

  private confirmDelete(item: CardItem): void {
    AlertDialog.show({
      title: '删除档案',
      message: '确认删除 ' + item.name + ' 的档案？该操作不可撤销。',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: {
        value: '删除',
        action: async () => {
          const ok = await Api.deletePerson(item.id);
          if (ok) {
            this.load();
          } else {
            promptAction.showToast({ message: '删除失败，请重试', duration: 1500 });
          }
        }
      }
    });
  }

  private completedCount(): number {
    let n = 0;
    for (let i = 0; i < this.cards.length; i++) {
      if (this.cards[i].status === '已填表') n++;
    }
    return n;
  }

  private tagKind(status: string): string {
    if (status === '已逾期') return 'red';
    if (status === '未填完') return 'amber';
    return 'green';
  }

  @Builder
  residentCard(item: CardItem) {
    Row({ space: 12 }) {
      Avatar({ src: item.avatar, diameter: 46 })
      Column({ space: 4 }) {
        Row({ space: 8 }) {
          Text(item.name)
            .fontSize(this.font(15))
            .fontWeight(FontWeight.Medium)
            .fontColor(this.p().ink)
            .maxLines(this.preferenceTextSize === 'normal' ? 1 : 2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Tag({ text: item.status, kind: this.tagKind(item.status) })
        }
        .width('100%')
        Text(`${item.age} 岁 · ${item.gender || '性别未填写'} · ${item.community}`)
          .fontSize(this.font(10))
          .fontColor(this.p().muted)
          .maxLines(this.preferenceTextSize === 'normal' ? 1 : 3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(item.lastAssessmentAt ? '最近访谈 ' + item.lastAssessmentAt.slice(0, 10) : '暂无访谈日期')
          .fontSize(this.font(10))
          .fontColor((this.darkMode ? this.p().muted : '#B08A72'))
          .maxLines(this.preferenceTextSize === 'normal' ? 1 : 2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .onClick(() => {
        AppStorage.setOrCreate('selectedPerson', JSON.stringify(item));
        router.pushUrl({ url: 'pages/Profile' });
      })
      Text('删除')
        .fontSize(this.font(11))
        .fontColor(this.darkMode ? '#EADDF5' : '#705782')
        .padding({ left: 9, right: 9, top: 5, bottom: 5 })
        .maxLines(1)
        .textAlign(TextAlign.Center)
        .borderRadius(10)
        .backgroundColor(this.darkMode ? '#4D3E5D' : '#EDE1F4')
        .onClick((event: ClickEvent) => {
          this.confirmDelete(item);
        })
      Text('›')
        .fontSize(this.font(16))
        .fontColor((this.darkMode ? this.p().chevron : '#B08E76'))
        .onClick(() => {
          AppStorage.setOrCreate('selectedPerson', JSON.stringify(item));
          router.pushUrl({ url: 'pages/Profile' });
        })
    }
    .width('100%')
    .padding(12)
    .borderRadius(18)
    .backgroundColor((this.darkMode ? this.p().surface : 'rgba(255,252,247,0.94)'))
    .border({ width: 1, color: (this.darkMode ? this.p().border : '#F2E0D4') })
    .shadow({ radius: 10, color: 'rgba(120,72,60,0.07)', offsetY: 4 })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        Row() {
          Text('‹').accessibilityText('返回')
            .fontSize(26)
            .fontColor(this.p().ink)
            .width(32)
            .textAlign(TextAlign.Center)
            .onClick(() => router.replaceUrl({ url: 'pages/Home' }))
          Text('筛查工作台')
            .fontSize(this.font(18))
            .fontWeight(FontWeight.Medium)
            .fontColor(this.p().ink)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
          Text('♧')
            .fontSize(this.font(18))
            .fontColor(this.p().ink2)
            .width(32)
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .height(52)
        .padding({ left: 10, right: 10 })

        Row({ space: 8 }) {
          Text('⌕')
            .fontSize(this.font(15))
            .fontColor((this.darkMode ? this.p().segInk : '#8A6B54'))
          Text('输入姓名、电话或社区')
            .fontSize(this.font(12))
            .fontColor((this.darkMode ? this.p().muted : '#B0927C'))
            .layoutWeight(1)
        }
        .width('100%')
        .height(44)
        .padding({ left: 14, right: 14 })
        .margin({ left: 20, right: 20 })
        .borderRadius(16)
        .backgroundColor((this.darkMode ? this.p().surface : 'rgba(255,255,255,0.82)'))
        .border({ width: 1, color: (this.darkMode ? this.p().border : '#EFDCD2') })

        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach([`全部 ${this.cards.length}`, `已填表 ${this.completedCount()}`, `未填完 ${this.cards.length - this.completedCount()}`, `需回访 ${this.cards.filter(item => item.needsFollowup === true).length}`], (label: string, index: number) => {
            Text(label)
              .fontSize(this.font(11))
              .fontColor(index === this.filter ? '#FFFFFF' : (this.darkMode ? this.p().segInk : '#8A6B54'))
              .backgroundColor(index === this.filter ? (this.darkMode ? this.p().accent : '#586A43') : (this.darkMode ? this.p().chipBg : 'rgba(255,255,255,0.6)'))
              .borderRadius(15)
              .margin({ right: 8, bottom: 8 })
              .padding({ left: 12, right: 12, top: 7, bottom: 7 })
              .border({ width: index === this.filter ? 0 : 1, color: (this.darkMode ? this.p().border : '#EBD8CC') })
              .onClick(() => {
                this.filter = index;
                this.refreshSource();
              })
          }, (label: string) => label)
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 12 })

        Row() {
          Text(`${this.cards.length} 份档案 · ${this.communityLabel()}`)
            .fontSize(this.font(10))
            .fontColor((this.darkMode ? this.p().section : '#9C7E66'))
          Blank()
          Text(this.loading ? '正在加载…' : this.loadError ? '加载失败' : '已同步')
            .fontSize(this.font(10))
            .fontColor((this.darkMode ? this.p().section : '#9C7E66'))
        }
        .width('100%')
        .padding({ left: 22, right: 22, top: 14, bottom: 8 })

        List({ space: 10 }) {
          if (this.loadError) {
            ListItem() {
              Column({ space: 8 }) {
                Text(this.loadError).fontSize(this.font(13)).fontColor((this.darkMode ? this.p().danger : '#8D483E'))
                Button('重新加载').backgroundColor((this.darkMode ? this.p().accent : Theme.greenDeep)).onClick(() => this.load())
                if (this.loadError.includes('登录')) {
                  Button('重新登录').backgroundColor((this.darkMode ? this.p().accent : Theme.greenDeep))
                    .onClick(() => router.replaceUrl({ url: 'pages/Login' }))
                }
              }.width('100%').padding(18)
            }
          } else if (this.filteredCards().length === 0 && !this.loading) {
            ListItem() {
              Column({ space: 6 }) {
                Text('暂无档案').fontSize(this.font(14)).fontColor(this.p().ink)
                Text('点下方“新建人员”开始建档。').fontSize(this.font(10)).fontColor((this.darkMode ? this.p().segInk : '#8A6B54'))
              }
              .width('100%')
              .padding({ top: 60, bottom: 40 })
            }
          }
          LazyForEach(this.source, (item: CardItem) => {
            ListItem() {
              this.residentCard(item)
            }
          }, (item: CardItem) => `${item.id}:${item.gender}`)
        }
        .layoutWeight(1)
        .lanes(this.wide() ? 2 : 1, 10)
        .padding({ left: 20, right: 20, bottom: 100 })
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
      .width('100%')
      .height('100%')

      Row({ space: 10 }) {
        Button('＋  新建人员')
          .layoutWeight(1)
          .height(50)
          .fontSize(this.font(15))
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .backgroundColor((this.darkMode ? this.p().accent : Theme.greenDeep))
          .borderRadius(25)
          .onClick(() => router.pushUrl({ url: 'pages/PersonForm' }))
        Text('☰').accessibilityText('更多')
          .fontSize(this.font(18))
          .fontColor(this.p().ink2)
          .width(50)
          .height(50)
          .textAlign(TextAlign.Center)
          .borderRadius(25)
          .backgroundColor((this.darkMode ? this.p().surface : 'rgba(255,252,247,0.94)'))
          .border({ width: 1, color: (this.darkMode ? this.p().border : '#EDDACC') })
      }
      .width('100%')
      .padding({ left: 20, right: 20, bottom: 26 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor((this.darkMode ? this.p().pageBg : '#F7E8E3'))
    .onAreaChange((_old: Area, area: Area) => {
      const width = Layout.parseWidth(String(area.width));
      if (width !== this.viewWidth) this.viewWidth = width;
    })
  }
}

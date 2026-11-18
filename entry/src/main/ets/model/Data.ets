export interface Resident {
  id: string;
  name: string;
  age: number;
  gender: string;
  community: string;
  status: string;
  score: string;
  risk: string;
  avatar: Resource;
}

export interface TaskItem {
  time: string;
  title: string;
  sub: string;
  tag: string;
  done: boolean;
}

export const residents: Resident[] = [
  { id: '1', name: '王秀兰', age: 72, gender: '女', community: '青禾社区 3 栋', status: '已填表', score: '16 / 24', risk: '中风险', avatar: $r('app.media.avatar_f1') },
  { id: '2', name: '陈国栋', age: 78, gender: '男', community: '青禾社区 5 栋', status: '未填完', score: '8 / 24', risk: '访谈进行中', avatar: $r('app.media.avatar_m2') },
  { id: '3', name: '陈芳', age: 68, gender: '女', community: '青禾社区 1 栋', status: '已填表', score: '11 / 24', risk: '低风险', avatar: $r('app.media.avatar_f3') },
  { id: '4', name: '李长顺', age: 81, gender: '男', community: '青禾社区 7 栋', status: '已逾期', score: '—', risk: '复筛到期', avatar: $r('app.media.avatar_m1') },
  { id: '5', name: '赵桂芝', age: 75, gender: '女', community: '青禾社区 2 栋', status: '已填表', score: '19 / 24', risk: '需关注', avatar: $r('app.media.avatar_f4') }
];

export const tasks: TaskItem[] = [
  { time: '10:30', title: '王阿姨 · 上门回访', sub: '青禾社区 3 栋 · 72 岁 · 独居', tag: '待完成', done: false },
  { time: '14:00', title: '陈芳 · 风险等级确认', sub: '访谈已完成，待确认风险等级', tag: '待处理', done: false }
];

export const followups: Resident[] = [
  residents[0], residents[3], residents[2], residents[1], residents[4]
];

// 把一条建议格式化成备忘录文本；抽成纯函数，便于单测与复用。
// ArkTS 不支持结构类型，因此参数逐个传入，避免跨文件接口做结构匹配。
export function suggestionMemoId(suggestionId: string): string {
  return 'advice-' + suggestionId;
}

export function suggestionMemoText(title: string, text: string, steps: string[], category: string,
  createdAt: string, source: string, page: number, section: string): string {
  const pageText = page > 0 ? ' · 第' + page + '页' : '';
  const sectionText = section.length > 0 ? ' · ' + section : '';
  return '心情调节建议 · ' + title + '\n' + text + '\n' + steps.join('\n') +
    '\n分类：' + category + '\n生成时间：' + createdAt + '\n参考资料：' + source + pageText + sectionText;
}

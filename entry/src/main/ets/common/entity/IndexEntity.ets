// Tab栏构建
export interface TabBuild {
  name: string
  title: ResourceStr
  icon?: Resource
  icon_fill?: Resource
}

// 主页签固定顺序：main_show 设置项存储的索引基于此顺序，
// 小说模式下排行榜页签从列表中移除时，靠它换算回当前布局的索引
export const TAB_ORDER: string[] = ['home', 'rank', 'trend', 'search', 'more']
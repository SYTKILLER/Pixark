import { PixivIllust } from '../../services/PixivTypes';

/**
 * 会话级收藏状态中心：
 * 列表角标优先读本记录，未命中时回落到接口返回的 illust.is_bookmarked。
 * 在详情页收藏/取消收藏后写入，返回列表时角标可即时刷新。
 */
@ObservedV2
export class BookmarkState {
  @Trace overrides: Map<number, boolean> = new Map();

  isBookmarked(illust: PixivIllust): boolean {
    if (this.overrides.has(illust.id)) {
      return this.overrides.get(illust.id)!;
    }
    return !!illust.is_bookmarked;
  }

  setBookmarked(illustId: number, bookmarked: boolean) {
    this.overrides.set(illustId, bookmarked);
  }
}

export const bookmarkState = new BookmarkState();

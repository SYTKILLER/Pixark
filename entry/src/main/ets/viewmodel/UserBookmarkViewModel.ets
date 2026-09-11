import { PixState } from '../entryability/AppState';
import { PixivIllust } from '../services/PixivTypes';
import { createLogger } from '../common/utils/Logger';
import { toastUtil } from '../common/utils/ToastUtils';
import { pixiv } from '../services/PixivService';
import { DetailPageParams, IIllustSwiperProvider } from '../common/entity/DetailEntity';

const logger = createLogger('UserBookmarkViewModel')

/**
 * 他人主页收藏页 ViewModel：加载指定用户的公开收藏插画
 */
@ObservedV2
export class UserBookmarkViewModel implements IIllustSwiperProvider {

  @Trace bookmarks: PixivIllust[] = [];
  @Trace isLoading: boolean = false;
  @Trace isLoadingMore: boolean = false;

  private nextUrl: string = '';
  private loaded: boolean = false;
  private userId: number = 0;

  get illustIds(): number[] {
    return this.bookmarks.map(i => i.id);
  }

  get hasMore(): boolean {
    return !!this.nextUrl;
  }

  async loadMore(): Promise<void> {
    await this.load(this.nextUrl);
  }

  async onReady(userId: number) {
    this.userId = userId;
    this.bookmarks = [];
    this.nextUrl = '';
    this.loaded = false;
    await this.load();
    logger.debug(`[onReady] UserId: ${userId}, Loaded: ${this.bookmarks.length}`);
  }

  async load(url?: string) {
    const isLoadMore = !!url;
    if (!isLoadMore && this.loaded) return;
    if (isLoadMore) {
      this.isLoadingMore = true;
    } else {
      this.isLoading = true;
    }

    try {
      // tag 和 maxBookmarkId 不需要，传 undefined；他人收藏仅能访问公开部分
      const data = await pixiv.getUserBookmarks(this.userId, 'public', undefined, undefined, url);
      const newItems = data.illusts || [];
      this.bookmarks = isLoadMore ? [...this.bookmarks, ...newItems] : newItems;
      this.nextUrl = data.next_url || '';
      this.loaded = true;
      logger.debug(`[load] ${isLoadMore ? 'LoadMore' : 'Init'}. NewItems: ${newItems.length}, Total: ${this.bookmarks.length}, HasNext: ${!!this.nextUrl}`);
    } catch (e) {
      logger.error(`[load] Failed: ${JSON.stringify(e)}`);
      toastUtil.showToast({ message: "无法加载收藏（可能未公开）" });
    } finally {
      this.isLoading = false;
      this.isLoadingMore = false;
    }
  }

  handleIllustClick(illust: PixivIllust) {
    const index = this.bookmarks.findIndex(i => i.id === illust.id);
    const params: DetailPageParams = {
      id: illust.id,
      illust: illust.user ? illust : undefined,
      swiperProvider: this,
      swiperIndex: index >= 0 ? index : 0
    };
    PixState.pageStack.pushPathByName('illust_detail', params, true);
  }

}

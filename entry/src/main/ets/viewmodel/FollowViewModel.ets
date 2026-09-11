import { DetailPageParams } from "../common/entity/DetailEntity";
import { PixState } from "../entryability/AppState";
import { PixivIllust, UserPreview } from "../services/PixivTypes";
import { createLogger } from "../common/utils/Logger";
import { pixiv } from "../services/PixivService";

const logger = createLogger('FollowViewModel');

/** 单个筛选页（全部/公开/私密）的关注用户数据，每个 Swiper 页独立持有 */
@ObservedV2
export class FollowPageData {
  @Trace users: UserPreview[] = [];
  @Trace isLoading: boolean = false;
  // 仅供 Refresh 组件绑定：加载更多也会置 isLoading，Refresh 需与之分离
  @Trace isRefreshing: boolean = false;
  loaded: boolean = false;
  nextUrlPublic: string = '';
  nextUrlPrivate: string = '';
  // 该页进行中的加载任务：强制刷新前需等待其收尾，避免刷新被防抖吞掉或新旧数据错拼
  inflight?: Promise<void>;
}

/**
 * 关注页 ViewModel：当前用户关注的画师列表
 * 筛选维度（全部/公开/私密）各持有独立数据页，支持 Swiper 滑动切换
 */
@ObservedV2
class FollowViewModel {

  // --- 筛选器状态（与 Swiper 页联动）：0 全部, 1 公开, 2 私密 ---
  @Trace filterIndex: number = 0;

  // --- 数据状态 ---
  @Trace isInitialLoading: boolean = true;
  @Trace isLoadingMore: boolean = false;

  // 页面是否处于前台（账号切换时仅前台页面立即重载）
  isActive: boolean = false;

  // 各筛选页数据
  private userPages: FollowPageData[] =
    [new FollowPageData(), new FollowPageData(), new FollowPageData()];

  // --- 生命周期 ---
  async onReady() {
    this.isActive = true;
    logger.debug('[onReady] Follow page ready.');
    // 先加载当前筛选页，随后后台预载其余筛选页，保证滑动切换即有内容
    await this.loadPage(this.filterIndex);
    this.isInitialLoading = false;
    this.preloadOtherPages();
  }

  onDisappear() {
    this.isActive = false;
  }

  // --- UI 数据访问 ---
  userPage(index: number): FollowPageData {
    return this.userPages[index];
  }

  // --- 筛选页切换 ---
  // Swiper 翻页 / 筛选器点击后同步当前筛选页并懒加载
  syncFilter(index: number) {
    if (index < 0 || index > 2) return;
    this.filterIndex = index;
    this.ensurePageLoaded(index);
  }

  ensurePageLoaded(index: number) {
    const page = this.userPages[index];
    if (page.loaded || page.isLoading) return;
    this.loadPage(index);
  }

  private preloadOtherPages() {
    for (let i = 0; i < 3; i++) {
      if (i !== this.filterIndex) {
        this.ensurePageLoaded(i);
      }
    }
  }

  // 强制重置并重新加载 (用于切换账号)
  public resetAndLoad() {
    // 原地重置（页面 UI 持有各筛选页实例的引用，不能整体替换数组）
    for (const page of this.userPages) {
      page.users = [];
      page.isLoading = false;
      page.isRefreshing = false;
      page.loaded = false;
      page.nextUrlPublic = ''; page.nextUrlPrivate = '';
    }
    this.isInitialLoading = true;
    if (this.isActive) {
      this.onReady();
    }
  }

  // --- 加载逻辑 ---
  async loadPage(index: number, isLoadMore: boolean = false, force: boolean = false) {
    await this.loadFollowPage(index, isLoadMore, force);
  }

  // 下拉刷新：等待该页在途请求收尾后，强制重新加载第一页（非追加分支会整体替换列表）
  async refreshPage(index: number) {
    const page = this.userPages[index];
    if (page.isRefreshing) return;
    page.isRefreshing = true;
    try {
      await this.loadPage(index, false, true);
    } finally {
      page.isRefreshing = false;
    }
  }

  // 加载关注列表 (index: 0 全部=公开+私密并行, 1 公开, 2 私密)
  private async loadFollowPage(index: number, isLoadMore: boolean = false, force: boolean = false) {
    const page = this.userPages[index];
    // 防抖：该页已有任务在跑时直接返回；强制刷新则先等旧任务收尾再执行
    if (page.inflight !== undefined) {
      if (!force) return;
      await page.inflight.catch(() => {});
      if (page.inflight !== undefined) return;
    }
    if (!isLoadMore && page.loaded && !force) return;
    if (isLoadMore && (this.isLoadingMore || !this.hasMoreOf(index))) return;
    if (isLoadMore) this.isLoadingMore = true;
    page.isLoading = true;
    const task = (async () => {
      try {
        const userId = PixState.currentUser?.id || 0;
        let newData: UserPreview[] = [];
        if (index === 0) {
          // 并行请求公开和私密，合并数据 (先公开后私密)
          const results = await Promise.all([
            pixiv.getUserFollowing(userId, 'public', isLoadMore ? page.nextUrlPublic : undefined),
            pixiv.getUserFollowing(userId, 'private', isLoadMore ? page.nextUrlPrivate : undefined)
          ]);
          page.nextUrlPublic = results[0].next_url || '';
          page.nextUrlPrivate = results[1].next_url || '';
          newData = [...(results[0].user_previews || []), ...(results[1].user_previews || [])];
        } else if (index === 1) {
          const res = await pixiv.getUserFollowing(userId, 'public', isLoadMore ? page.nextUrlPublic : undefined);
          page.nextUrlPublic = res.next_url || '';
          newData = res.user_previews || [];
        } else {
          const res = await pixiv.getUserFollowing(userId, 'private', isLoadMore ? page.nextUrlPrivate : undefined);
          page.nextUrlPrivate = res.next_url || '';
          newData = res.user_previews || [];
        }
        page.users = isLoadMore ? [...page.users, ...newData] : newData;
        page.loaded = true;
        logger.debug(`[loadFollowPage] Filter: ${index}, Loaded ${newData.length} users.`);
      } catch (e) {
        logger.error(`[loadFollowPage] Failed: ${e.message}`);
      }
    })();
    page.inflight = task;
    try {
      await task;
    } finally {
      if (page.inflight === task) page.inflight = undefined;
      page.isLoading = false;
      if (isLoadMore) this.isLoadingMore = false;
    }
  }

  private hasMoreOf(index: number): boolean {
    const page = this.userPages[index];
    if (index === 0) return !!(page.nextUrlPublic || page.nextUrlPrivate);
    if (index === 1) return !!page.nextUrlPublic;
    return !!page.nextUrlPrivate;
  }

  // --- 交互逻辑 ---
  // 缩略图点击：不属于任何列表上下文，不传 Provider，让详情页自己拉取
  handleIllustClick(illust: PixivIllust, pathStack?: NavPathStack) {
    const params: DetailPageParams = {
      id: illust.id,
      swiperIndex: 0,
      illust: illust.user ? illust : undefined
    };
    (pathStack || PixState.pageStack).pushPathByName('illust_detail', params, true);
  }

  // --- 加载更多 ---
  async loadMore(): Promise<void> {
    await this.loadPage(this.filterIndex, true);
  }

}

export const followVM = new FollowViewModel();

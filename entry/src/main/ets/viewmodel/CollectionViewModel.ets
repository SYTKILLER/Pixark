import { DetailPageParams, IIllustSwiperProvider } from "../common/entity/DetailEntity";
import { PixState } from "../entryability/AppState";
import { PixivIllust, PixivNovel } from "../services/PixivTypes";
import { createLogger } from "../common/utils/Logger";
import { pixiv } from "../services/PixivService";
import { appSettings } from "../common/entity/SettingsModel";

const logger = createLogger('CollectionViewModel');

/** 单个筛选页（全部/公开/私密）的插画数据，每个 Swiper 页独立持有 */
@ObservedV2
export class CollectionIllustPageData {
  @Trace illusts: PixivIllust[] = [];
  @Trace isLoading: boolean = false;
  // 仅供 Refresh 组件绑定：加载更多也会置 isLoading，Refresh 需与之分离
  @Trace isRefreshing: boolean = false;
  loaded: boolean = false;
  nextUrlPublic: string = '';
  nextUrlPrivate: string = '';
  // 该页进行中的加载任务：强制刷新前需等待其收尾，避免刷新被防抖吞掉或新旧数据错拼
  inflight?: Promise<void>;
}

/** 单个筛选页（全部/公开/私密）的小说数据，每个 Swiper 页独立持有 */
@ObservedV2
export class CollectionNovelPageData {
  @Trace novels: PixivNovel[] = [];
  @Trace isLoading: boolean = false;
  @Trace isRefreshing: boolean = false;
  loaded: boolean = false;
  nextUrlPublic: string = '';
  nextUrlPrivate: string = '';
  inflight?: Promise<void>;
}

/**
 * 收藏页 ViewModel：当前用户的收藏（插画/小说）
 * 筛选维度（全部/公开/私密）各持有独立数据页，支持 Swiper 滑动切换
 */
@ObservedV2
class CollectionViewModel implements IIllustSwiperProvider {

  // --- 筛选器状态（与 Swiper 页联动）：0 全部, 1 公开, 2 私密 ---
  @Trace filterIndex: number = 0;

  // --- 数据状态 ---
  @Trace isInitialLoading: boolean = true;
  @Trace isLoadingMore: boolean = false;

  // 页面是否处于前台（账号切换时仅前台页面立即重载）
  isActive: boolean = false;

  // 各筛选页数据（插画 / 小说）
  private illustPages: CollectionIllustPageData[] =
    [new CollectionIllustPageData(), new CollectionIllustPageData(), new CollectionIllustPageData()];
  private novelPages: CollectionNovelPageData[] =
    [new CollectionNovelPageData(), new CollectionNovelPageData(), new CollectionNovelPageData()];

  // --- 生命周期 ---
  async onReady() {
    this.isActive = true;
    logger.debug('[onReady] Collection page ready.');
    // 先加载当前筛选页，随后后台预载其余筛选页，保证滑动切换即有内容
    await this.loadPage(this.filterIndex);
    this.isInitialLoading = false;
    this.preloadOtherPages();
  }

  onDisappear() {
    this.isActive = false;
  }

  // --- UI 数据访问 ---
  illustPage(index: number): CollectionIllustPageData {
    return this.illustPages[index];
  }

  novelPage(index: number): CollectionNovelPageData {
    return this.novelPages[index];
  }

  // --- 筛选页切换 ---
  // Swiper 翻页 / 筛选器点击后同步当前筛选页并懒加载
  syncFilter(index: number) {
    if (index < 0 || index > 2) return;
    this.filterIndex = index;
    this.ensurePageLoaded(index);
  }

  ensurePageLoaded(index: number) {
    if (appSettings.novel_mode) {
      const page = this.novelPages[index];
      if (page.loaded || page.isLoading) return;
    } else {
      const page = this.illustPages[index];
      if (page.loaded || page.isLoading) return;
    }
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
    for (const page of this.illustPages) {
      page.illusts = [];
      page.isLoading = false;
      page.isRefreshing = false;
      page.loaded = false;
      page.nextUrlPublic = ''; page.nextUrlPrivate = '';
    }
    for (const page of this.novelPages) {
      page.novels = [];
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

  // --- 详情页滑动联动 (IIllustSwiperProvider) ---
  get illustIds(): number[] {
    return this.illustPages[this.filterIndex].illusts.map(i => i.id);
  }

  get hasMore(): boolean {
    if (appSettings.novel_mode) {
      const page = this.novelPages[this.filterIndex];
      if (this.filterIndex === 0) return !!(page.nextUrlPublic || page.nextUrlPrivate);
      if (this.filterIndex === 1) return !!page.nextUrlPublic;
      return !!page.nextUrlPrivate;
    }
    const page = this.illustPages[this.filterIndex];
    if (this.filterIndex === 0) return !!(page.nextUrlPublic || page.nextUrlPrivate);
    if (this.filterIndex === 1) return !!page.nextUrlPublic;
    return !!page.nextUrlPrivate;
  }

  get isLoading(): boolean {
    return this.isLoadingMore;
  }

  // --- 加载逻辑 ---
  async loadPage(index: number, isLoadMore: boolean = false, force: boolean = false) {
    if (appSettings.novel_mode) {
      await this.loadNovelPage(index, isLoadMore, force);
    } else {
      await this.loadIllustPage(index, isLoadMore, force);
    }
  }

  // 下拉刷新：等待该页在途请求收尾后，强制重新加载第一页（非追加分支会整体替换列表）
  async refreshPage(index: number) {
    const page = appSettings.novel_mode ? this.novelPages[index] : this.illustPages[index];
    if (page.isRefreshing) return;
    page.isRefreshing = true;
    try {
      await this.loadPage(index, false, true);
    } finally {
      page.isRefreshing = false;
    }
  }

  // 加载收藏插画 (index: 0 全部=公开+私密并行, 1 公开, 2 私密)
  private async loadIllustPage(index: number, isLoadMore: boolean = false, force: boolean = false) {
    const page = this.illustPages[index];
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
        let newData: PixivIllust[] = [];
        if (index === 0) {
          // 并行请求公开和私密，合并数据 (先公开后私密)
          const results = await Promise.all([
            pixiv.getUserBookmarks(userId, 'public', undefined, undefined, isLoadMore ? page.nextUrlPublic : undefined),
            pixiv.getUserBookmarks(userId, 'private', undefined, undefined, isLoadMore ? page.nextUrlPrivate : undefined)
          ]);
          page.nextUrlPublic = results[0].next_url || '';
          page.nextUrlPrivate = results[1].next_url || '';
          newData = [...(results[0].illusts || []), ...(results[1].illusts || [])];
        } else if (index === 1) {
          const res = await pixiv.getUserBookmarks(userId, 'public', undefined, undefined, isLoadMore ? page.nextUrlPublic : undefined);
          page.nextUrlPublic = res.next_url || '';
          newData = res.illusts || [];
        } else {
          const res = await pixiv.getUserBookmarks(userId, 'private', undefined, undefined, isLoadMore ? page.nextUrlPrivate : undefined);
          page.nextUrlPrivate = res.next_url || '';
          newData = res.illusts || [];
        }
        page.illusts = isLoadMore ? [...page.illusts, ...newData] : newData;
        page.loaded = true;
        logger.debug(`[loadIllustPage] Filter: ${index}, Loaded ${newData.length} items.`);
      } catch (e) {
        logger.error(`[loadIllustPage] Failed: ${e.message}`);
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

  // 加载收藏小说 (index: 0 全部=公开+私密并行, 1 公开, 2 私密)
  private async loadNovelPage(index: number, isLoadMore: boolean = false, force: boolean = false) {
    const page = this.novelPages[index];
    // 同 loadIllustPage：防抖 + 强制刷新先等在途任务收尾
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
        let newData: PixivNovel[] = [];
        if (index === 0) {
          const results = await Promise.all([
            pixiv.getUserBookmarkNovel(userId, 'public', isLoadMore ? page.nextUrlPublic : undefined),
            pixiv.getUserBookmarkNovel(userId, 'private', isLoadMore ? page.nextUrlPrivate : undefined)
          ]);
          page.nextUrlPublic = results[0].next_url || '';
          page.nextUrlPrivate = results[1].next_url || '';
          newData = [...(results[0].novels || []), ...(results[1].novels || [])];
        } else if (index === 1) {
          const res = await pixiv.getUserBookmarkNovel(userId, 'public', isLoadMore ? page.nextUrlPublic : undefined);
          page.nextUrlPublic = res.next_url || '';
          newData = res.novels || [];
        } else {
          const res = await pixiv.getUserBookmarkNovel(userId, 'private', isLoadMore ? page.nextUrlPrivate : undefined);
          page.nextUrlPrivate = res.next_url || '';
          newData = res.novels || [];
        }
        page.novels = isLoadMore ? [...page.novels, ...newData] : newData;
        page.loaded = true;
      } catch (e) {
        logger.error(`[loadNovelPage] Failed: ${e.message}`);
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
    if (appSettings.novel_mode) {
      const page = this.novelPages[index];
      if (index === 0) return !!(page.nextUrlPublic || page.nextUrlPrivate);
      if (index === 1) return !!page.nextUrlPublic;
      return !!page.nextUrlPrivate;
    }
    const page = this.illustPages[index];
    if (index === 0) return !!(page.nextUrlPublic || page.nextUrlPrivate);
    if (index === 1) return !!page.nextUrlPublic;
    return !!page.nextUrlPrivate;
  }

  // --- 交互逻辑 ---
  // 统一的点击处理逻辑
  handleIllustClick(illust: PixivIllust, pathStack?: NavPathStack) {
    const index = this.illustPages[this.filterIndex].illusts.findIndex(i => i.id === illust.id);
    const params: DetailPageParams = {
      id: illust.id,
      swiperProvider: this,
      swiperIndex: index >= 0 ? index : 0,
      // 数据兜底, 如果 illust 对象没有 user 信息，说明是残缺数据，强制置空，让详情页自己拉
      illust: illust.user ? illust : undefined
    };
    // 执行跳转（平板分栏模式下压入所在页面的导航栈）
    (pathStack || PixState.pageStack).pushPathByName('illust_detail', params, true);
  }

  // --- 加载更多 ---
  async loadMore(): Promise<void> {
    await this.loadPage(this.filterIndex, true);
  }

}

export const collectionVM = new CollectionViewModel();

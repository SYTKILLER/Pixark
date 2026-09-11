import { UserDetailParams } from '../common/entity/UserDetailEntity';
import { PixState } from '../entryability/AppState';
import { PixivIllust, PixivNovel, PixivUser, UserDetailResponse } from '../services/PixivTypes';
import { createLogger } from '../common/utils/Logger';
import { toastUtil } from '../common/utils/ToastUtils';
import { pixiv } from '../services/PixivService';
import { DetailPageParams, IIllustSwiperProvider } from '../common/entity/DetailEntity';

const logger = createLogger('UserDetailViewModel')

@ObservedV2
export class UserDetailViewModel implements IIllustSwiperProvider {

  // 预加载的用户数据（用于瞬间显示）
  @Trace preUserData: PixivUser | null = null;
  // 完整的用户详情
  @Trace userData: UserDetailResponse | null = null;
  @Trace isFollow: boolean = false;
  @Trace isDetailLoading: boolean = false;
  // 统一的加载更多防抖状态
  @Trace isLoadingMore: boolean = false;

  // 分段控制器索引 (0: 插画, 1: 漫画, 2: 小说, 3: 详情)
  @Trace tabIndex: number = 0;

  // --- 插画相关 ---
  @Trace userIllusts: PixivIllust[] = [];
  @Trace isIllustLoading: boolean = false;
  private nextIllustUrl: string = '';

  // --- 漫画相关 ---
  @Trace userMangas: PixivIllust[] = [];
  @Trace isMangaLoading: boolean = false;
  private nextMangaUrl: string = '';

  // --- 小说相关 ---
  @Trace userNovels: PixivNovel[] = [];
  @Trace isNovelLoading: boolean = false;
  private nextNovelUrl: string = '';

  // 记录是否已经加载过
  private hasLoadedIllusts: boolean = false;
  private hasLoadedMangas: boolean = false;
  private hasLoadedNovels: boolean = false;

  // 嵌套滚动配置
  get nestedScrollOptions(): NestedScrollOptions {
    return {
      scrollForward: NestedScrollMode.PARENT_FIRST,
      scrollBackward: NestedScrollMode.SELF_FIRST,
    };
  }

  // 动态获取当前展示的插画 ID 列表 (插画/漫画 Tab 供详情页滑动联动)
  get illustIds(): number[] {
    return this.currentIllustList.map(i => i.id);
  }

  // 动态判断当前列表是否还有更多数据
  get hasMore(): boolean {
    if (this.tabIndex === 0) return !!this.nextIllustUrl;     // 插画
    if (this.tabIndex === 1) return !!this.nextMangaUrl;      // 漫画
    if (this.tabIndex === 2) return !!this.nextNovelUrl;      // 小说
    return false; // 详情 Tab
  }

  get isLoading(): boolean {
    return this.isLoadingMore;
  }

  async loadMore(): Promise<void> {
    await this.loadMoreCurrentData();
  }

  async onReady(ctx: NavDestinationContext, params: UserDetailParams) {
    const userId = params.id;
    // 初始化状态
    this.userIllusts = [];           // 清空插画列表
    this.userMangas = [];            // 清空漫画列表
    this.userNovels = [];            // 清空小说列表
    this.userData = null;            // 清空详情数据（避免闪现上一个用户的信息）

    this.nextIllustUrl = '';         // 重置插画分页
    this.nextMangaUrl = '';          // 重置漫画分页
    this.nextNovelUrl = '';          // 重置小说分页

    this.hasLoadedIllusts = false;   // 重置“已加载”标志位
    this.hasLoadedMangas = false;
    this.hasLoadedNovels = false;
    this.tabIndex = 0;               // 默认回到第一个 Tab (插画)
    // 页面初始化
    logger.debug(`[onReady] Start. UserId: ${userId}, HasPreUserData:${!!params.user}`);
    // 初始化预加载数据
    if (params.user) {
      this.preUserData = params.user;
      this.isFollow = params.user.is_followed;
      logger.debug(`[onReady] PreUserData applied. Name: ${params.user.name}, IsFollow: ${params.user.is_followed}`);
    }
    // 加载用户详细资料
    this.loadUserDetail(userId);
    // 预加载第一个 Tab 的数据（插画）
    if (this.tabIndex === 0) {
      this.loadUserIllusts(userId);
    }
  }

  // --- 核心数据加载 ---
  async loadUserDetail(userId: number) {
    this.isDetailLoading = true;
    logger.debug(`[loadUserDetail] Requesting userId=${userId}`);

    try {
      const data = await pixiv.getUserDetail(userId);
      this.userData = data;
      // 更新关注状态
      this.isFollow = data.user?.is_followed ?? false;
      const userName = data.user?.name || '未知用户';
      const followCount = data.profile?.total_follow_users ?? 0;
      const hasBackground = !!data.profile?.background_image_url;
      const comment = data.user?.comment || '';
      logger.debug(
        `[loadUserDetail] Success. Name: ${userName}, ` +
          `FollowCount: ${followCount}, Background:${hasBackground}, ` +
          `HasComment: ${comment.length > 0}`
      );
      // 清理预加载数据
      this.preUserData = null;
    } catch (e) {
      logger.error(`[loadUserDetail] Failed name: ${e.name}, message: ${e.message}`);
      toastUtil.showToast({ message: `加载用户信息失败, ${e.message}` });
    } finally {
      this.isDetailLoading = false;
    }
  }

  async loadUserIllusts(userId: number, url?: string) {
    const isLoadMore = !!url;
    // 防止重复请求
    if (!isLoadMore && this.hasLoadedIllusts) {
      logger.debug(`[loadUserIllusts] Skipped (already loaded). UserId: ${userId}`);
      return;
    }
    this.isIllustLoading = true;
    logger.debug(`[loadUserIllusts] ${isLoadMore ? 'LoadMore' : 'Init'}. UserId: ${userId}, NextUrl: ${url ? 'Exists' : 'None'}`);

    try {
      const data = await pixiv.getUserIllusts(userId, 'illust', url);
      const newIllusts = data.illusts || [];

      if (isLoadMore) {
        this.userIllusts.push(...newIllusts);
      } else {
        this.userIllusts = newIllusts;
      }

      this.nextIllustUrl = data.next_url || '';
      this.hasLoadedIllusts = true;
      // 插画加载成功
      logger.debug(`[loadUserIllusts] Success. NewItems: ${newIllusts.length}, Total: ${this.userIllusts.length}, HasNext: ${!!this.nextIllustUrl}`);
    } catch (e) {
      logger.error(`[loadUserIllusts] Failed: ${JSON.stringify(e)}`);
    } finally {
      this.isIllustLoading = false;
    }
  }

  async loadUserMangas(userId: number, url?: string) {
    const isLoadMore = !!url;
    // 防止重复请求
    if (!isLoadMore && this.hasLoadedMangas) {
      logger.debug(`[loadUserMangas] Skipped (already loaded). UserId: ${userId}`);
      return;
    }
    this.isMangaLoading = true;
    logger.debug(`[loadUserMangas] ${isLoadMore ? 'LoadMore' : 'Init'}. UserId: ${userId}, NextUrl: ${url ? 'Exists' : 'None'}`);

    try {
      const data = await pixiv.getUserIllusts(userId, 'manga', url);
      const newMangas = data.illusts || [];

      if (isLoadMore) {
        this.userMangas.push(...newMangas);
      } else {
        this.userMangas = newMangas;
      }

      this.nextMangaUrl = data.next_url || '';
      this.hasLoadedMangas = true;
      // 漫画加载成功
      logger.debug(`[loadUserMangas] Success. NewItems: ${newMangas.length}, Total: ${this.userMangas.length}, HasNext: ${!!this.nextMangaUrl}`);
    } catch (e) {
      logger.error(`[loadUserMangas] Failed: ${JSON.stringify(e)}`);
    } finally {
      this.isMangaLoading = false;
    }
  }

  async loadUserNovels(userId: number, url?: string) {
    const isLoadMore = !!url;
    // 防止重复请求
    if (!isLoadMore && this.hasLoadedNovels) {
      logger.debug(`[loadUserNovels] Skipped (already loaded). UserId: ${userId}`);
      return;
    }
    this.isNovelLoading = true;
    logger.debug(`[loadUserNovels] ${isLoadMore ? 'LoadMore' : 'Init'}. UserId: ${userId}, NextUrl: ${url ? 'Exists' : 'None'}`);

    try {
      const data = await pixiv.getUserNovels(userId, url);
      const newNovels = data.novels || [];

      if (isLoadMore) {
        this.userNovels.push(...newNovels);
      } else {
        this.userNovels = newNovels;
      }

      this.nextNovelUrl = data.next_url || '';
      this.hasLoadedNovels = true;
      // 小说加载成功
      logger.debug(`[loadUserNovels] Success. NewItems: ${newNovels.length}, Total: ${this.userNovels.length}, HasNext: ${!!this.nextNovelUrl}`);
    } catch (e) {
      logger.error(`[loadUserNovels] Failed: ${JSON.stringify(e)}`);
    } finally {
      this.isNovelLoading = false;
    }
  }

  // --- 交互逻辑 ---
  handleTabChange(index: number) {
    this.tabIndex = index;
    const userId = this.userData?.user.id;
    logger.debug(`[handleTabChange] Index: ${index}, UserId: ${userId}`);
    if (!userId) {
      logger.warn(`[handleTabChange] No userId found, skipping load.`);
      return;
    }
    if (index === 0) {
      this.loadUserIllusts(userId);
    } else if (index === 1) {
      this.loadUserMangas(userId);
    } else if (index === 2) {
      this.loadUserNovels(userId);
    }
  }

  async followOrCancel() {
    if (!this.userData) return;
    const userId = this.userData.user.id;
    const action = this.isFollow ? 'Unfollow' : 'Follow';

    logger.debug(`[followOrCancel] Start. Action: ${action}, UserId: ${userId}`);

    try {
      if (this.isFollow) {
        await pixiv.unfollowUser(userId);
        this.isFollow = false;
        if (this.userData.user) this.userData.user.is_followed = false;
      } else {
        await pixiv.followUser(userId, 'public');
        this.isFollow = true;
        if (this.userData.user) this.userData.user.is_followed = true;
      }
      logger.debug(`[followOrCancel] Success. Action: ${action}`);
    } catch (e) {
      logger.error(`[followOrCancel] Failed: ${JSON.stringify(e)}`);
      toastUtil.showToast({ message: "操作失败" });
    }
  }

  // --- 辅助获取 ---
  // 插画 / 漫画（同为 PixivIllust 结构，供 WaterFlowView 使用）
  get currentIllustList(): PixivIllust[] {
    if (this.tabIndex === 0) {
      return this.userIllusts;
    } else if (this.tabIndex === 1) {
      return this.userMangas;
    }
    return [];
  }

  // 统一的插画点击处理逻辑
  handleIllustClick(illust: PixivIllust) {
    // 自动计算当前插画在当前列表中的索引
    const index = this.currentIllustList.findIndex(i => i.id === illust.id);
    // 构造携带 Swiper 信息的参数
    const params: DetailPageParams = {
      id: illust.id,
      illust: illust,
      swiperProvider: this,       // 传入自身
      swiperIndex: index >= 0 ? index : 0
    };
    // 执行跳转
    PixState.pageStack.pushPathByName('illust_detail', params, true);
  }

  async loadMoreCurrentData() {
    if (this.isLoadingMore) return; // 防抖

    const userId = this.userData?.user.id;
    if (!userId) {
      logger.warn(`[loadMoreCurrentData] No userId found.`);
      return;
    }

    this.isLoadingMore = true;
    try {
      if (this.tabIndex === 0 && this.nextIllustUrl) {
        await this.loadUserIllusts(userId, this.nextIllustUrl);
      } else if (this.tabIndex === 1 && this.nextMangaUrl) {
        await this.loadUserMangas(userId, this.nextMangaUrl);
      } else if (this.tabIndex === 2 && this.nextNovelUrl) {
        await this.loadUserNovels(userId, this.nextNovelUrl);
      }
    } finally {
      this.isLoadingMore = false;
    }
  }

}

export const uDV = new UserDetailViewModel();

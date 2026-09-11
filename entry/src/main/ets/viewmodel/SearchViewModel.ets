import { DetailPageParams, IIllustSwiperProvider } from '../common/entity/DetailEntity';
import SearchHistoryInfo from '../common/entity/SearchHistoryInfo';
import { generateSuggestions, SuggestionItem } from '../common/entity/SearchSuggestion';
import { PixState, _PixState } from '../entryability/AppState';
import { PixivIllust, PixivNovel, PixivTrendingTag, UserPreview, SearchSort, SearchTarget, SearchR18Mode, SearchFilterOptions } from '../services/PixivTypes';
import { SearchHistoryTable } from '../common/utils/database/impl/SearchHistoryDao';
import { createLogger } from '../common/utils/Logger';
import { toastUtil } from '../common/utils/ToastUtils';
import { pixiv } from '../services/PixivService';
import { appSettings } from '../common/entity/SettingsModel';

const logger = createLogger('SearchViewModel')


@ObservedV2
class SearchViewModel implements IIllustSwiperProvider {

  // 搜索历史
  @Trace searchHistory: SearchHistoryInfo[] = []
  // 推荐标签
  @Trace trendingTags: PixivTrendingTag[] = [];
  // 搜索建议
  @Trace suggestions: SuggestionItem[] = [];
  // 搜索结果(插画)
  @Trace resultIllusts: PixivIllust[] = []
  // 小说搜索结果
  @Trace resultNovels: PixivNovel[] = []
  @Trace resultUsers: UserPreview[] = []

  @Trace showSuggestions: boolean = false
  @Trace searchHistoryEdit: boolean = false
  @Trace isLoadingMore: boolean = false;

  private IllustNextUrl: string = '';
  private novelNextUrl: string = '';
  private userNextUrl: string = '';

  @Trace keyword: string = '';
  @Trace searchType: 'illust' | 'novel' | 'user' = 'illust';

  // ===== 搜索筛选（不持久化，每次进入搜索页重置为默认） =====
  /** 排序方式，默认按人气 */
  @Trace filterSort: SearchSort = 'popular_desc';
  /** 关键字匹配方式，默认部分匹配标签 */
  @Trace filterTarget: SearchTarget = 'partial_match_for_tags';
  /** 收藏数下限，0 = 不限 */
  @Trace filterMinBookmark: number = 0;
  /** R-18 筛选：不限制 / 仅R-18 / 排除R-18 */
  @Trace filterR18: SearchR18Mode = 'none';

  /** 当前筛选是否处于非默认状态（用于筛选按钮小红点） */
  get isFilterActive(): boolean {
    return this.filterSort !== 'popular_desc' ||
      this.filterTarget !== 'partial_match_for_tags' ||
      this.filterMinBookmark !== 0 ||
      this.filterR18 !== 'none';
  }

  /** 重置筛选为默认值 */
  resetFilters() {
    this.filterSort = 'popular_desc';
    this.filterTarget = 'partial_match_for_tags';
    this.filterMinBookmark = 0;
    this.filterR18 = 'none';
  }

  /** 筛选条件变化后重新搜索当前关键词 */
  async applyFilters() {
    if (!this.keyword) return;
    this.lastSearchedIllustKeyword = '';
    this.lastSearchedNovelKeyword = '';
    this.resultIllusts = [];
    this.resultNovels = [];
    this.IllustNextUrl = '';
    this.novelNextUrl = '';
    await this.doSearch(true);
  }

  /** R-18 筛选通过关键字追加标签实现，仅用于请求参数，不影响搜索历史与显示 */
  private buildRequestWord(): string {
    if (this.filterR18 === 'only') return `${this.keyword} R-18`;
    if (this.filterR18 === 'exclude') return `${this.keyword} -R-18`;
    return this.keyword;
  }

  private lastSearchedIllustKeyword: string = '';
  private lastSearchedNovelKeyword: string = '';
  private lastSearchedUserKeyword: string = '';

  private debounceTimerId: number = -1;
  private searchHistoryDB: SearchHistoryTable | null = null;

  // 嵌套滚动配置
  get nestedScrollOptions(): NestedScrollOptions {
    return {
      scrollForward: NestedScrollMode.PARENT_FIRST,
      scrollBackward: NestedScrollMode.SELF_FIRST,
    };
  }
  get illustIds(): number[] { return this.searchType === 'illust' ? this.resultIllusts.map(i => i.id) : []; }
  get hasMore(): boolean {
    if (this.searchType === 'illust') return !!this.IllustNextUrl;
    if (this.searchType === 'novel') return !!this.novelNextUrl;
    return false;  // 画师模式不支持插画 Swiper 联动
  }
  get isLoading(): boolean { return this.isLoadingMore; }
  async loadMore(): Promise<void> { await this.loadMoreSearchResult(); }

  /**
   * 重置搜索状态
   * 通常在全局模式切换后，或重新进入搜索主页时调用
   */
  private resetSearchState() {
    // 强制将 searchType 对齐到当前全局模式
    this.searchType = appSettings.novel_mode ? 'novel' : 'illust';
    // 清空所有搜索结果和翻页 URL
    this.resultIllusts = [];
    this.resultNovels = [];
    this.resultUsers = [];
    this.IllustNextUrl = '';
    this.novelNextUrl = '';
    this.userNextUrl = '';
    // 清空缓存的关键词，确保下次搜索会真去请求
    this.lastSearchedIllustKeyword = '';
    this.lastSearchedNovelKeyword = '';
    this.lastSearchedUserKeyword = '';
    // 清空当前关键词
    this.keyword = '';
    // 筛选条件不持久化，重置为默认
    this.resetFilters();
  }

  // 获取数据库实例，实现懒加载
  private getDB(): SearchHistoryTable {
    if (!this.searchHistoryDB) {
      // 确保 Context 存在
      if (!_PixState.Context) {
        logger.error('Context 未初始化！');
        // 抛出错误或返回一个空壳对象防止崩溃，这里建议抛错以便发现
        throw new Error("Database Context is not ready!");
      }
      this.searchHistoryDB = new SearchHistoryTable(_PixState.Context);
    }
    return this.searchHistoryDB;
  }

  // 加载 搜索历史 & 推荐标签
  async loadData() {
    // 每次加载搜索主页数据时，先重置一下状态，避免模式切换后的残留
    this.resetSearchState();
    try {
      // await this.getDB().fixNullSearchType();
      const mode = appSettings.novel_mode ? 'novel' : 'illust';
      const values = await this.getDB().queryByMode(mode)
      this.searchHistory = values
    } catch (e) {
      logger.error('[DB_INIT] 加载搜索历史失败: ', e);
    }
    try {
      this.trendingTags = appSettings.novel_mode ? await pixiv.getNovelTrendTags() : await pixiv.getTrendingTags();
    } catch (e) {
      logger.error('加载热门标签失败:', e);
    }
  }

  async doSearch(force: boolean = false) {
    if (!this.keyword) return;
    this.showSuggestions = false

    // 纯数字视为作品/画师 ID，直接跳详情（覆盖 Tab 切换等绕过 handleSearchInput 的路径）
    if (/^\d+$/.test(this.keyword)) {
      this.jumpToDetail(this.keyword, this.searchType);
      return;
    }

    let shouldRequest = true;
    if (!force) {
      if (this.searchType === 'illust' && this.keyword === this.lastSearchedIllustKeyword) shouldRequest = false;
      else if (this.searchType === 'novel' && this.keyword === this.lastSearchedNovelKeyword) shouldRequest = false;
      else if (this.searchType === 'user' && this.keyword === this.lastSearchedUserKeyword) shouldRequest = false;
    }
    if (!shouldRequest) return;

    const word = this.buildRequestWord();
    // 人气优先：官方 API 的 sort=popular_desc 仅对 Premium 生效，免费账号会被静默忽略。
    // 参考 Pixiv-Shaft 的免费方案：改用 date_desc + 收藏数门槛近似热度排序，
    // 并把热门预览（popular-preview 接口）合并到头部，页内按收藏数降序。
    const isPopular = this.filterSort === 'popular_desc' && this.searchType !== 'user';
    const minBookmark = this.effectiveMinBookmark();
    const options: SearchFilterOptions = {
      sort: isPopular ? 'date_desc' : this.filterSort,
      searchTarget: this.filterTarget,
      minBookmark,
    };
    try {
      if (this.searchType === 'illust') {
        const data = await pixiv.searchIllust(word, undefined, options);
        let illusts = (data.illusts as PixivIllust[]) || [];
        if (isPopular) {
          // 合并热门预览结果到头部
          try {
            const preview = await pixiv.getPopularPreview(word);
            const ids = new Set(illusts.map(i => i.id));
            const hot = ((preview.illusts as PixivIllust[]) || [])
              .filter(i => !ids.has(i.id));
            illusts = hot.concat(illusts);
          } catch (e) { logger.warn('热门预览获取失败，忽略'); }
        }
        this.resultIllusts = this.postProcessIllusts(illusts, isPopular, minBookmark);
        this.IllustNextUrl = data.next_url || '';
        this.lastSearchedIllustKeyword = this.keyword;
      }
      // 小说搜索逻辑
      else if (this.searchType === 'novel') {
        const data = await pixiv.searchNovel(word, undefined, options);
        const novels = (data.novels as PixivNovel[]) || [];
        this.resultNovels = this.postProcessNovels(novels, isPopular, minBookmark);
        this.novelNextUrl = data.next_url || '';
        this.lastSearchedNovelKeyword = this.keyword;
      }
      else {
        const data = await pixiv.searchUser(this.keyword);
        this.resultUsers = data.user_previews;
        this.userNextUrl = data.next_url || '';
        this.lastSearchedUserKeyword = this.keyword;
      }
    } catch (e) { logger.error(`[搜索异常] ${JSON.stringify(e)}`); }
  }

  /**
   * 实际生效的收藏数门槛：
   * 免费 API 会忽略 bookmark_num_min 参数，因此收藏筛选必须在本地强制执行；
   * 人气模式下用户选"不限"时采用 500 作为默认热度门槛（近似 Shaft 方案）
   */
  private effectiveMinBookmark(): number {
    if (this.filterMinBookmark > 0) return this.filterMinBookmark;
    return this.filterSort === 'popular_desc' ? 500 : 0;
  }

  /** 插画结果本地过滤（服务端忽略收藏参数时的兜底）+ 人气模式页内排序 */
  private postProcessIllusts(list: PixivIllust[], popular: boolean, minBookmark: number): PixivIllust[] {
    let result = minBookmark > 0
      ? list.filter(i => (i.total_bookmarks ?? 0) >= minBookmark)
      : list;
    if (popular) {
      result = result.slice().sort((a, b) => (b.total_bookmarks ?? 0) - (a.total_bookmarks ?? 0));
    }
    return result;
  }

  /** 小说结果本地过滤 + 人气模式页内排序 */
  private postProcessNovels(list: PixivNovel[], popular: boolean, minBookmark: number): PixivNovel[] {
    let result = minBookmark > 0
      ? list.filter(n => (n.total_bookmarks ?? 0) >= minBookmark)
      : list;
    if (popular) {
      result = result.slice().sort((a, b) => (b.total_bookmarks ?? 0) - (a.total_bookmarks ?? 0));
    }
    return result;
  }

  // 加载更多
  async loadMoreSearchResult() {
    if (this.isLoadingMore) return; // 防抖

    const nextUrl = this.searchType === 'illust' ? this.IllustNextUrl :
      this.searchType === 'novel' ? this.novelNextUrl : this.userNextUrl;

    if (!nextUrl) {
      if ((this.searchType === 'illust' && this.resultIllusts.length > 0) ||
        (this.searchType === 'novel' && this.resultNovels.length > 0) ||
        (this.searchType === 'user' && this.resultUsers.length > 0)) {
        toastUtil.showToast({ message: $r('app.string.search_not_tips') });
      }
      return;
    }

    this.isLoadingMore = true;
    // 翻页结果同样需要本地兜底过滤（服务端可能忽略收藏数参数）与人气页内排序
    const popular = this.filterSort === 'popular_desc' && this.searchType !== 'user';
    const minBookmark = this.effectiveMinBookmark();
    // 本地过滤可能把整页滤空，此时自动续拉下一页（最多连续 5 页）
    const MAX_EMPTY_PAGES = 5;
    try {
      let url: string | undefined = nextUrl;
      for (let page = 0; page < MAX_EMPTY_PAGES && url; page++) {
        const pageUrl: string = url;
        let appended = 0;
        if (this.searchType === 'illust') {
          const data = await pixiv.searchIllust('', pageUrl);
          const list = this.postProcessIllusts((data.illusts as PixivIllust[]) || [], popular, minBookmark);
          appended = list.length;
          this.resultIllusts.push(...list);
          url = data.next_url || undefined;
          this.IllustNextUrl = url || '';
        } else if (this.searchType === 'novel') {
          const data = await pixiv.searchNovel('', pageUrl);
          const list = this.postProcessNovels((data.novels as PixivNovel[]) || [], popular, minBookmark);
          appended = list.length;
          this.resultNovels.push(...list);
          url = data.next_url || undefined;
          this.novelNextUrl = url || '';
        } else {
          const data = await pixiv.searchUser('', pageUrl);
          appended = data.user_previews.length;
          this.resultUsers.push(...data.user_previews);
          url = data.next_url || undefined;
          this.userNextUrl = url || '';
        }
        // 有结果（或画师模式/无过滤）即停止续拉
        if (appended > 0 || minBookmark === 0) break;
      }
    } catch (e) {
      logger.error(`[加载更多失败] 错误详情: ${JSON.stringify(e)}`);
    } finally {
      this.isLoadingMore = false;
    }
  }

  /**
   * 从搜索建议点击或搜索框提交时调用
   * 先判断是否为纯数字 ID，若是则跳转详情；否则执行关键词搜索
   */
  async handleSearchInput(input: string, type: 'illust' | 'user' | 'novel' = 'illust', force = false) {
    const text = input.trim();
    // 存数据库
    const currentMode = appSettings.novel_mode ? 'novel' : 'illust';
    this.getDB().saveOrUpdate(text, currentMode).then(async () => {
      const values = await this.getDB().queryByMode(currentMode)
      this.searchHistory = values
    })
    if (!text) return;
    // 判断是否为纯数字（作品 ID 或用户 ID）
    const isNumber = /^\d+$/.test(text);
    if (isNumber) {
      this.jumpToDetail(text, type);
      return;
    }
    // 非数字，当成关键词搜索
    this.doSearch(force);
  }

  /** 纯数字 ID 直达：插画/小说 → 作品详情，画师 → 画师详情 */
  private jumpToDetail(idText: string, type: 'illust' | 'user' | 'novel') {
    const id = Number(idText);
    const params: DetailPageParams = { id };
    if (type === 'user') {
      PixState.pageStack.pushPathByName('user_detail', params, true);
    } else {
      // 插画与小说详情共用路由，由详情页按 id 拉取
      PixState.pageStack.pushPathByName('illust_detail', params, true);
    }
  }

  handleIllustClick(illust: PixivIllust) {
    // 判断是否处于真正的插画列表上下文中
    const isIllustContext = this.searchType === 'illust';
    // 计算索引
    const index = isIllustContext ? this.resultIllusts.findIndex(i => i.id === illust.id) : 0;

    const params: DetailPageParams = {
      id: illust.id,
      // 只有在插画上下文才传 Provider，关注页传 undefined！
      swiperProvider: isIllustContext ? this : undefined,
      swiperIndex: index >= 0 ? index : 0,
      // 数据兜底, 如果 illust 对象没有 user 信息，说明是残缺数据，强制置空，让详情页自己拉
      illust: illust.user ? illust : undefined
    };
    // 跳转详情页
    PixState.pageStack.pushPathByName('illust_detail', params, true);
  }

  handleNovelClick(novel: PixivNovel) {
    // TODO: 跳转小说详情
    logger.info(`[handleNovelClick] Clicked novel: ${novel.id}`);
  }

  handleLongPressGesture(item: PixivTrendingTag) {
    // 长按进入详情页
    const params: DetailPageParams = { id: item.illust.id, illust: item.illust };
    PixState.pageStack.pushPathByName('illust_detail', params, true);
  }

  updateSuggestions(input: string) {
    this.showSuggestions = true
    if (this.debounceTimerId !== -1) {
      clearTimeout(this.debounceTimerId);
    }
    if (!input || input.trim().length === 0) {
      this.suggestions = [];
      return;
    }
    this.debounceTimerId = setTimeout(() => {
      const tags = this.trendingTags || [];
      const resultList = generateSuggestions(input.trim(), tags, [
        toastUtil.getResourceString($r('app.string.jump_illusst')),
        toastUtil.getResourceString($r('app.string.jump_user')),
        toastUtil.getResourceString($r('app.string.search'))], appSettings.novel_mode);
      this.suggestions = resultList;
    }, 300);
  }

  clearSearchHistory() {
    toastUtil.showDialog({
      title: $r('app.string.tips'),
      message: $r('app.string.confirm_clear_search_history'),
      buttons: [
        { text: $r('app.string.cancel'), color: '#999999' },
        { text: $r('app.string.clear'), color: '#FF0000' }
      ]
    }, async (err, data) => {
      if (data?.index === 1) {
        // 只清空当前模式的历史
        const currentMode = appSettings.novel_mode ? 'novel' : 'illust';
        await this.getDB().clearAll(currentMode)
        this.searchHistory = []
        this.searchHistoryEdit = false
      }
    });
  }

  async deleteSearch(id: number) {
    await this.getDB().deleteByID(id)
    this.searchHistory = this.searchHistory.filter((item) => item.id != id)
    if (this.searchHistory.length == 0) {
      this.searchHistoryEdit = false
    }
  }

}

export const searchVM = new SearchViewModel();

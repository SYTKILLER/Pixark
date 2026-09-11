import { pixiv } from '../services/PixivService';
import { PixivIllust, PixivNovel } from '../services/PixivTypes';
import { createLogger } from '../common/utils/Logger';
import { appSettings } from '../common/entity/SettingsModel';
import { toastUtil } from '../common/utils/ToastUtils';
import { FunctionConstants } from '../common/constants/FunctionConstants';
import { RankTab } from '../common/entity/RankModel';
import { DetailPageParams, IIllustSwiperProvider } from '../common/entity/DetailEntity';
import { PixState } from '../entryability/AppState';

const logger = createLogger('RankVM');

/** 单个排行榜分类的页面数据（每个 Swiper 页独立持有） */
@ObservedV2
export class RankPageData {
  @Trace illusts: PixivIllust[] = [];
  @Trace novels: PixivNovel[] = [];
  @Trace isLoading: boolean = false;
  nextUrl: string = '';
  nextNovelUrl: string = '';
  loaded: boolean = false;
}

@ObservedV2
export class RankViewModel implements IIllustSwiperProvider {
  // 各分类页面数据（key=分类 mode）
  private pageDataMap: Map<string, RankPageData> = new Map();
  // 数据缓存签名：分类配置/模式/日期任一变化即失效全部缓存
  private dataSignature: string = '';

  @Trace currentMode: string = 'day';
  @Trace currentDate: string = '';

  @Trace editingModes: string[] = [];
  @Trace editingSelected: Set<string> = new Set();

  // 获取当前激活的 Tab 列表
  get activeTabs(): RankTab[] {
    // 根据模式选择对应的配置数组
    const modes = appSettings.novel_mode
      ? (appSettings.novel_rank_modes || Object.keys(FunctionConstants.NOVEL_RANK_MODES))
      : appSettings.rank_modes;
    return modes.map(key => {
      const tab = new RankTab();
      tab.key = key;
      // 根据模式取对应的 label
      tab.label = appSettings.novel_mode
        ? (FunctionConstants.NOVEL_RANK_MODES[key] || key)
        : (FunctionConstants.ILLUST_RANK_MODES[key] || key);
      return tab;
    });
  }

  get isEmptyConfig(): boolean { return appSettings.rank_modes.length === 0; }

  /** 当前模式对应的页面数据 */
  get currentData(): RankPageData {
    return this.getPageData(this.currentMode);
  }

  get illustIds(): number[] {
    return appSettings.novel_mode ? this.currentData.novels.map(n => n.id) : this.currentData.illusts.map(i => i.id);
  }

  get hasMore(): boolean {
    return appSettings.novel_mode ? !!this.currentData.nextNovelUrl : !!this.currentData.nextUrl;
  }

  get isLoading(): boolean {
    return this.currentData.isLoading;
  }

  /** 获取指定分类的页面数据（配置/日期变化时自动失效重建） */
  getPageData(mode: string): RankPageData {
    const sig = this.currentSignature();
    if (sig !== this.dataSignature) {
      this.pageDataMap.clear();
      this.dataSignature = sig;
    }
    let data = this.pageDataMap.get(mode);
    if (!data) {
      data = new RankPageData();
      this.pageDataMap.set(mode, data);
    }
    return data;
  }

  private currentSignature(): string {
    const modes = appSettings.novel_mode
      ? (appSettings.novel_rank_modes || Object.keys(FunctionConstants.NOVEL_RANK_MODES))
      : appSettings.rank_modes;
    return `${appSettings.novel_mode ? 'novel' : 'illust'}|${this.currentDate}|${modes.join(',')}`;
  }

  /** 确保指定分类已加载（懒加载，Swiper 页进入时调用） */
  ensureLoaded(mode: string) {
    const data = this.getPageData(mode);
    if (data.loaded || data.isLoading) return;
    this.fetchRanking(mode);
  }

  /** 首次进入：校正当前分类并加载 */
  ensureFirstLoad() {
    const tabs = this.activeTabs;
    if (tabs.length > 0 && !tabs.some(t => t.key === this.currentMode)) {
      this.currentMode = tabs[0].key;
    }
    this.ensureLoaded(this.currentMode);
  }

  /** 当前分类在 Swiper 中的下标 */
  currentTabIndex(): number {
    return this.activeTabs.findIndex(t => t.key === this.currentMode);
  }

  /** Swiper 翻页后同步当前分类 */
  syncModeByIndex(index: number) {
    const tabs = this.activeTabs;
    if (index < 0 || index >= tabs.length) return;
    if (tabs[index].key !== this.currentMode) {
      this.currentMode = tabs[index].key;
    }
    this.ensureLoaded(this.currentMode);
  }

  changeMode(mode: string) {
    if (this.currentMode === mode) return;
    this.currentMode = mode;
    this.ensureLoaded(mode);
  }

  changeDate(date: Date) {
    this.currentDate = this.getFormattedDate(date);
    // 日期变化通过签名失效所有分类缓存后，重新加载当前分类
    this.fetchRanking(this.currentMode);
  }

  clearDate() {
    if (!this.currentDate) return;
    this.currentDate = '';
    this.fetchRanking(this.currentMode);
  }

  /** 加载指定分类的排行榜数据 */
  async fetchRanking(mode?: string) {
    // 获取当前模式下的可用 modes (优先用用户自定义的，没有则用全量默认)
    const supportedModes = appSettings.novel_mode
      ? (appSettings.novel_rank_modes || Object.keys(FunctionConstants.NOVEL_RANK_MODES))
      : (appSettings.rank_modes || Object.keys(FunctionConstants.ILLUST_RANK_MODES));

    let targetMode = mode ?? this.currentMode;
    if (supportedModes.length > 0 && !supportedModes.includes(targetMode)) {
      targetMode = supportedModes[0];
      this.currentMode = targetMode;
      logger.debug(`[fetchRanking] 当前mode不支持，自动回退至: ${targetMode}`);
    }

    const data = this.getPageData(targetMode);
    if (data.isLoading) return;
    data.isLoading = true;
    data.illusts = [];
    data.novels = [];
    data.nextUrl = '';
    data.nextNovelUrl = '';

    // date 参数，空字符串时不传
    const dateParam = this.currentDate || undefined;
    logger.debug(`[fetchRanking] 开始请求: mode=${targetMode}, date=${dateParam || '无'}, novelMode=${appSettings.novel_mode}`);
    try {
      if (appSettings.novel_mode) {
        const res = await pixiv.getNovelRanking(targetMode, dateParam);
        data.novels = res.novels || [];
        data.nextNovelUrl = res.next_url || '';
      } else {
        const res = await pixiv.getRanking(targetMode, dateParam);
        data.illusts = res.illusts || [];
        data.nextUrl = res.next_url || '';
      }
      data.loaded = true;
    } catch (e) {
      logger.error(`[fetchRanking] 请求失败: ${JSON.stringify(e)}`);
      toastUtil.showToast({ message: '加载排行榜失败' });
    } finally {
      data.isLoading = false;
    }
  }

  async loadMore(mode?: string) {
    const targetMode = mode ?? this.currentMode;
    const data = this.getPageData(targetMode);
    const hasMore = appSettings.novel_mode ? !!data.nextNovelUrl : !!data.nextUrl;
    if (data.isLoading || !hasMore) return;
    data.isLoading = true;
    try {
      if (appSettings.novel_mode) {
        const res = await pixiv.getNovelRanking(targetMode, this.currentDate, data.nextNovelUrl);
        const newNovels = res.novels || [];
        data.novels = [...data.novels, ...newNovels];
        data.nextNovelUrl = res.next_url || '';
      } else {
        const res = await pixiv.getRanking(targetMode, this.currentDate, data.nextUrl);
        const newIllusts = res.illusts || [];
        data.illusts = [...data.illusts, ...newIllusts];
        data.nextUrl = res.next_url || '';
      }
    } catch (e) {
      logger.error(`[loadMore] 请求失败: ${JSON.stringify(e)}`);
    } finally {
      data.isLoading = false;
    }
  }

  // 编辑面板逻辑
  openEditMode() {
    const allAvailableKeys = Object.keys(FunctionConstants.ILLUST_RANK_MODES)
      .filter(key => appSettings.show_H || !key.includes('r18'));
    const currentSelectedKeys = appSettings.rank_modes.filter(key => allAvailableKeys.includes(key));
    this.editingSelected = new Set(currentSelectedKeys);
    const unselectedKeys = allAvailableKeys.filter(key => !this.editingSelected.has(key));
    this.editingModes = [...currentSelectedKeys, ...unselectedKeys];
  }

  toggleModeInEdit(key: string) {
    const newSet = new Set(this.editingSelected);
    if (newSet.has(key)) { newSet.delete(key); } else { newSet.add(key); }
    this.editingSelected = newSet;
  }

  onDropTo(fromIndex: number, toIndex: number) {
    if (fromIndex < 0 || toIndex < 0 || fromIndex === toIndex) return;
    const arr = [...this.editingModes];
    const item = arr.splice(fromIndex, 1)[0];
    arr.splice(toIndex, 0, item);
    this.editingModes = arr;
  }

  saveModes() {
    const finalModes = this.editingModes.filter(key => this.editingSelected.has(key));
    if (finalModes.length === 0) { toastUtil.showToast({ message: '至少选择一个项目' }); return; }
    const isSame = finalModes.length === appSettings.rank_modes.length && finalModes.every((value, index) => value === appSettings.rank_modes[index]);
    if (isSame) return;
    appSettings.rank_modes = [...finalModes];
    if (!appSettings.rank_modes.includes(this.currentMode)) {
      this.currentMode = appSettings.rank_modes[0];
      this.fetchRanking();
    }
    toastUtil.showToast({ message: '配置已保存' });
  }

  // 插画点击逻辑
  handleIllustClick(illust: PixivIllust) {
    const index = this.currentData.illusts.findIndex(i => i.id === illust.id);
    const params: DetailPageParams = {
      id: illust.id, swiperProvider: this, swiperIndex: index >= 0 ? index : 0,
      illust: illust.user ? illust : undefined
    };
    PixState.pageStack.pushPathByName('illust_detail', params, true);
  }

  // 小说点击逻辑
  handleNovelClick(novel: PixivNovel) {
    // TODO: 跳转小说详情
    logger.info(`[handleNovelClick] Clicked novel: ${novel.id}`);
  }

  private getFormattedDate(date: Date): string {
    const y = date.getFullYear();
    const m = (date.getMonth() + 1).toString().padStart(2, '0');
    const d = (date.getDate()).toString().padStart(2, '0');
    return `${y}-${m}-${d}`;
  }

}

export const rankVM = new RankViewModel();

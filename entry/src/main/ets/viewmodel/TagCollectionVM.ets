import { PixivTag, AutoCompleteResponse } from '../services/PixivTypes';
import {
  tagCollectionService,
  TAG_TYPE_FAVORITE,
  TAG_TYPE_BLOCK,
  TagAddResult
} from '../common/utils/TagCollectionService';
import { compareKeyword, resolveGroupLetter } from '../common/utils/TagUtils';
import { toastUtil } from '../common/utils/ToastUtils';
import { pixiv } from '../services/PixivService';
import { createLogger } from '../common/utils/Logger';

const logger = createLogger('TagCollectionVM');

/** 管理页关键词条目 */
export interface KeywordView {
  name: string;
  translated: string;
}

/** 字母分组 */
export interface KeywordGroup {
  letter: string;
  keywords: KeywordView[];
}

/**
 * 关键词收藏/屏蔽 ViewModel：
 * 包装 TagCollectionService 的内存缓存为响应式状态，
 * 供详情页高亮/屏蔽占位与关键词管理页共用。
 */
@ObservedV2
export class TagCollectionVM {

  /** 收藏关键词快照（响应式，命中判断用） */
  @Trace favorites: string[] = [];
  /** 屏蔽关键词快照（响应式，命中判断用） */
  @Trace blocked: string[] = [];
  /** 收藏字母分组（管理页） */
  @Trace favoriteGroups: KeywordGroup[] = [];
  /** 屏蔽字母分组（管理页） */
  @Trace blockedGroups: KeywordGroup[] = [];

  constructor() {
    tagCollectionService.addListener(() => this.rebuild());
    this.rebuild();
  }

  /**
   * 由服务缓存重建响应式快照与分组
   */
  rebuild(): void {
    const records = tagCollectionService.getRecords();
    const favorites: string[] = [];
    const blocked: string[] = [];
    for (const r of records) {
      if (r.type === TAG_TYPE_FAVORITE) {
        favorites.push(r.name);
      } else if (r.type === TAG_TYPE_BLOCK) {
        blocked.push(r.name);
      }
    }
    this.favorites = favorites;
    this.blocked = blocked;
    this.favoriteGroups = this.buildGroups(TAG_TYPE_FAVORITE);
    this.blockedGroups = this.buildGroups(TAG_TYPE_BLOCK);
  }

  private buildGroups(type: number): KeywordGroup[] {
    const records = tagCollectionService.getRecords().filter(r => r.type === type);
    const list: KeywordView[] = records.map((r): KeywordView => {
      const kw: KeywordView = { name: r.name, translated: r.translatedName || '' };
      return kw;
    });
    list.sort((a, b) => compareKeyword(a, b));
    // compareKeyword 已保证同组连续，顺序归并成分组
    const groups: KeywordGroup[] = [];
    for (const kw of list) {
      const letter = resolveGroupLetter(kw.name, kw.translated);
      const last = groups[groups.length - 1];
      if (last && last.letter === letter) {
        last.keywords.push(kw);
      } else {
        const group: KeywordGroup = { letter: letter, keywords: [kw] };
        groups.push(group);
      }
    }
    return groups;
  }

  // ==============================
  // 命中判断（读取 @Trace 快照保证 UI 响应）
  // ==============================

  isFavorite(name: string): boolean {
    return this.favorites.indexOf(name) >= 0;
  }

  isBlocked(name: string): boolean {
    return this.blocked.indexOf(name) >= 0;
  }

  hasBlockedTags(tags: PixivTag[] | undefined): boolean {
    if (!tags) {
      return false;
    }
    for (const t of tags) {
      if (t && this.isBlocked(t.name)) {
        return true;
      }
    }
    return false;
  }

  /**
   * 作品标签命中的屏蔽词列表（详情页占位展示）
   */
  blockedNamesIn(tags: PixivTag[] | undefined): string[] {
    if (!tags) {
      return [];
    }
    const result: string[] = [];
    for (const t of tags) {
      if (t && this.isBlocked(t.name) && result.indexOf(t.name) < 0) {
        result.push(t.name);
      }
    }
    return result;
  }

  // ==============================
  // 增删操作（带 toast 反馈）
  // ==============================

  async addFavorite(name: string, translated: string = ''): Promise<void> {
    const outcome = await tagCollectionService.add(name, TAG_TYPE_FAVORITE, translated);
    if (outcome.result === TagAddResult.DUPLICATE) {
      toastUtil.showToast({ message: `#${TagCollectionVM.safeName(name)} 已在收藏列表中` });
      return;
    }
    if (outcome.movedFromOther) {
      toastUtil.showToast({ message: `已将 #${TagCollectionVM.safeName(name)} 从屏蔽移入收藏` });
    } else {
      toastUtil.showToast({ message: `已收藏 #${TagCollectionVM.safeName(name)}` });
    }
    this.backfillTranslation(name, translated);
  }

  async addBlocked(name: string, translated: string = ''): Promise<void> {
    const outcome = await tagCollectionService.add(name, TAG_TYPE_BLOCK, translated);
    if (outcome.result === TagAddResult.DUPLICATE) {
      toastUtil.showToast({ message: `#${TagCollectionVM.safeName(name)} 已在屏蔽列表中` });
      return;
    }
    if (outcome.movedFromOther) {
      toastUtil.showToast({ message: `已将 #${TagCollectionVM.safeName(name)} 从收藏移入屏蔽` });
    } else {
      toastUtil.showToast({ message: `已屏蔽 #${TagCollectionVM.safeName(name)}` });
    }
    this.backfillTranslation(name, translated);
  }

  async removeFavorite(name: string): Promise<void> {
    await tagCollectionService.remove(name, TAG_TYPE_FAVORITE);
    toastUtil.showToast({ message: `已取消收藏 #${TagCollectionVM.safeName(name)}` });
  }

  async removeBlocked(name: string): Promise<void> {
    await tagCollectionService.remove(name, TAG_TYPE_BLOCK);
    toastUtil.showToast({ message: `已取消屏蔽 #${TagCollectionVM.safeName(name)}` });
  }

  async removeBlockedNames(names: string[]): Promise<void> {
    await tagCollectionService.removeBlockedNames(names);
  }

  /**
   * 手动添加的关键词没有翻译，异步走搜索自动补全尝试补齐（用于排序分组）
   */
  /**
   * 获取关键词的官方翻译：
   * 一级走搜索自动补全（精确匹配优先，其次前缀匹配）；
   * 拿不到时二级兜底查一次搜索结果中同名词的译文
   */
  async tryFetchTranslation(name: string): Promise<string> {
    try {
      const resp: AutoCompleteResponse = await pixiv.getSearchAutocomplete(name);
      const tags = resp?.tags || [];
      let hit = tags.find(t => t.name === name && t.translated_name);
      if (!hit) {
        hit = tags.find(t => (t.name.startsWith(name) || name.startsWith(t.name)) && t.translated_name);
      }
      if (hit && hit.translated_name) {
        return hit.translated_name;
      }
      logger.debug(`tryFetchTranslation(ac) ${name}: ${tags.length} tags, no translation`);
    } catch (e) {
      logger.debug(`tryFetchTranslation(ac) failed: ${JSON.stringify(e)}`);
    }
    try {
      const result = await pixiv.searchIllust(name);
      const illusts = result?.illusts || [];
      for (const it of illusts) {
        const t = (it.tags || []).find(tg => tg.name === name && tg.translated_name);
        if (t && t.translated_name) {
          return t.translated_name;
        }
      }
      logger.debug(`tryFetchTranslation(search) ${name}: ${illusts.length} illusts, no translation`);
    } catch (e) {
      logger.debug(`tryFetchTranslation(search) failed: ${JSON.stringify(e)}`);
    }
    return '';
  }

  private isEnsuringTranslations: boolean = false;

  /**
   * 补齐列表中缺失翻译的关键词（管理页打开时调用，串行、限流 20 个）
   */
  async ensureTranslations(): Promise<void> {
    if (this.isEnsuringTranslations) {
      return;
    }
    this.isEnsuringTranslations = true;
    try {
      const missing = tagCollectionService.getRecords().filter(r => !r.translatedName);
      let count = 0;
      for (const r of missing) {
        if (count >= 20) {
          break;
        }
        const translated = await this.tryFetchTranslation(r.name);
        if (translated) {
          await tagCollectionService.updateTranslationIfEmpty(r.name, translated);
        }
        count++;
      }
    } finally {
      this.isEnsuringTranslations = false;
    }
  }

  /**
   * 添加后若无翻译，异步走搜索自动补全补齐（用于排序分组与展示）
   */
  private backfillTranslation(name: string, translated: string): void {
    if (translated || tagCollectionService.getTranslation(name)) {
      return;
    }
    this.tryFetchTranslation(name).then((t: string) => {
      if (t) {
        tagCollectionService.updateTranslationIfEmpty(name, t);
      }
    });
  }

  /**
   * 展示用名称：去掉输入可能带的 # 前缀
   */
  static safeName(name: string): string {
    return name.trim().replace(/^#+/, '');
  }
}

export const tagCollectionVM = new TagCollectionVM();

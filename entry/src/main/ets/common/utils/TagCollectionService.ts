import { Context } from '@kit.AbilityKit';
import { PixivIllust, PixivNovel, PixivTag } from '../../services/PixivTypes';
import TagCollectionInfo from '../entity/TagCollectionInfo';
import { TagCollectionTable } from './database/impl/TagCollectionDao';
import { createLogger } from './Logger';

const logger = createLogger('TagCollectionService');

/** 收藏类型 */
export const TAG_TYPE_FAVORITE: number = 0;
/** 屏蔽类型 */
export const TAG_TYPE_BLOCK: number = 1;

/** 增加结果 */
export enum TagAddResult {
  /** 成功 */
  OK = 0,
  /** 已存在于同类型列表 */
  DUPLICATE = 1,
}

export interface TagAddOutcome {
  result: TagAddResult;
  /** 本次操作把关键词从另一类型列表移除（互斥转移） */
  movedFromOther: boolean;
}

export type TagChangeListener = () => void;

/**
 * 关键词收藏/屏蔽服务：
 * 持有全量内存缓存（Set 匹配，避免逐条查库），由 EntryAbility 启动时 init，
 * 供 PixivData 列表过滤（屏蔽）与 TagCollectionVM（UI 高亮/管理页）共用。
 */
export class TagCollectionService {

  private table: TagCollectionTable | null = null;
  private readyPromise: Promise<void> | null = null;
  private records: TagCollectionInfo[] = [];
  private favoriteSet: Set<string> = new Set();
  private blockedSet: Set<string> = new Set();
  private listeners: TagChangeListener[] = [];

  /**
   * 启动时初始化（EntryAbility 调用，传入上下文）
   */
  init(context: Context): void {
    if (this.readyPromise) {
      return;
    }
    this.table = new TagCollectionTable(context);
    this.readyPromise = this.reload();
  }

  /**
   * 等待缓存就绪（未初始化时直接放行，按空数据兜底）
   */
  async ready(): Promise<void> {
    if (!this.readyPromise) {
      return;
    }
    await this.readyPromise;
  }

  private async reload(): Promise<void> {
    try {
      if (!this.table) {
        return;
      }
      this.records = await this.table.queryAll();
      this.rebuildSets();
      this.notify();
    } catch (e) {
      logger.error(`reload failed: ${JSON.stringify(e)}`);
    }
  }

  private rebuildSets(): void {
    this.favoriteSet = new Set(this.records.filter(r => r.type === TAG_TYPE_FAVORITE).map(r => r.name));
    this.blockedSet = new Set(this.records.filter(r => r.type === TAG_TYPE_BLOCK).map(r => r.name));
  }

  private notify(): void {
    this.listeners.forEach(l => {
      try {
        l();
      } catch (e) {
        logger.error(`listener error: ${JSON.stringify(e)}`);
      }
    });
  }

  addListener(listener: TagChangeListener): void {
    this.listeners.push(listener);
  }

  removeListener(listener: TagChangeListener): void {
    const idx = this.listeners.indexOf(listener);
    if (idx >= 0) {
      this.listeners.splice(idx, 1);
    }
  }

  /**
   * 归一化输入：去空白、去掉手动输入的 # 前缀
   */
  static normalize(name: string): string {
    return name.trim().replace(/^#+/, '').trim();
  }

  /**
   * 添加关键词。收藏与屏蔽互斥：加入一侧会自动从另一侧移除。
   */
  async add(name: string, type: number, translatedName: string = ''): Promise<TagAddOutcome> {
    const normalizedName = TagCollectionService.normalize(name);
    if (normalizedName.length === 0) {
      return { result: TagAddResult.DUPLICATE, movedFromOther: false };
    }
    await this.ready();
    try {
      const target = type === TAG_TYPE_FAVORITE ? this.favoriteSet : this.blockedSet;
      const other = type === TAG_TYPE_FAVORITE ? this.blockedSet : this.favoriteSet;
      if (target.has(normalizedName)) {
        return { result: TagAddResult.DUPLICATE, movedFromOther: false };
      }
      let movedFromOther = false;
      if (other.has(normalizedName) && this.table) {
        await this.table.deleteByNameAndType(normalizedName, type === TAG_TYPE_FAVORITE ? TAG_TYPE_BLOCK : TAG_TYPE_FAVORITE);
        movedFromOther = true;
      }
      // 已有翻译时保留旧翻译，避免空翻译覆盖
      let finalTranslated = translatedName;
      if (!finalTranslated) {
        const existing = this.records.find(r => r.name === normalizedName);
        if (existing && existing.translatedName) {
          finalTranslated = existing.translatedName;
        }
      }
      if (this.table) {
        await this.table.saveOrUpdate(new TagCollectionInfo(normalizedName, type, finalTranslated));
      }
      await this.reload();
      return { result: TagAddResult.OK, movedFromOther };
    } catch (e) {
      logger.error(`add failed: ${JSON.stringify(e)}`);
      return { result: TagAddResult.DUPLICATE, movedFromOther: false };
    }
  }

  /**
   * 移除关键词（按类型）
   */
  async remove(name: string, type: number): Promise<void> {
    const normalizedName = TagCollectionService.normalize(name);
    await this.ready();
    try {
      if (this.table) {
        await this.table.deleteByNameAndType(normalizedName, type);
      }
      await this.reload();
    } catch (e) {
      logger.error(`remove failed: ${JSON.stringify(e)}`);
    }
  }

  /**
   * 移除一组屏蔽关键词（详情页"取消屏蔽"用，移除后该作品恢复可见）
   */
  async removeBlockedNames(names: string[]): Promise<void> {
    if (names.length === 0) {
      return;
    }
    await this.ready();
    try {
      if (this.table) {
        for (const raw of names) {
          const n = TagCollectionService.normalize(raw);
          if (this.blockedSet.has(n)) {
            await this.table.deleteByNameAndType(n, TAG_TYPE_BLOCK);
          }
        }
      }
      await this.reload();
    } catch (e) {
      logger.error(`removeBlockedNames failed: ${JSON.stringify(e)}`);
    }
  }

  /**
   * 获取关键词的官方翻译（优先命中记录）
   */
  getTranslation(name: string): string {
    const record = this.records.find(r => r.name === name);
    return record ? record.translatedName : '';
  }

  /**
   * 若已知翻译比缓存新（例如详情页拿到了 translated_name），补写进记录
   */
  async updateTranslationIfEmpty(name: string, translatedName: string): Promise<void> {
    if (!translatedName) {
      return;
    }
    const record = this.records.find(r => r.name === name);
    if (!record || record.translatedName) {
      return;
    }
    record.translatedName = translatedName;
    try {
      if (this.table) {
        await this.table.saveOrUpdate(record);
      }
      await this.reload();
    } catch (e) {
      logger.error(`updateTranslationIfEmpty failed: ${JSON.stringify(e)}`);
    }
  }

  getRecords(): TagCollectionInfo[] {
    return this.records;
  }

  isFavorite(name: string): boolean {
    return this.favoriteSet.has(name);
  }

  isBlocked(name: string): boolean {
    return this.blockedSet.has(name);
  }

  /**
   * 作品标签中是否命中屏蔽词
   */
  hasBlockedTag(tags: PixivTag[] | undefined): boolean {
    if (!tags || this.blockedSet.size === 0) {
      return false;
    }
    for (const t of tags) {
      if (t && this.blockedSet.has(t.name)) {
        return true;
      }
    }
    return false;
  }

  /**
   * 列出作品标签中命中的全部屏蔽词（详情页占位展示/取消屏蔽用）
   */
  listBlockedTags(tags: PixivTag[] | undefined): string[] {
    if (!tags || this.blockedSet.size === 0) {
      return [];
    }
    const result: string[] = [];
    for (const t of tags) {
      if (t && this.blockedSet.has(t.name) && result.indexOf(t.name) < 0) {
        result.push(t.name);
      }
    }
    return result;
  }

  /**
   * 过滤插画列表（获取阶段屏蔽）
   */
  filterIllusts(illusts: PixivIllust[]): PixivIllust[] {
    if (this.blockedSet.size === 0) {
      return illusts;
    }
    return illusts.filter(i => !this.hasBlockedTag(i.tags));
  }

  /**
   * 过滤小说列表（获取阶段屏蔽）
   */
  filterNovels(novels: PixivNovel[]): PixivNovel[] {
    if (this.blockedSet.size === 0) {
      return novels;
    }
    return novels.filter(n => !this.hasBlockedTag(n.tags));
  }
}

export const tagCollectionService = new TagCollectionService();


import AutoTable from '../AutoTable';
import { ValueType } from '../AbsTable';
import { Table } from '../decorator/Decorators';
import { Context } from '@kit.AbilityKit';
import { createLogger } from '../../Logger';
import TagCollectionInfo from '../../../entity/TagCollectionInfo';

const logger = createLogger('TagCollectionTable');

/**
 * 关键词收藏/屏蔽记录表
 */
@Table({ db: 'pixiv_manager', name: 'tag_collection' })
export class TagCollectionTable extends AutoTable<TagCollectionInfo> {

  constructor(context: Context) {
    super(context, 'pixiv_manager', 'tag_collection');
  }

  // 返回实体类
  protected getEntityClass(): new (...args: any[]) => TagCollectionInfo {
    return TagCollectionInfo;
  }

  /**
   * 获取主键列名
   */
  getColumnId(): string {
    return 'id'
  }

  /**
   * 获取实体ID值
   */
  getEntityId(item: TagCollectionInfo): ValueType {
    return item.id
  }

  /**
   * 查询全部记录，按收录时间倒序
   */
  async queryAll(): Promise<TagCollectionInfo[]> {
    return this.query(this.getPredicates().orderByDesc('create_time'))
  }

  /**
   * 按类型查询（0 收藏 / 1 屏蔽）
   */
  async queryByType(type: number): Promise<TagCollectionInfo[]> {
    return this.query(this.getPredicates().equalTo('type', type).orderByDesc('create_time'))
  }

  /**
   * 按关键词原文精确查询（跨类型）
   */
  async queryByName(name: string): Promise<TagCollectionInfo[]> {
    return this.query(this.getPredicates().equalTo('name', name))
  }

  /**
   * 保存或更新（按 name + type 判断是否存在）
   */
  async saveOrUpdate(item: TagCollectionInfo): Promise<number> {
    logger.debug('saveOrUpdate', `name = ${item.name}, type = ${item.type}`)
    const results = await this.query(
      this.getPredicates().equalTo('name', item.name).and().equalTo('type', item.type)
    )
    if (results && results.length > 0) {
      const existing = results[0]
      item.id = existing.id
      return await this.update(item)
    }
    item.id = null
    return await this.insert(item)
  }

  /**
   * 删除指定关键词（按 name + type）
   */
  async deleteByNameAndType(name: string, type: number): Promise<number> {
    return this.deleteItem(
      this.getPredicates().equalTo('name', name).and().equalTo('type', type)
    )
  }
}

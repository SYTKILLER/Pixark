import { Column } from "../utils/database/decorator/Decorators";

/**
 * 关键词收藏/屏蔽记录
 */
export default class TagCollectionInfo {
  /**
   * 记录ID，新增时设置为 null 可实现自增
   */
  @Column({
    name: 'id',
    type: 'INTEGER',
    isPrimaryKey: true,
    autoIncrement: true
  })
  id: number | null = null;

  /**
   * 关键词原文（不含 # 前缀）
   */
  @Column({
    name: 'name',
    type: 'TEXT',
    notNull: true
  })
  name: string = '';

  /**
   * 类型：0 收藏，1 屏蔽
   */
  @Column({
    name: 'type',
    type: 'INTEGER',
    notNull: true
  })
  type: number = 0;

  /**
   * Pixiv 官方翻译（translated_name），用于排序分组，可为空
   */
  @Column({
    name: 'translated_name',
    type: 'TEXT',
    defaultValue: ''
  })
  translatedName: string = '';

  /**
   * 收录时间
   */
  @Column({
    name: 'create_time',
    type: 'INTEGER',
    notNull: true
  })
  createTime: number = 0;

  constructor(name: string = '', type: number = 0, translatedName: string = '') {
    this.name = name;
    this.type = type;
    this.translatedName = translatedName;
    this.createTime = new Date().getTime();
  }
}

import { intl } from '@kit.LocalizationKit';

/**
 * 关键词排序分组工具：
 * - 中文/汉字：取拼音首字母归组（拼音排序 Collator + 锚点汉字表，带缓存）
 * - 假名（平/片）：按五十音行映射到罗马音首字母（あ→A、か→K…浊音拗音归清音行）
 * - 拉丁字母：直接取字母
 * - 其余（符号、数字、其他语言）：归入 # 组
 */

// zh 区域显式指定拼音排序。真机验证结论：汉字之间按拼音排序可靠（阿<波），
// 但汉字整体排在拉丁字母之前（阿<a），因此不能与字母比较，需用拼音锚点汉字表
const zhCollator = new intl.Collator('zh-Hans-CN', { usage: 'sort', collation: 'pinyin' });

// 拼音锚点汉字表：每个字母取一个拼音首字母等于它的汉字（无 I/U/V）
const PINYIN_ANCHORS = '啊芭擦搭蛾发噶哈击喀垃妈拿哦啪期然撒塌挖昔压匝';
const ANCHOR_LETTERS = 'ABCDEFGHJKLMNOPQRSTWXYZ';

// 首字符分组结果缓存（关键词量级下避免重复 Collator 比较）
const initialCache: Map<string, string> = new Map();

// 五十音行首（清音行，浊音/拗音按 Unicode 顺延归入前一清音行）
const HIRA_ROWS = 'あかさたなはまやらわ';
const KATA_ROWS = 'アカサタナハマヤラワ';
const ROW_ROMAJI = ['A', 'K', 'S', 'T', 'N', 'H', 'M', 'Y', 'R', 'W'];

/**
 * 判断假名并返回其行首字母，非假名返回 null
 */
function kanaRowLetter(ch: string): string | null {
  const code = ch.charCodeAt(0);
  let rows: string | null = null;
  if (code >= 0x3041 && code <= 0x309F) {
    rows = HIRA_ROWS;
  } else if (code >= 0x30A1 && code <= 0x30FF) {
    rows = KATA_ROWS;
  }
  if (!rows) {
    return null;
  }
  // 拨音ん/ン单独归 N
  if (ch === 'ん' || ch === 'ン') {
    return 'N';
  }
  // 从最后一行往前找第一个行首 ≤ ch 的行
  for (let i = rows.length - 1; i >= 0; i--) {
    if (ch >= rows[i]) {
      return ROW_ROMAJI[i];
    }
  }
  return null;
}

/**
 * 取汉字的拼音首字母：从锚点表末位向前找第一个"小于等于该汉字"的锚点。
 * 依赖汉字间的拼音排序（真机已验证），锚点即各字母桶的起始汉字。
 */
function pinyinInitial(ch: string): string {
  const cached = initialCache.get(ch);
  if (cached) {
    return cached;
  }
  let result = '#';
  for (let i = PINYIN_ANCHORS.length - 1; i >= 0; i--) {
    if (zhCollator.compare(ch, PINYIN_ANCHORS[i]) >= 0) {
      result = ANCHOR_LETTERS[i];
      break;
    }
  }
  initialCache.set(ch, result);
  return result;
}

/**
 * 解析单个字符的分组字母，无法归类返回 '#'
 */
function charGroupLetter(ch: string): string {
  if ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')) {
    return ch.toUpperCase();
  }
  const code = ch.charCodeAt(0);
  if (code >= 0x4E00 && code <= 0x9FFF) {
    // 汉字：中文关键词直接取拼音；日文汉字关键词优先走翻译，无翻译时同样按拼音归组
    return pinyinInitial(ch);
  }
  const kana = kanaRowLetter(ch);
  if (kana) {
    return kana;
  }
  return '#';
}

/**
 * 解析关键词的分组字母：
 * 优先使用 Pixiv 官方翻译（中文）取拼音首字母；无翻译时按关键词原文归类
 */
export function resolveGroupLetter(name: string, translated: string): string {
  const key = translated && translated.length > 0 ? translated : name;
  const trimmed = key.replace(/^#+/, '');
  if (trimmed.length === 0) {
    return '#';
  }
  return charGroupLetter(trimmed.charAt(0));
}

/**
 * 关键词排序比较：先按分组字母（A-Z，# 最后），组内按排序键（翻译优先）的拼音序
 */
export interface SortableKeyword {
  name: string;
  translated: string;
}

export function compareKeyword(a: SortableKeyword, b: SortableKeyword): number {
  const la = resolveGroupLetter(a.name, a.translated);
  const lb = resolveGroupLetter(b.name, b.translated);
  if (la !== lb) {
    if (la === '#') {
      return 1;
    }
    if (lb === '#') {
      return -1;
    }
    return la < lb ? -1 : 1;
  }
  const ka = a.translated || a.name;
  const kb = b.translated || b.name;
  const cmp = zhCollator.compare(ka, kb);
  if (cmp !== 0) {
    return cmp;
  }
  return zhCollator.compare(a.name, b.name);
}

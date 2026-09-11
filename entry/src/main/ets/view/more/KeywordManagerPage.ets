import { PixState } from "../../entryability/AppState";
import { NaviContainer } from "../../components/NaviContainer";
import { EmptyStateView } from "../../components/CommonWidgets";
import { tagCollectionVM } from "../../viewmodel/TagCollectionVM";
import { KeywordGroup, KeywordView } from "../../viewmodel/TagCollectionVM";
import { TAG_TYPE_FAVORITE } from "../../common/utils/TagCollectionService";
import { searchVM } from "../../viewmodel/SearchViewModel";
import { toastUtil } from "../../common/utils/ToastUtils";
import { ColorUtils } from "../../common/utils/ColorUtils";
import { UISettings } from "../../common/entity/SettingsModel";
import { CustomContentDialog, SegmentButtonV2Items, TabSegmentButtonV2 } from "@kit.ArkUI";
import { ButtonOptions } from "@ohos.arkui.advanced.Dialog";
import { curves } from "@kit.ArkUI";
import { hdsEffect } from "@kit.UIDesignKit";

/**
 * 列表扁平行：字母头行 / 关键词行
 */
interface FlatRow {
  isHeader: boolean;
  letter: string;
  keyword?: KeywordView;
}

@Builder
export function KeywordManagerPageBuilder(name: string, param: Object) {
  KeywordManagerPage()
}

@ComponentV2
struct KeywordManagerPage {

  @Local pageStack: NavPathStack = new NavPathStack()
  private swiperController: SwiperController = new SwiperController()
  @Local currentTab: number = 0

  private tabItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '收藏' },
    { text: '屏蔽' },
  ]);

  aboutToAppear(): void {
    // 打开管理页时补齐已有关键词缺失的译文
    tagCollectionVM.ensureTranslations();
  }

  build() {
    NaviContainer({
      title: $r('app.string.keyword_manage'),
      content: () => {
        this.Content()
      },
      onReady: (ctx) => {
        this.pageStack = ctx.pathStack
      },
      onBackPressed: () => false
    })
  }

  @Builder
  Content() {
    Column({ space: 10 }) {
      // 收藏 / 屏蔽 子页切换
      Row() {
        TabSegmentButtonV2({
          items: this.tabItems,
          selectedIndex: this.currentTab!!,
          enableStateAnimation: true,
          onItemClicked: (tab) => {
            toastUtil.animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
              this.currentTab = tab;
              this.swiperController.changeIndex(tab);
            })
          }
        })
      }
      .padding({ left: PixState.PageMarginValue, right: PixState.PageMarginValue })
      .width('100%')

      Swiper(this.swiperController) {
        KeywordListPage({ type: TAG_TYPE_FAVORITE, pageStack: this.pageStack })
        KeywordListPage({ type: 1, pageStack: this.pageStack })
      }
      .index(this.currentTab)
      .loop(false)
      .indicator(false)
      .cachedCount(1)
      .duration(280)
      .nestedScroll(SwiperNestedScrollMode.SELF_FIRST)
      .onChange((index: number) => {
        toastUtil.animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
          this.currentTab = index;
        })
      })
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Start)
  }
}

/**
 * 单个关键词列表子页（收藏 / 屏蔽）：
 * 字母分组列表 + 右侧 AlphabetIndexer 索引条 + 滑动删除 + FAB 添加
 */
@ComponentV2
struct KeywordListPage {

  /** 0 收藏 / 1 屏蔽 */
  @Param type: number = 0
  @Param pageStack: NavPathStack = new NavPathStack()

  @Local selectedIndex: number = 0
  @Local inputText: string = ''
  @Local isAdding: boolean = false
  @Local addCancelled: boolean = false
  private addSeq: number = 0
  @Local dialogController: CustomDialogController | undefined = undefined

  private scroller: ListScroller = new ListScroller()

  aboutToAppear(): void {
    const buttons: ButtonOptions[] = [
      {
        value: $r('app.string.cancel'),
        buttonStyle: ButtonStyleMode.TEXTUAL,
        fontColor: $r('sys.color.font_secondary'),
        action: () => {
          this.addCancelled = true;
          this.dialogController?.close()
        }
      },
      {
        value: '添加',
        buttonStyle: ButtonStyleMode.TEXTUAL,
        fontColor: PixState.currentThemeColor,
        action: () => {
          this.confirmAdd()
        }
      }
    ];
    this.dialogController = new CustomDialogController({
      builder: CustomContentDialog({
        primaryTitle: this.type === TAG_TYPE_FAVORITE ? '添加收藏关键词' : '添加屏蔽关键词',
        secondaryTitle: '保存后将自动补全 # 前缀',
        contentBuilder: (): void => {
          this.InputBuilder()
        },
        buttons: buttons,
        contentAreaPadding: { top: 12, bottom: 12, left: 24, right: 24 },
        themeColorMode: UISettings.color_mode + 1
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      cornerRadius: 32
    })
  }

  private get groups(): KeywordGroup[] {
    return this.type === TAG_TYPE_FAVORITE ? tagCollectionVM.favoriteGroups : tagCollectionVM.blockedGroups;
  }

  private get letters(): string[] {
    return this.groups.map(g => g.letter);
  }

  /**
   * 扁平行模型：字母头行 + 关键词行统一展开，
   * 保证 AlphabetIndexer 与 List 的下标联动简单可靠
   */
  private get flatRows(): FlatRow[] {
    const rows: FlatRow[] = [];
    for (const g of this.groups) {
      const header: FlatRow = { isHeader: true, letter: g.letter };
      rows.push(header);
      for (const kw of g.keywords) {
        const row: FlatRow = { isHeader: false, letter: g.letter, keyword: kw };
        rows.push(row);
      }
    }
    return rows;
  }

  /** 字母分组头在列表中的扁平下标 */
  private letterStartIndex(letter: string): number {
    const rows = this.flatRows;
    for (let i = 0; i < rows.length; i++) {
      if (rows[i].isHeader && rows[i].letter === letter) {
        return i;
      }
    }
    return 0;
  }

  build() {
    // 智感握姿：0 右下(BottomEnd=8)，2 左下(BottomStart=6)，与详情页悬浮按钮一致
    Stack({ alignContent: 8 - PixState.buttonPosition }) {
      if (this.groups.length === 0) {
        Column() {
          EmptyStateView({
            icon: this.type === TAG_TYPE_FAVORITE ? $r('sys.symbol.star_circle') : $r('sys.symbol.exclamationmark_shield_fill'),
            message: this.type === TAG_TYPE_FAVORITE ? '暂无收藏的关键词\n长按作品详情页标签或点击右下角添加' : '暂无屏蔽的关键词\n长按作品详情页标签或点击右下角添加'
          })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        Row() {
          // 分组列表（字母头行 + 关键词行扁平展开，高度占满、内容从顶部开始）
          List({ space: 8, scroller: this.scroller }) {
            ForEach(this.flatRows, (row: FlatRow) => {
              if (row.isHeader) {
                // 字母分组头
                ListItem() {
                  Text(row.letter)
                    .fontSize(15)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(PixState.currentThemeColor)
                    .width('100%')
                    .padding({ left: 6, top: 4, bottom: 2 })
                }
              } else {
                // 关键词条目
                ListItem() {
                  Column({ space: 3 }) {
                    Text(row.keyword!.name)
                      .fontSize(15)
                      .fontColor($r('sys.color.font_primary'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .width('100%')
                    if (row.keyword!.translated && row.keyword!.translated !== row.keyword!.name) {
                      Text(row.keyword!.translated)
                        .fontSize(12)
                        .fontColor($r('sys.color.font_tertiary'))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .width('100%')
                    }
                  }
                  .alignItems(HorizontalAlign.Start)
                  .padding({ left: 16, right: 16, top: 11, bottom: 11 })
                  .borderRadius(16)
                  .backgroundColor($r('app.color.card_bg'))
                  .width('100%')
                }
                .onClick(() => {
                  if (this.type === TAG_TYPE_FAVORITE && row.keyword) {
                    // 收藏关键词点击跳转搜索（与详情页标签行为一致）
                    searchVM.keyword = row.keyword.name;
                    searchVM.searchType = 'illust';
                    toastUtil.animateTo({
                      curve: curves.interpolatingSpring(0, 1, 342, 38)
                    }, () => {
                      this.pageStack.pushPath({ name: 'searching_page' }, false);
                    })
                  }
                })
                .swipeAction({
                  end: {
                    builder: () => {
                      this.DeleteSwipeButton(row.keyword!.name)
                    }
                  }
                })
                .transition({
                  type: TransitionType.Insert,
                  opacity: 0,
                })
                .transition({
                  type: TransitionType.Delete,
                  opacity: 0,
                  scale: { x: 0.95, y: 0.95 }
                })
              }
            }, (row: FlatRow) => row.isHeader ? `${this.type}_h_${row.letter}` : `${this.type}_${row.keyword!.name}`)
          }
          .width('100%')
          .layoutWeight(1)
          .height('100%')
          .padding({ left: 16, right: 4, top: 8 })
          .contentEndOffset(PixState.bottomRectHeight == 0 ? 16 : PixState.bottomRectHeight + 16)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .onScrollIndex((first: number) => {
            const rows = this.flatRows;
            if (first < 0 || first >= rows.length) {
              return;
            }
            const letter = rows[first].letter;
            const idx = this.letters.indexOf(letter);
            if (idx >= 0 && idx !== this.selectedIndex) {
              this.selectedIndex = idx;
            }
          })

          // 右侧字母索引条
          AlphabetIndexer({ arrayValue: this.letters, selected: this.selectedIndex })
            .usingPopup(true)
            .autoCollapse(true)
            .selectedColor(PixState.currentThemeColor)
            .color($r('sys.color.font_tertiary'))
            .selectedBackgroundColor(ColorUtils.getColorWithAlphaString(PixState.currentThemeColor, 15))
            .popupColor(PixState.currentThemeColor)
            .popupBackgroundBlurStyle(BlurStyle.COMPONENT_THIN)
            .itemSize(24)
            .margin({ right: 4 })
            .onSelect((index: number) => {
              this.selectedIndex = index;
              this.scroller.scrollToIndex(this.letterStartIndex(this.letters[index]));
            })
        }
        .width('100%')
        .height('100%')
        .alignItems(VerticalAlign.Top)
      }

      // FAB：蓝色背景 + 白色加号，随智感握姿换边，带光感与阴影
      Row() {
        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(28)
          .fontColor([Color.White])
      }
      .width(56)
      .height(56)
      .borderRadius(28)
      .justifyContent(FlexAlign.Center)
      .backgroundColor($r('app.color.brand'))
      .shadow({ radius: 20, color: '#4D000000', offsetY: 6 })
      .margin({
        right: PixState.buttonPosition === 0 ? 20 : 0,
        left: PixState.buttonPosition === 2 ? 20 : 0,
        bottom: PixState.bottomRectHeight == 0 ? 24 : PixState.bottomRectHeight + 24
      })
      .visualEffect(new hdsEffect.HdsEffectBuilder()
        .pointLight({
          sourceType: hdsEffect.PointLightSourceType.BRIGHT, // 组件自身发光效果
          illuminatedType: hdsEffect.PointLightIlluminatedType.DEFAULT_FEATHERING_BORDER // 组件受光效果
        })
        .buildEffect())
      .onClick(() => {
        this.inputText = '';
        this.addCancelled = false;
        this.dialogController?.open()
      })
    }
    .width('100%')
    .height('100%')
  }

  /** 添加对话框输入区：# 前缀 + 输入框 */
  @Builder
  InputBuilder() {
    Row({ space: 8 }) {
      Text('#')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(PixState.currentThemeColor)
      TextInput({ placeholder: '输入关键词', text: this.inputText })
        .onChange((value: string) => {
          this.inputText = value
        })
        .layoutWeight(1)
        .fontSize(16)
        .borderRadius(16)
        .backgroundColor($r('sys.color.background_secondary'))
        .onSubmit(() => {
          this.confirmAdd()
        })
    }
    .width('100%')
  }

  /** 确认添加：对话框内等待译文获取（加载提示），一次入库带译文；取消按钮可中止 */
  private async confirmAdd(): Promise<void> {
    if (this.isAdding) {
      return;
    }
    const name = this.inputText.trim().replace(/^#+/, '').trim();
    if (name.length === 0) {
      toastUtil.showToast({ message: '请输入关键词' });
      return;
    }
    this.isAdding = true;
    // 每次添加重置取消标记；序号防上一次被取消的请求串扰本次
    this.addCancelled = false;
    const attempt = ++this.addSeq;
    try {
      const timeout = new Promise<string>((resolve: (value: string) => void) => {
        setTimeout(() => resolve(''), 5000);
      });
      const translated = await Promise.race([tagCollectionVM.tryFetchTranslation(name), timeout]);
      if (this.addCancelled || this.addSeq !== attempt) {
        return;
      }
      if (this.type === TAG_TYPE_FAVORITE) {
        await tagCollectionVM.addFavorite(name, translated);
      } else {
        await tagCollectionVM.addBlocked(name, translated);
      }
      this.inputText = '';
      this.dialogController?.close();
    } finally {
      this.isAdding = false;
    }
  }

  /** 滑动删除按钮 */
  @Builder
  DeleteSwipeButton(name: string) {
    SymbolGlyph($r('sys.symbol.ohos_trash_circle'))
      .fontSize(22)
      .fontColor([Color.Red])
      .margin({ right: 12, left: 10 })
      .onClick(() => {
        if (this.type === TAG_TYPE_FAVORITE) {
          tagCollectionVM.removeFavorite(name);
        } else {
          tagCollectionVM.removeBlocked(name);
        }
      })
  }
}

import { curves, SegmentButtonV2Items, TabSegmentButtonV2 } from '@kit.ArkUI';
import { UserListView } from '../components/UsersListView';
import { WaterFlowView } from '../components/WaterFlowView';
import { SuggestionItem } from '../common/entity/SearchSuggestion';
import { PixState } from '../entryability/AppState';
import { toastUtil } from '../common/utils/ToastUtils';
import { searchVM } from '../viewmodel/SearchViewModel';
import { NaviContainer } from '../components/NaviContainer';
import { PixivIllust, PixivNovel, SearchSort, SearchTarget, SearchR18Mode } from '../services/PixivTypes';
import { appSettings } from '../common/entity/SettingsModel';
import { NovelListView } from '../components/NovelListView';
import UIConstants from '../common/constants/UIConstants';


@Builder
export function SearchingPageBuilder() {
  SearchingPage()
}


@ComponentV2
export default struct SearchingPage {


  @Local searchTypeSelectedIndex: number = 0;
  // 搜索框是否处于焦点状态：建议面板仅在真实输入时显示，
  // 过滤掉组件带初始值创建时程序赋值触发的 onChange
  @Local searchInputFocused: boolean = false;
  // 筛选面板显示状态与草稿（确认后才写入 searchVM 并重新搜索）
  @Local showFilterSheet: boolean = false;
  @Local draftSort: SearchSort = 'popular_desc';
  @Local draftTarget: SearchTarget = 'partial_match_for_tags';
  @Local draftMinBookmark: number = 0;
  @Local draftR18: SearchR18Mode = 'none';

  private readonly SORT_OPTIONS: SearchSort[] = ['popular_desc', 'date_desc', 'date_asc'];
  private readonly TARGET_OPTIONS: SearchTarget[] =
    ['exact_match_for_tags', 'partial_match_for_tags', 'title_and_caption'];
  private readonly BOOKMARK_OPTIONS: number[] = [0, 100, 300, 500, 1000, 3000, 5000, 10000];
  private readonly R18_OPTIONS: SearchR18Mode[] = ['none', 'only', 'exclude'];

  private sortLabel(v: SearchSort): Resource {
    if (v === 'popular_desc') return $r('app.string.sort_popular');
    if (v === 'date_desc') return $r('app.string.sort_newest');
    return $r('app.string.sort_oldest');
  }
  private targetLabel(v: SearchTarget): Resource {
    if (v === 'partial_match_for_tags') return $r('app.string.match_partial');
    if (v === 'exact_match_for_tags') return $r('app.string.match_exact');
    return $r('app.string.match_title');
  }
  private bookmarkLabel(v: number): ResourceStr {
    if (v === 0) return $r('app.string.bookmark_unlimited');
    return `≥${v}`;
  }
  private r18Label(v: SearchR18Mode): Resource {
    if (v === 'only') return $r('app.string.r18_only');
    if (v === 'exclude') return $r('app.string.r18_exclude');
    return $r('app.string.r18_none');
  }

  /** 打开筛选面板时同步草稿 */
  private openFilterSheet() {
    this.draftSort = searchVM.filterSort;
    this.draftTarget = searchVM.filterTarget;
    this.draftMinBookmark = searchVM.filterMinBookmark;
    this.draftR18 = searchVM.filterR18;
    this.showFilterSheet = true;
  }

  /** 确认筛选 */
  private confirmFilter() {
    searchVM.filterSort = this.draftSort;
    searchVM.filterTarget = this.draftTarget;
    searchVM.filterMinBookmark = this.draftMinBookmark;
    searchVM.filterR18 = this.draftR18;
    this.showFilterSheet = false;
    searchVM.applyFilters();
  }

  private pageInfos: NavPathStack = new NavPathStack();
  private panOptionL: PanGestureOptions = new PanGestureOptions({ direction: PanDirection.Left })
  private panOptionR: PanGestureOptions = new PanGestureOptions({ direction: PanDirection.Right })

  private get searchTypeItems(): SegmentButtonV2Items {
    return appSettings.novel_mode
      ? new SegmentButtonV2Items([{ text: $r('app.string.novel') }, { text: $r('app.string.user_author') }])
      : new SegmentButtonV2Items([{ text: $r('app.string.illust') }, { text:$r('app.string.user_author') }]);
  }

  build() {
    NaviContainer({
      content: () => {
        this.Content()
      },
      transitionEffect: TransitionEffect.OPACITY,
      onBackPressed: () => {
        toastUtil.animateTo({
          curve: curves.interpolatingSpring(0, 1, 342, 38),
        }, () => {
          this.pageInfos.pop(false)
        })
        searchVM.keyword = ''
        return true;
      },
      onReady: (ctx) => {
        this.pageInfos = ctx.pathStack;
        // 带关键词进入（点击标签/历史记录/推荐标签）时直接发起搜索，进入页面即加载结果
        if (searchVM.keyword) {
          searchVM.doSearch(true);
        }
      },
      onNaviDisAppear: () => {
        // 离开页面时清理建议面板状态，避免残留影响下次进入
        searchVM.showSuggestions = false;
        searchVM.suggestions = [];
      }
    })
  }

  @Builder
  Content() {
    Column() {
      // 搜索栏
      Row({space: 5}) {
        // 返回图标
        Button({ type: ButtonType.Circle, stateEffect: false }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontColor([$r('sys.color.font_primary')])
            .fontSize(29)
        }
        .transition(TransitionEffect.asymmetric(
          TransitionEffect.OPACITY
            .animation({ duration: 200, delay: 150, curve: curves.cubicBezierCurve(0.33, 0, 0.67, 1) }),
          TransitionEffect.OPACITY
            .animation({ duration: 200, curve: curves.cubicBezierCurve(0.33, 0, 0.67, 1) })
        ))
        .backgroundColor($r('sys.color.button_background_color_transparent'))
        .width(40).height(40)
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Up) {
            this.getUIContext().animateTo({
              curve: curves.interpolatingSpring(0, 1, 342, 38)
            }, () => {
              this.pageInfos.pop(false)
              searchVM.keyword = ''
            })
          }
        })
        Search({ value: searchVM.keyword!!, placeholder: $r('app.string.search_placeholder_2') })
          .transition(TransitionEffect.opacity(0.99))
          .geometryTransition('SEARCH_ID')
          // 已携带关键词进入（如点击标签/历史记录）时不聚焦弹键盘，直接展示搜索结果
          .defaultFocus(!searchVM.keyword).height(40)
          .focusOnTouch(true)
          .onFocus(() => {
            this.searchInputFocused = true
          })
          .onBlur(() => {
            this.searchInputFocused = false
          })
          .onSubmit(() => {
            searchVM.handleSearchInput(searchVM.keyword, searchVM.searchType, true)
          })
          .layoutWeight(1)
          .id('SEARCH_ID')
          .onChange((value) => {
            // 仅响应聚焦状态下的真实输入，忽略组件初始化赋值触发的 onChange
            if (this.searchInputFocused) {
              searchVM.updateSuggestions(value)
            }
          })
        // 筛选入口（画师搜索不支持筛选，隐藏）
        if (searchVM.searchType !== 'user') {
          if (searchVM.isFilterActive) {
            Badge({
              value: '',
              position: BadgePosition.RightTop,
              style: { badgeSize: 8, badgeColor: $r('sys.color.warning') }
            }) {
              this.FilterButton()
            }
          } else {
            this.FilterButton()
          }
        }
      }
      .width('100%').height(56)
      .padding(({
        left: PixState.PageMarginValue,
        right: PixState.PageMarginValue
      }))
      // 建议列表（仅在搜索框聚焦输入时显示，避免覆盖搜索结果）
      if (searchVM.showSuggestions && this.searchInputFocused && searchVM.suggestions.length > 0) {
        Column() {
          List({ space: 1 }) {
            ForEach(searchVM.suggestions, (item: SuggestionItem) => {
              ListItem() {
                Row() {
                  Text(item.text)
                    .fontSize(14)
                    .margin({ left: 8 })
                }
                .width('100%')
                .padding({
                  left: PixState.PageMarginValue,
                  right: PixState.PageMarginValue,
                  top: 10, bottom: 10
                })
              }
              .onClick(() => {
                let type: 'illust' | 'novel' | 'user' = 'illust'; // 默认插画
                if (item.type === 'novel_jump') {
                  type = 'novel';
                } else if (item.type === 'user_jump') {
                  type = 'user';
                } else if (item.type === 'keyword_search') {
                  // 如果是普通关键词搜索，根据当前全局模式决定搜什么
                  type = appSettings.novel_mode ? 'novel' : 'illust';
                }
                searchVM.handleSearchInput(item.value, type, true);
              })
            }, (item: SuggestionItem) => `${item.type}_${item.value}`)
          }
          .borderRadius(UIConstants.RADIUS_ITEM)
          .backgroundColor($r('app.color.card_bg'))
          .border({ width: 0.5, color: $r('sys.color.comp_divider') })
          .shadow({ radius: 16, color: '#14000000', offsetX: 0, offsetY: 4 })
        }
        .width('100%')
        .padding(({
          left: PixState.PageMarginValue,
          right: PixState.PageMarginValue
        }))
      } else {
        // 结果类型栏
        Row() {
          TabSegmentButtonV2({
            items: this.searchTypeItems,
            enableStateAnimation: true,
            selectedIndex: this.searchTypeSelectedIndex!!,
            onItemClicked: (tab) => {
              if (tab == 0) {
                searchVM.searchType = appSettings.novel_mode ? 'novel' : 'illust'
              } else {
                searchVM.searchType = 'user'
              }
              searchVM.doSearch(false)
            }
          })
        }
        .transition(TransitionEffect.asymmetric(
          TransitionEffect.OPACITY
            .combine(TransitionEffect.translate({ y: 100 })),
          TransitionEffect.OPACITY.animation({ duration: 0 })
        ))
        .margin(({
          bottom: 10,
          left: PixState.PageMarginValue,
          right: PixState.PageMarginValue
        }))

        if (this.searchTypeSelectedIndex == 0) {
          if (searchVM.searchType === 'novel') {
            // 小说
            NovelListView({
              contentEndOffset: (PixState.TabBarVertical ? 125 : 160) + PixState.bottomRectHeight,
              novelList: searchVM.resultNovels,
              onItemClick: (novel: PixivNovel) => {
                searchVM.handleNovelClick(novel)
              },
              onReachEnd: () => {
                searchVM.loadMoreSearchResult()
              }
            })
              .transition(TransitionEffect.asymmetric(
                TransitionEffect.OPACITY
                  .combine(TransitionEffect.translate({ y: 100 })),
                TransitionEffect.OPACITY.animation({ duration: 0 })
              ))
          } else {
            // 插画
            WaterFlowView({
              contentEndOffset: (PixState.TabBarVertical ? 125 : 160) + PixState.bottomRectHeight,
              illustList: searchVM.resultIllusts,
              onCardClick: (illust) => {
                searchVM.handleIllustClick(illust)
              },
              onReachEnd: () => {
                // 只有非测试环境且当前不处于加载中时、存在下一页数据会触发数据更新
                if (!PixState.isTest) {
                  searchVM.loadMoreSearchResult()
                }
              }
            })
              .transition(TransitionEffect.asymmetric(
                TransitionEffect.OPACITY
                  .combine(TransitionEffect.translate({ y: 100 })),
                TransitionEffect.OPACITY.animation({ duration: 0 })
              ))
          }
        } else {
          // 画师
          UserListView({
            userPres: searchVM.resultUsers,
            contentEndOffset: (PixState.TabBarVertical ? 125 : 160) + PixState.bottomRectHeight,
            onButtonClick: (result: boolean, err?: string) => {
            },
            onImageClick: (illust: PixivIllust) => {
              searchVM.handleIllustClick(illust)
            },
            onReachEnd: () => {
              searchVM.loadMoreSearchResult()
            }
          })
            .transition(TransitionEffect.asymmetric(
              TransitionEffect.OPACITY
                .combine(TransitionEffect.translate({ y: 100 })),
              TransitionEffect.OPACITY.animation({ duration: 0 })
            ))
        }
      }
    }
    .backgroundColor($r('sys.color.background_primary'))
    .size({ width: '100%', height: '100%' })
    .padding({ top: PixState.topRectHeight })
    .bindSheet($$this.showFilterSheet, this.FilterSheetBuilder(), {
      height: 480,
      dragBar: true,
      showClose: false
    })
    // 左滑手势
    .gesture(
      PanGesture(this.panOptionL)
        .onActionStart((event: GestureEvent) => {
          if (event) {
            toastUtil.animateTo({
              duration: 300,
              curve: Curve.EaseOut,
              playMode: PlayMode.Normal,
            }, () => {
              this.searchTypeSelectedIndex = 1
              searchVM.searchType = 'user'
              searchVM.doSearch(false)
            })
          }
        }),
    )
    // 右滑滑手势
    .gesture(
      PanGesture(this.panOptionR)
        .onActionStart((event: GestureEvent) => {
          if (event) {
            toastUtil.animateTo({
              duration: 300,
              curve: Curve.EaseOut,
              playMode: PlayMode.Normal,
            }, () => {
              this.searchTypeSelectedIndex = 0
              searchVM.searchType = appSettings.novel_mode ? 'novel' : 'illust'
              searchVM.doSearch(false)
            })
          }
        }),
    )
  }

  @Builder
  FilterButton() {
    Button({ type: ButtonType.Circle, stateEffect: false }) {
      SymbolGlyph($r('sys.symbol.line_3_horizontal_circle'))
        .fontColor([$r('sys.color.font_primary')])
        .fontSize(24)
    }
    .backgroundColor($r('sys.color.button_background_color_transparent'))
    .width(40).height(40)
    .onClick(() => this.openFilterSheet())
  }

  @Builder
  FilterSheetBuilder() {
    Column() {
      // 标题
      Row() {
        Text($r('app.string.search_filter'))
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
      }
      .width('100%')
      .margin({ top: 8, bottom: 12 })

      Scroll() {
        Column({ space: 14 }) {
          // 排序方式
          Column() {
            Text($r('app.string.filter_sort'))
              .fontSize(14)
              .fontColor($r('sys.color.font_secondary'))
              .margin({ bottom: 6 })
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.SORT_OPTIONS, (v: SearchSort) => {
                FilterChip({
                  label: this.sortLabel(v),
                  selected: this.draftSort === v,
                  onTap: () => { this.draftSort = v }
                })
              }, (v: SearchSort) => v)
            }
          }
          .alignItems(HorizontalAlign.Start)

          // 匹配方式
          Column() {
            Text($r('app.string.filter_match_mode'))
              .fontSize(14)
              .fontColor($r('sys.color.font_secondary'))
              .margin({ bottom: 6 })
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.TARGET_OPTIONS, (v: SearchTarget) => {
                FilterChip({
                  label: this.targetLabel(v),
                  selected: this.draftTarget === v,
                  onTap: () => { this.draftTarget = v }
                })
              }, (v: SearchTarget) => v)
            }
          }
          .alignItems(HorizontalAlign.Start)

          // 收藏数筛选
          Column() {
            Text($r('app.string.filter_bookmark'))
              .fontSize(14)
              .fontColor($r('sys.color.font_secondary'))
              .margin({ bottom: 6 })
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.BOOKMARK_OPTIONS, (v: number) => {
                FilterChip({
                  label: this.bookmarkLabel(v),
                  selected: this.draftMinBookmark === v,
                  onTap: () => { this.draftMinBookmark = v }
                })
              }, (v: number) => `bm_${v}`)
            }
          }
          .alignItems(HorizontalAlign.Start)

          // R-18 筛选
          Column() {
            Text($r('app.string.filter_r18'))
              .fontSize(14)
              .fontColor($r('sys.color.font_secondary'))
              .margin({ bottom: 6 })
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.R18_OPTIONS, (v: SearchR18Mode) => {
                FilterChip({
                  label: this.r18Label(v),
                  selected: this.draftR18 === v,
                  onTap: () => { this.draftR18 = v }
                })
              }, (v: SearchR18Mode) => v)
            }
          }
          .alignItems(HorizontalAlign.Start)
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .width('100%')

      // 底部按钮
      Row({ space: 12 }) {
        Button($r('app.string.filter_reset'))
          .layoutWeight(1)
          .backgroundColor($r('sys.color.comp_background_gray'))
          .fontColor($r('sys.color.font_primary'))
          .onClick(() => {
            this.draftSort = 'popular_desc';
            this.draftTarget = 'partial_match_for_tags';
            this.draftMinBookmark = 0;
            this.draftR18 = 'none';
          })
        Button($r('app.string.filter_confirm'))
          .layoutWeight(1)
          .onClick(() => this.confirmFilter())
      }
      .width('100%')
      .margin({ top: 12, bottom: 16 })
    }
    .width('100%')
    .height('100%')
    .padding({
      left: PixState.PageMarginValue,
      right: PixState.PageMarginValue
    })
  }

}

/** 筛选选项 Chip（独立组件，@Param 响应式刷新选中态） */
@ComponentV2
struct FilterChip {
  @Param label: ResourceStr = '';
  @Param selected: boolean = false;
  @Event onTap: () => void = () => {};

  build() {
    Text(this.label)
      .fontSize(14)
      .fontColor(this.selected ? $r('sys.color.brand') : $r('sys.color.font_primary'))
      .padding({ left: 14, right: 14, top: 8, bottom: 8 })
      .borderRadius(UIConstants.RADIUS_ITEM)
      .backgroundColor(this.selected ? $r('sys.color.comp_background_tertiary') : $r('sys.color.comp_background_gray'))
      .border({
        width: 1,
        color: this.selected ? $r('sys.color.brand') : $r('sys.color.comp_divider')
      })
      .margin({ right: 8, bottom: 8 })
      .onClick(() => this.onTap())
  }
}

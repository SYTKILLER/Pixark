import { PixivImageComponent } from "../components/PixivImage";
import { PixState } from "../entryability/AppState";
import { GridColumnsTemplate } from "../common/utils/breakpoint/BreakPoint";
import { IllustDetailViewModel } from "../viewmodel/IllustDetailViewModel";
import { SnapShotUtils } from "../common/utils/SnapShotUtils";
import { PixivIllust, PixivImage, PixivTag } from "../services/PixivTypes";
import { LengthMetrics, curves } from "@kit.ArkUI";
import UIConstants from "../common/constants/UIConstants";
import { homeViewModel } from "../viewmodel/HomeViewModel";
import { DetailPageParams, IIllustSwiperProvider } from "../common/entity/DetailEntity";
import { UserItem } from "../components/UserItem";
import { PixivImageViewer } from "../components/ImageViewer";
import { NaviContainer } from "../components/NaviContainer";
import { appSettings } from "../common/entity/SettingsModel";
import { hdsEffect } from "@kit.UIDesignKit";
import { ColorUtils } from "../common/utils/ColorUtils";
import { LongTakeAnimationProperties } from "../common/utils/customtransition/LongTakeAnimationProperties";
import { CustomTransition } from "../common/utils/customtransition/CustomNavigationUtils";
import { CardUtil } from "../common/utils/CardUtil";
import { createLogger } from "../common/utils/Logger";
import { CommentPanel } from "./CommentPanel";
import { searchVM } from "../viewmodel/SearchViewModel";
import { toastUtil } from "../common/utils/ToastUtils";
import { tagCollectionVM } from "../viewmodel/TagCollectionVM";
import { EmptyStateView } from "../components/CommonWidgets";
import { SymbolGlyphModifier } from "@kit.ArkUI";

const logger = createLogger('IllustDetail')


@Builder
export function IllustDetailBuilder(name: string, param: Object) {
  IllustDetail()
}

// 外层：负责 Swiper 容器与转场动画
@ComponentV2
struct IllustDetail {

  @Local illustTitle: string = ''
  @Local showLargeImage: boolean = false
  @Local currentSwiperIndex: number = 0

  private pageStack: NavPathStack = new NavPathStack()
  private swiperProvider: IIllustSwiperProvider | undefined = undefined
  private initialId: number = 0
  private sharedId: string = ''
  private longTakeAnimationProperties: LongTakeAnimationProperties = new LongTakeAnimationProperties();

  build() {
    NaviContainer({
      title: this.illustTitle,
      content: () => { this.Content() },
      onReady: (ctx) => {
        this.pageStack = ctx.pathStack
        this.handleTransitionReady(ctx)
      },
      onBackPressed: () => {
        if (this.showLargeImage) {
          this.showLargeImage = false
          return true
        }
        return false
      },
      onNaviDisAppear: () => {
        homeViewModel.restoreIllustVisibility();
        SnapShotUtils.clear();
      }
    })
  }

  // 处理转场动画初始化
  private handleTransitionReady(ctx: NavDestinationContext) {
    const params = ctx?.pathInfo?.param as DetailPageParams;
    if (!params) return;

    this.initialId = params.id;
    this.swiperProvider = params.swiperProvider;

    const fromId = params.fromId as string;
    const pageId = ctx.navDestinationId;
    if (!pageId || !fromId) {
      this.longTakeAnimationProperties.setFinalStatus();
      return;
    }
    this.sharedId = CardUtil.getPostPageImageId(fromId) || fromId;

    this.longTakeAnimationProperties.init(fromId, () => {
      homeViewModel.restoreIllustVisibility();
    });

    CustomTransition.getInstance().registerNavParam(pageId, 2000, (proxy: NavigationTransitionProxy) => {
      this.longTakeAnimationProperties.doAnimation(proxy);
    });
  }

  @Builder Content() {
    if (this.swiperProvider && appSettings.swiper_browsing) {
      // === Swiper 模式 ===
      Swiper() {
        Repeat<number>(this.swiperProvider.illustIds)
          .virtualScroll({ totalCount: this.swiperProvider.illustIds.length, reusable: false }) // 禁用复用，触发加载
          .key((id: number) => id.toString())
          .each((ri: RepeatItem<number>) => {
            IllustDetailContent({
              illustId: ri.item,
              sharedId: ri.item === this.initialId ? this.sharedId : '',
              pageStack: this.pageStack,
              showLargeImage: this.showLargeImage,
              onImageLarge: (show) => { this.showLargeImage = show },
              onTitle: (title) => { this.illustTitle = title }
            })
          })
      }
      .index(this.swiperProvider.illustIds.indexOf(this.initialId) || 0)
      .indicator(false)
      .loop(false)
      .cachedCount(0, false)
      .onChange((index: number) => {
        const total = this.swiperProvider?.illustIds.length || 0;
        // logger.debug(`[Swiper Log] >>> 滑动变化! 当前Index: ${index}, 列表总数:${total}, 当前ID: ${this.swiperProvider?.illustIds[index]}`);
        this.currentSwiperIndex = index;
        this.tryLoadMore(index);
      })
      .width('100%')
      .height('100%')
    } else {
      // === 单页模式 ===
      IllustDetailContent({
        illustId: this.initialId,
        sharedId: this.sharedId,
        pageStack: this.pageStack,
        showLargeImage: this.showLargeImage,
        onImageLarge: (show) => { this.showLargeImage = show },
        onTitle: (title) => { this.illustTitle = title }
      })
        .width('100%')
        .height('100%')
    }
  }

  // 触底预加载逻辑
  private tryLoadMore(index: number) {
    if (!this.swiperProvider || !this.swiperProvider.hasMore || this.swiperProvider.isLoading) return;
    const total = this.swiperProvider.illustIds.length;
    // logger.debug(`[Swiper Log] >>> 预加载检查: index=${index}, total=${total}, hasMore=${this.swiperProvider.hasMore}`);
    // 滑到倒数第 2 张时，触发预加载
    if (index >= total - 2) {
      this.swiperProvider.loadMore();
    }
  }

}

// 内层：负责单张插画的数据与 UI
@ComponentV2
struct IllustDetailContent {

  @Param illustId: number = 0
  @Param sharedId: string = ''
  @Param showLargeImage: boolean = false
  @Param pageStack: NavPathStack = new NavPathStack()

  @Local currentImageIndex: number = 0
  @Local showCommentPanel: boolean = false
  @Local iDV: IllustDetailViewModel = new IllustDetailViewModel()
  // 标签长按菜单（isShow 由各胶囊按 menuTagName 匹配，避免多个菜单同时弹出）
  @Local showTagMenu: boolean = false
  @Local menuTagName: string = ''

  @Event onImageLarge: (show: boolean) => void
  @Event onTitle: (title: string) => void

  async aboutToAppear(): Promise<void> {
    // 根据 ID 加载详情
    this.iDV.loadIllustDetail(this.illustId);
    this.iDV.loadRelated(this.illustId);
  }

  /** 当前作品命中的屏蔽词 */
  private blockedTagNames(): string[] {
    return tagCollectionVM.blockedNamesIn(this.iDV.detailData?.tags);
  }

  /** 标签长按菜单：收藏 / 屏蔽 */
  @Builder
  TagMenu(tag: PixivTag) {
    Menu() {
      MenuItem({
        content: tagCollectionVM.isFavorite(tag.name) ? '取消收藏' : '收藏关键词',
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.star_circle')).fontColor(['#FF9500'])
      })
        .onClick(() => {
          // 选中即收起：必须先关菜单再改数据，否则数据刷新引发菜单收起-展开-收起的闪烁
          this.showTagMenu = false;
          if (tagCollectionVM.isFavorite(tag.name)) {
            tagCollectionVM.removeFavorite(tag.name);
          } else {
            tagCollectionVM.addFavorite(tag.name, tag.translated_name || '');
          }
        })
      MenuItem({
        content: tagCollectionVM.isBlocked(tag.name) ? '取消屏蔽' : '屏蔽关键词',
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.exclamationmark_shield_fill'))
          .fontColor([$r('sys.color.font_secondary')])
      })
        .onClick(() => {
          this.showTagMenu = false;
          if (tagCollectionVM.isBlocked(tag.name)) {
            tagCollectionVM.removeBlocked(tag.name);
          } else {
            tagCollectionVM.addBlocked(tag.name, tag.translated_name || '');
          }
        })
    }
  }

  build() {
    // 屏蔽兜底：从列表过滤覆盖不到的入口（评论、用户页等）直接打开时，整页占位
    if (this.iDV.detailData && tagCollectionVM.hasBlockedTags(this.iDV.detailData.tags)) {
      Column() {
        EmptyStateView({
          icon: $r('sys.symbol.exclamationmark_shield_fill'),
          message: `该作品包含已屏蔽的关键词：${this.blockedTagNames().join('、')}`,
          actionText: '取消屏蔽',
          onAction: () => {
            tagCollectionVM.removeBlockedNames(this.blockedTagNames());
          }
        })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else {
      Stack({ alignContent: 8 - PixState.buttonPosition }) {
      Row() {
        List({ space: 10 }) {
          ForEach(this.iDV.imageList, (illust: PixivImage, index: number) => {
            ListItem() {
              PixivImageComponent({
                imageUrl: this.iDV.detailImageUrls[index] || illust.medium,
                imageObjectFit: ImageFit.Auto,
                imageBorder: { radius: 0 },
              })
                .id(index === 0 ? this.sharedId : illust.medium)
            }
            .onClick(() => {
              this.currentImageIndex = index
              this.onImageLarge(true)
            })
          })

          if (PixState.widthBp < 2 && this.iDV.detailData) {
            this.IntroContent()
          }
        }
        .height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .contentEndOffset(PixState.bottomRectHeight == 0 ? PixState.PageMarginValue : PixState.bottomRectHeight)
        .padding(({ left: PixState.PageMarginValue, right: PixState.PageMarginValue }))
        .width(PixState.widthBp < 2 ? '100%' : PixState.windowWidth / 2)

        if (PixState.widthBp >= 2 && this.iDV.detailData) {
          List({ space: 10 }) {
            this.IntroContent()
          }
          .height('100%')
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .contentEndOffset(PixState.bottomRectHeight == 0 ? PixState.PageMarginValue : PixState.bottomRectHeight)
          .contentStartOffset(60 + PixState.topRectHeight)
          .width(PixState.windowWidth / 2)
          .padding(({ left: PixState.PageMarginValue, right: PixState.PageMarginValue }))
        }
      }
      .justifyContent(FlexAlign.SpaceBetween)
      .bindSheet(this.showCommentPanel!!, this.CommentPanel(), {
        height: '70%',
        dragBar: true,
        onWillAppear: () => {},
        onWillDisappear: () => {
        }
      })
      this.FloatingControlButton()

      if (this.showLargeImage) {
        PixivImageViewer({
          imageUrls: this.iDV.imageList,
          startIndex: this.currentImageIndex,
          bookmarked: this.iDV.isBookmarked,
          onClose: () => {
            this.onImageLarge(false)
          },
          onDownload: (index) => {
            this.iDV.downloadCurrentImage(index);
            if (appSettings.collecting_when_download) {
              this.iDV.bookmarkOrCancel(true)
            }
          },
          onShare: (url, index) => {},
          onBookmark: (index) => {
            this.iDV.bookmarkOrCancel(!this.iDV.isBookmarked)
          }
        })
          .transition(TransitionEffect.scale({ x: 0.92, y: 0.92 })
            .combine(TransitionEffect.OPACITY)
            .animation({ duration: 280, curve: curves.springMotion(0.42, 0.8) }))
      }
    }
  }
  }

  /**
   * 悬浮控制 tab：下载 + 收藏（竖式双按钮，保留智感握姿光效）
   */
  @Builder
  FloatingControlButton() {
    Column({ space: 4 }) {
      // 下载按钮
      Row() {
        SymbolGlyph($r('sys.symbol.circle_and_arrow_down'))
          .fontSize(24).fontColor([Color.White])
      }
      .width(56)
      .height(52)
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        this.iDV.downloadAllImages();
        if (appSettings.collecting_when_download) {
          this.iDV.bookmarkOrCancel(true)
        }
      })
      // 分隔线
      Divider()
        .strokeWidth(0.5)
        .width(28)
        .color('#33FFFFFF')
      // 收藏按钮
      Row() {
        SymbolGlyph(this.iDV.isBookmarked ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
          .fontSize(27).fontColor([this.iDV.isBookmarked ? PixState.currentThemeColor : Color.White])
      }
      .width(56)
      .height(52)
      .justifyContent(FlexAlign.Center)
      .borderRadius(26)
      .backgroundColor(this.iDV.isBookmarked ? ColorUtils.getColorWithAlphaString(PixState.currentThemeColor, 30) : Color.Transparent)
      .onClick(() => {
        this.iDV.bookmarkOrCancel()
      })
    }
    .alignItems(HorizontalAlign.Center)
    .padding({ top: 4, bottom: 4 })
    .width(60)
    .borderRadius(30)
    .backgroundColor($r('sys.color.ohos_id_color_bottom_tab_icon_auxcolor_off02'))
    .offset({ x: PixState.buttonPosition === 0 ? -PixState.PageMarginValue : PixState.PageMarginValue, y: -20 })
    .visualEffect(new hdsEffect.HdsEffectBuilder()
      .pointLight({
        sourceType: this.iDV.isBookmarked ?
          hdsEffect.PointLightSourceType.BRIGHT : hdsEffect.PointLightSourceType.NONE, // 组件自身发光效果
        illuminatedType: hdsEffect.PointLightIlluminatedType.DEFAULT_FEATHERING_BORDER // 组件受光效果
      })
      .buildEffect())
  }

  @Builder
  IntroContent() {
    // 详情信息卡片
    ListItem() {
      this.InfoCard()
    }
    // 评论入口
    ListItem() {
      this.Comment()
    }
    // 相关推荐
    ListItem() {
      this.RelatedSection()
    }
  }

  /** 详情信息卡片 */
  @Builder
  InfoCard() {
    Column({ space: 12 }) {
      // 标题
      Text(this.iDV.detailData!.title)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .onVisibleAreaChange([0.0, 1.0], (isExpanding: boolean, currentRatio: number) => {
          console.debug(`Test Text isExpanding: ${isExpanding}, currentRatio: ${currentRatio}`)
          if (isExpanding && currentRatio >= 1.0) {
            this.onTitle(this.iDV.detailData!.title)
          }
          if (!isExpanding && currentRatio <= 0.0) {
            console.debug('Test Text is completely invisible.')
          }
        })
      // 统计数据行：观看人数 + 喜欢数 + 时间
      Row({ space: 16 }) {
        Text($r('app.string.browse', this.iDV.detailData!.total_view))
          .fontSize(12)
          .fontColor($r('sys.color.font_tertiary'))
        Text($r('app.string.num_collection', this.iDV.detailData!.total_bookmarks))
          .fontSize(12)
          .fontColor($r('sys.color.font_tertiary'))
        // 格式化时间
        Text(this.iDV.formatDate(this.iDV.detailData!.create_date))
          .fontSize(12)
          .fontColor($r('sys.color.font_tertiary'))
      }
      .width('100%')
      // 元数据行：ID + 分辨率
      Row({ space: 16 }) {
        Text(`插画ID: ${this.iDV.detailData!.id}`)
          .fontSize(12)
          .fontColor($r('sys.color.font_fourth'))
        Text(`${this.iDV.detailData!.width} x ${this.iDV.detailData!.height}`)
          .fontSize(12)
          .fontColor($r('sys.color.font_fourth'))
      }
      .width('100%')
      // 分割线
      Divider().color($r('sys.color.ohos_id_color_text_field_sub_bg'))

      // 作者行：头像 + 名称 + 关注按钮
      UserItem({
        user: this.iDV.detailData?.user,
        isFollow: this.iDV.isFollow,
        onButtonClick: (result: boolean, err?: string) => {
          this.iDV.followOrCancel(result, err)
        }
      })

      // 标签
      Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
        ForEach(this.iDV.detailData!.tags, (tag: PixivTag) => {
          Row({ space: 4 }) {
            if (tagCollectionVM.isFavorite(tag.name)) {
              SymbolGlyph($r('sys.symbol.star_circle'))
                .fontSize(12)
                .fontColor(['#FF9500'])
            }
            // Shaft 式：原文为主行，官方译文为次行小字
            Column({ space: 2 }) {
              Text(`#${tag.name}`)
                .fontSize(13)
                .fontColor(tagCollectionVM.isFavorite(tag.name) ? '#FF9500' : PixState.currentThemeColor)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .maxLines(1)
              if (tag.translated_name && tag.translated_name !== tag.name) {
                Text(tag.translated_name)
                  .fontSize(10)
                  .fontColor(tagCollectionVM.isFavorite(tag.name) ? '#B3FF9500' : $r('sys.color.font_tertiary'))
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .maxLines(1)
              }
            }
            .alignItems(HorizontalAlign.Start)
            .constraintSize({ maxWidth: 300 })
          }
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .backgroundColor(tagCollectionVM.isFavorite(tag.name) ? '#26FF9500' : $r('app.color.brand_weak'))
          .borderRadius(UIConstants.RADIUS_PILL)
          .constraintSize({ maxWidth: '100%' })
          .onClick(() => {
            // 点击标签直接以该标签为关键词搜索（用原始标签名保证 exact_match_for_tags 精确匹配），
            // 搜索由搜索结果页 onReady 时发起
            searchVM.keyword = tag.name;
            searchVM.searchType = 'illust';
            toastUtil.animateTo({
              curve: curves.interpolatingSpring(0, 1, 342, 38)
            }, () => {
              this.pageStack.pushPath({ name: 'searching_page' }, false);
            })
          })
          .gesture(
            LongPressGesture({ repeat: false, duration: 400 })
              .onAction(() => {
                this.menuTagName = tag.name;
                this.showTagMenu = true;
              })
          )
          .bindMenu(this.showTagMenu && this.menuTagName === tag.name, this.TagMenu(tag), {
            placement: Placement.Bottom,
            backgroundBlurStyle: BlurStyle.Thin,
            onDisappear: () => {
              this.showTagMenu = false
            }
          })
        })
      }
      .width('100%')
    }
    .width('100%')
    .borderRadius(UIConstants.RADIUS_ITEM)
  }

  /** 评论入口 */
  @Builder
  Comment() {
    Row() {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.ellipsis_message_1'))
          .fontSize(19)
          .fontColor([PixState.currentThemeColor])
        Text('查看评论')
          .fontSize(16)
          .fontColor($r('sys.color.font_primary'))
      }
      Blank()
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(19)
        .fontColor([$r('sys.color.font_tertiary')])
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(UIConstants.RADIUS_ITEM)
    .onClick(() => {
      this.showCommentPanel = true
    })
  }

  @Builder
  CommentPanel() {
    CommentPanel({
      targetId: this.illustId,
      onClose: () => {
        this.showCommentPanel = false
      }
    })
  }

  /** 相关推荐 */
  @Builder
  RelatedSection() {
    Column({ space: 12 }) {
      // 标题
      Text($r('app.string.related_recommendations'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .padding({ left: 4 })

      // 网格布局
      Grid() {
        ForEach(this.iDV.relatedIllusts, (item: PixivIllust) => {
          GridItem() {
            PixivImageComponent({
              imageUrl: item.image_urls.square_medium,
              imageAspectRatio: 1,
              imageBorder: { radius: UIConstants.RADIUS_ITEM }
            })
          }
          .onClick(() => {
            // 点击推荐插画
            const index = this.iDV.relatedIllusts.findIndex(i => i.id === item.id);
            const params: DetailPageParams = {
              id: item.id,
              illust: item,
              swiperProvider: this.iDV,
              swiperIndex: index >= 0 ? index : 0
            }
            this.pageStack.pushPathByName('illust_detail', params, true);
          })
        })
      }
      .columnsTemplate(GridColumnsTemplate(PixState.widthBp))
      .columnsGap(3)
      .rowsGap(3)
      .width('100%')

      // 底部的加载更多按钮 / 状态提示
      if (this.iDV.hasMore) {
        Row() {
          if (this.iDV.isLoading) {
            LoadingProgress().width(20).height(20)
            Text() {
              Span($r('app.string.loading_recommendations'))
              Span('...')
            }.fontSize(14).margin({ left: 8 })
          } else {
            Text($r('app.string.load_more_recommendations')).fontSize(14).fontColor(PixState.currentThemeColor)
          }
        }
        .width('100%')
        .height(48)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          if (!this.iDV.isLoading) {
            this.iDV.loadMore();
          }
        })
      } else if (this.iDV.relatedIllusts.length > 0) {
        Text($r('app.string.no_further_recommendations'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .fontSize(13)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .margin({ top: 8, bottom: 8 })
      }
    }
    .width('100%')
    .borderRadius(12)
  }

}


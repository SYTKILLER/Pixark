import { PixState, _PixState } from "../entryability/AppState"
import { PixivIllust } from "../services/PixivTypes"
import { WaterFlowColumnsTemplate } from "../common/utils/breakpoint/BreakPoint"
import { CardUtil } from "../common/utils/CardUtil"
import { createLogger } from "../common/utils/Logger"
import { PixivImageComponent } from "./PixivImage"
import { appSettings } from "../common/entity/SettingsModel"
import { bookmarkState } from "../common/entity/BookmarkState"
import { ImageUtils } from '../common/utils/ImageUtils';
import { FunctionConstants } from "../common/constants/FunctionConstants"
import { EmptyStateView } from "./CommonWidgets"

const logger = createLogger('WaterFlowView')


/**
 * 瀑布流视图
 */
@ComponentV2
export struct WaterFlowView {

  @Param contentEndOffset: number = 0
  @Param illustList: PixivIllust[] = []
  @Param nestedScroll: NestedScrollOptions | undefined = undefined
  /** 外部滚动器（用于标题栏联动等场景） */
  @Param scroller: Scroller | undefined = undefined
  /** 空态文案（传入后列表为空时展示空态视图） */
  @Param emptyText: ResourceStr | undefined = undefined
  @Param emptyIcon: Resource = $r('sys.symbol.picture_slash')
  /** 是否在卡片上显示收藏角标（收藏页内已全为收藏，可关闭） */
  @Param showBookmarkBadge: boolean = true

  @Event onCardClick: (illust: PixivIllust) => void
  @Event onReachEnd: () => void

  build() {
    Stack() {
      WaterFlow() {
        ForEach(this.illustList, (illust: PixivIllust) => {
          FlowItem() {
            PixivImageComponent({
              showHTips: showHTips(illust),
              showAISign: isAIIllust(illust),
              imageUrl: ImageUtils.getImageUrlByQuality(illust.image_urls, appSettings.image_preview_quality),
              imageObjectFit: ImageFit.Auto,
              imageBorder: { radius: 16 },
            })
              .id(CardUtil.getFlowItemIdByIndex(illust.id))
              .overlay(this.BookmarkBadge(illust), { align: Alignment.BottomEnd })
            // .visibility(homeViewModel.hiddenIllustId === illust.id ? Visibility.None : Visibility.Visible)
          }
          .clip(true)
          .stateStyles({
            pressed: { .opacity(0.85) },
            normal: { .opacity(1) }
          })
          .onClick(() => {
            this.onCardClick(illust)
          })
        }, (iilust: PixivIllust) => `${iilust.id}${iilust.title}`)
      }
      .rowsGap(5)
      .columnsGap(10)
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .nestedScroll(this.nestedScroll)
      .margin({ left: PixState.PageMarginValue, right: PixState.PageMarginValue })
      .contentEndOffset(PixState.bottomRectHeight + this.contentEndOffset)
      .columnsTemplate(WaterFlowColumnsTemplate(PixState.widthBp)) // 瀑布流列数
      .onReachEnd(() => {
        logger.debug('滚动到瀑布流底部，开始加载更多');
        this.onReachEnd()
      })

      if (this.emptyText !== undefined && this.illustList.length === 0) {
        EmptyStateView({
          icon: this.emptyIcon,
          message: this.emptyText
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  /** 收藏角标：右下角红心，会话内收藏/取消后即时刷新 */
  @Builder
  BookmarkBadge(illust: PixivIllust) {
    if (this.showBookmarkBadge && bookmarkState.isBookmarked(illust)) {
      Row() {
        SymbolGlyph($r('sys.symbol.heart_fill'))
          .fontSize(14)
          .fontColor(['#FF3B30'])
      }
      .padding(5)
      .borderRadius(14)
      .backgroundColor('#40000000')
      .margin({ right: 6, bottom: 6 })
    }
  }

}

function showHTips(illust: PixivIllust): boolean {
  if (appSettings.show_H) return false
  if (!illust.tags || illust.tags.length === 0) return false;
  const aiTagNames = FunctionConstants.R18_TAG;
  return illust.tags.some(tag => aiTagNames.includes(tag.name))
}

/**
 * 判断插画是否为 AI 作品
 * @param illust 插画对象
 * @returns true 表示是 AI 作品
 */
export function isAIIllust(illust: PixivIllust): boolean {
  const aiType = (illust as PixivIllust).illust_ai_type;
  if (aiType === 2 || aiType === 3) {
    return true;
  }
  if (!illust.tags || illust.tags.length === 0) return false;
  const aiTagNames = FunctionConstants.AI_TAG;
  return illust.tags.some(tag => aiTagNames.includes(tag.name));
}

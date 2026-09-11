import { NaviContainer } from "../../components/NaviContainer"
import { animation } from "../../common/utils/AnimationUtil"
import { collectionVM } from "../../viewmodel/CollectionViewModel"
import { PixState } from "../../entryability/AppState"
import { SegmentButtonV2Items, TabSegmentButtonV2 } from "@kit.ArkUI"
import { WaterFlowView } from "../../components/WaterFlowView"
import { NovelListView } from "../../components/NovelListView"
import { PixivIllust, PixivNovel } from "../../services/PixivTypes"
import { appSettings } from "../../common/entity/SettingsModel"

@Builder
export function CollectionPageBuilder() {
  CollectionPage()
}


@ComponentV2
struct CollectionPage {

  // onReady 时才拿到真实导航栈，用 @Local 保证重新赋值能同步到筛选页子组件
  @Local pageStack: NavPathStack = new NavPathStack()
  private swiperController: SwiperController = new SwiperController()
  private filterTabItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: $r('app.string.all') },
    { text: $r('app.string.public') },
    { text: $r('app.string.private') },
  ]);

  aboutToAppear(): void {
    collectionVM.onReady();
  }

  aboutToDisappear(): void {
    collectionVM.onDisappear();
  }

  build() {
    NaviContainer({
      title: $r('app.string.collection'),
      content: () => { this.Content() },
      onReady: (ctx) => { this.pageStack = ctx.pathStack },
      onBackPressed: () => false
    })
  }

  @Builder Content() {
    Column({ space: 10 }) {
      // 筛选器区域
      Row() {
        TabSegmentButtonV2({
          items: this.filterTabItems,
          selectedIndex: collectionVM.filterIndex,
          enableStateAnimation: true,
          onItemClicked: (tab) => { this.onFilterClick(tab); }
        })
      }
      .padding({ left: PixState.PageMarginValue, right: PixState.PageMarginValue })
      .width('100%')

      // 左右滑动在 全部/公开/私密 间切换（同排行榜交互）
      Swiper(this.swiperController) {
        ForEach([0, 1, 2], (index: number) => {
          CollectionFilterPage({ index: index, pageStack: this.pageStack })
        }, (index: number) => `${index}_${appSettings.novel_mode ? 'n' : 'i'}`)
      }
      .index(collectionVM.filterIndex)
      .loop(false)
      .indicator(false)
      .cachedCount(2)
      .duration(280)
      .nestedScroll(SwiperNestedScrollMode.SELF_FIRST)
      .onChange((index: number) => {
        collectionVM.syncFilter(index);
      })
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Start)
  }

  // 筛选器点击：同步 Swiper 翻页
  private onFilterClick(index: number) {
    collectionVM.syncFilter(index);
    this.swiperController.changeIndex(index);
  }

}

/**
 * 单个筛选页（全部/公开/私密）。
 * 独立成组件以便在挂载时触发懒加载（首次进入、预载、插画/小说模式切换重建时均生效）
 */
@ComponentV2
struct CollectionFilterPage {

  @Param index: number = 0;
  @Param pageStack: NavPathStack = new NavPathStack()

  aboutToAppear(): void {
    collectionVM.ensurePageLoaded(this.index);
  }

  build() {
    if (appSettings.novel_mode) {
      Column() {
        this.NovelContent()
      }.transition(animation.modeSwitchTransition())
    } else {
      Column() {
        this.IllustContent()
      }.transition(animation.modeSwitchTransition())
    }
  }

  // 插画筛选页
  @Builder
  IllustContent() {
    Stack() {
      if (collectionVM.illustPage(this.index).isLoading && !collectionVM.illustPage(this.index).loaded) {
        LoadingProgress()
          .width(40)
          .height(40)
          .color(PixState.currentThemeColor)
      } else {
        Refresh({ refreshing: collectionVM.illustPage(this.index).isRefreshing }) {
          WaterFlowView({
            contentEndOffset: PixState.widthBp == 2 ? 56 : 16,
            illustList: collectionVM.illustPage(this.index).illusts,
            emptyText: $r('app.string.no_data'),
            showBookmarkBadge: false, // 收藏页内已全为收藏，不显示角标
            onCardClick: (illust: PixivIllust) => { collectionVM.handleIllustClick(illust, this.pageStack); },
            onReachEnd: () => { collectionVM.loadMore(); }
          })
        }
        .width('100%')
        .height('100%')
        .onRefreshing(async () => { await collectionVM.refreshPage(this.index) })
      }
    }
    .width('100%')
    .height('100%')
  }

  // 小说筛选页
  @Builder
  NovelContent() {
    Stack() {
      if (collectionVM.novelPage(this.index).isLoading && !collectionVM.novelPage(this.index).loaded) {
        LoadingProgress()
          .width(40)
          .height(40)
          .color(PixState.currentThemeColor)
      } else {
        Refresh({ refreshing: collectionVM.novelPage(this.index).isRefreshing }) {
          NovelListView({
            novelList: collectionVM.novelPage(this.index).novels,
            onItemClick: (novel: PixivNovel) => {
            },
            onReachEnd: () => { collectionVM.loadMore(); }
          })
        }
        .width('100%')
        .height('100%')
        .onRefreshing(async () => { await collectionVM.refreshPage(this.index) })
      }
    }
    .width('100%')
    .height('100%')
  }

}

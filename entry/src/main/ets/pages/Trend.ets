import { trendVM } from "../viewmodel/TrendViewModel";
import { animation } from "../common/utils/AnimationUtil";
import { PixState } from "../entryability/AppState";
import { LengthMetrics, SegmentButtonV2Items, TabSegmentButtonV2 } from '@kit.ArkUI';
import { WaterFlowView } from "../components/WaterFlowView";
import { PixivIllust, PixivNovel } from "../services/PixivTypes";
import { NovelListView } from "../components/NovelListView";
import { appSettings } from "../common/entity/SettingsModel";


@ComponentV2
export struct Trend {

  @Local skeletonOpacity: number = 1;
  private intervalId: number = -1;
  private swiperController: SwiperController = new SwiperController();

  private filterTabItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: $r('app.string.all') },
    { text: $r('app.string.public') },
    { text: $r('app.string.private') },
  ]);

  build() {
    Column() {
      if (trendVM.isInitialLoading) {
        this.TrendSkeleton()
      } else {
        this.TrendContent()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  TrendContent() {
    Column({ space: 10 }) {
      // 筛选器区域
      Row() {
        TabSegmentButtonV2({
          items: this.filterTabItems,
          selectedIndex: trendVM.filterIndex,
          enableStateAnimation: true,
          onItemClicked: (tab) => { this.onFilterClick(tab); }
        })
      }
      .padding({ left: PixState.PageMarginValue, right: PixState.PageMarginValue })
      .width('100%')

      // 左右滑动在 全部/公开/私密 间切换（同排行榜交互）
      Swiper(this.swiperController) {
        ForEach([0, 1, 2], (index: number) => {
          TrendFilterPage({ index: index })
        }, (index: number) => `${index}_${appSettings.novel_mode ? 'n' : 'i'}`)
      }
      .index(trendVM.filterIndex)
      .loop(false)
      .indicator(false)
      .cachedCount(2)
      .duration(280)
      .nestedScroll(SwiperNestedScrollMode.SELF_FIRST)
      .onChange((index: number) => {
        trendVM.syncFilter(index);
      })
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Start)
  }

  // 筛选器点击：同步 Swiper 翻页
  private onFilterClick(index: number) {
    trendVM.syncFilter(index);
    this.swiperController.changeIndex(index);
  }

  // 骨架屏
  @Builder
  TrendSkeleton() {
    Scroll() {
      Column({ space: 10 }) {
        // 模拟顶部的筛选器
        Row()
          .height(32)
          .width('100%')
          .borderRadius(16)
          .margin({ bottom: 10 })
          .opacity(this.skeletonOpacity)
          .backgroundColor($r('sys.color.comp_divider'))
          .animation({ duration: 800, curve: Curve.EaseInOut })
        // 模拟内容区 (瀑布流占位)
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start, space: { main: LengthMetrics.vp(10), cross: LengthMetrics.vp(10) } }) {
          ForEach([220, 180, 250, 200, 240, 190], (height: number) => {
            Column()
              .width('48%')
              .height(height)
              .borderRadius(12)
              .opacity(this.skeletonOpacity)
              .backgroundColor($r('sys.color.comp_divider'))
              .animation({ duration: 800, curve: Curve.EaseInOut })
          })
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: PixState.PageMarginValue, right: PixState.PageMarginValue })
    }
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }

  aboutToAppear(): void {
    trendVM.onReady();
    // 骨架屏闪烁动画
    this.intervalId = setInterval(() => {
      this.skeletonOpacity = this.skeletonOpacity === 1 ? 0.4 : 1;
    }, 800);
  }

  aboutToDisappear(): void {
    trendVM.onDisappear();
    if (this.intervalId !== -1) clearInterval(this.intervalId);
  }

}


/**
 * 单个筛选页（全部/公开/私密）。
 * 独立成组件以便在挂载时触发懒加载（首次进入、预载、插画/小说模式切换重建时均生效）
 */
@ComponentV2
struct TrendFilterPage {

  @Param index: number = 0;

  aboutToAppear(): void {
    trendVM.ensurePageLoaded(this.index);
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
      if (trendVM.illustPage(this.index).isLoading && !trendVM.illustPage(this.index).loaded) {
        LoadingProgress()
          .width(40)
          .height(40)
          .color(PixState.currentThemeColor)
      } else {
        Refresh({ refreshing: trendVM.illustPage(this.index).isRefreshing }) {
          WaterFlowView({
            contentEndOffset: PixState.FloatTabBarListAvoid,
            illustList: trendVM.illustPage(this.index).illusts,
            onCardClick: (illust: PixivIllust) => { trendVM.handleIllustClick(illust); },
            onReachEnd: () => { trendVM.loadMore(); }
          })
        }
        .width('100%')
        .height('100%')
        .onRefreshing(async () => { await trendVM.refreshPage(this.index) })
      }
    }
    .width('100%')
    .height('100%')
  }

  // 小说筛选页
  @Builder
  NovelContent() {
    Stack() {
      if (trendVM.novelPage(this.index).isLoading && !trendVM.novelPage(this.index).loaded) {
        LoadingProgress()
          .width(40)
          .height(40)
          .color(PixState.currentThemeColor)
      } else {
        Refresh({ refreshing: trendVM.novelPage(this.index).isRefreshing }) {
          NovelListView({
            contentEndOffset: PixState.FloatTabBarListAvoid,
            novelList: trendVM.novelPage(this.index).novels,
            onItemClick: (novel: PixivNovel) => {
            },
            onReachEnd: () => { trendVM.loadMore(); }
          })
        }
        .width('100%')
        .height('100%')
        .onRefreshing(async () => { await trendVM.refreshPage(this.index) })
      }
    }
    .width('100%')
    .height('100%')
  }

}

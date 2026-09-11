import { NaviContainer } from "../../components/NaviContainer"
import { followVM } from "../../viewmodel/FollowViewModel"
import { PixState } from "../../entryability/AppState"
import { SegmentButtonV2Items, TabSegmentButtonV2 } from "@kit.ArkUI"
import { UserListView } from "../../components/UsersListView"
import { EmptyStateView } from "../../components/CommonWidgets"
import { PixivIllust } from "../../services/PixivTypes"

@Builder
export function FollowPageBuilder() {
  FollowPage()
}


@ComponentV2
struct FollowPage {

  // onReady 时才拿到真实导航栈，用 @Local 保证重新赋值能同步到筛选页子组件
  @Local pageStack: NavPathStack = new NavPathStack()
  private swiperController: SwiperController = new SwiperController()
  private filterTabItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: $r('app.string.all') },
    { text: $r('app.string.public') },
    { text: $r('app.string.private') },
  ]);

  aboutToAppear(): void {
    followVM.onReady();
  }

  aboutToDisappear(): void {
    followVM.onDisappear();
  }

  build() {
    NaviContainer({
      title: $r('app.string.follow'),
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
          selectedIndex: followVM.filterIndex,
          enableStateAnimation: true,
          onItemClicked: (tab) => { this.onFilterClick(tab); }
        })
      }
      .padding({ left: PixState.PageMarginValue, right: PixState.PageMarginValue })
      .width('100%')

      // 左右滑动在 全部/公开/私密 间切换（同排行榜交互）
      Swiper(this.swiperController) {
        ForEach([0, 1, 2], (index: number) => {
          FollowFilterPage({ index: index, pageStack: this.pageStack })
        }, (index: number) => `${index}`)
      }
      .index(followVM.filterIndex)
      .loop(false)
      .indicator(false)
      .cachedCount(2)
      .duration(280)
      .nestedScroll(SwiperNestedScrollMode.SELF_FIRST)
      .onChange((index: number) => {
        followVM.syncFilter(index);
      })
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Start)
  }

  // 筛选器点击：同步 Swiper 翻页
  private onFilterClick(index: number) {
    followVM.syncFilter(index);
    this.swiperController.changeIndex(index);
  }

}

/**
 * 单个筛选页（全部/公开/私密）。
 * 独立成组件以便在挂载时触发懒加载（首次进入、预载时均生效）
 */
@ComponentV2
struct FollowFilterPage {

  @Param index: number = 0;
  @Param pageStack: NavPathStack = new NavPathStack()

  aboutToAppear(): void {
    followVM.ensurePageLoaded(this.index);
  }

  build() {
    Stack() {
      if (followVM.userPage(this.index).isLoading && !followVM.userPage(this.index).loaded) {
        LoadingProgress()
          .width(40)
          .height(40)
          .color(PixState.currentThemeColor)
      } else if (followVM.userPage(this.index).loaded && followVM.userPage(this.index).users.length === 0) {
        EmptyStateView({
          icon: $r('sys.symbol.person_2'),
          message: $r('app.string.no_data')
        })
      } else {
        Refresh({ refreshing: followVM.userPage(this.index).isRefreshing }) {
          UserListView({
            contentEndOffset: PixState.widthBp == 2 ? 56 : 16,
            userPres: followVM.userPage(this.index).users,
            isFollow: true,
            onButtonClick: (result: boolean, err?: string) => { },
            onImageClick: (illust: PixivIllust) => { followVM.handleIllustClick(illust, this.pageStack) },
            onReachEnd: () => { followVM.loadMore(); }
          })
        }
        .width('100%')
        .height('100%')
        .onRefreshing(async () => { await followVM.refreshPage(this.index) })
      }
    }
    .width('100%')
    .height('100%')
  }

}

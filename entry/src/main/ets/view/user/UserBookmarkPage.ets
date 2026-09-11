import { NaviContainer } from "../../components/NaviContainer";
import { WaterFlowView } from "../../components/WaterFlowView";
import { UserDetailParams } from "../../common/entity/UserDetailEntity";
import { UserBookmarkViewModel } from "../../viewmodel/UserBookmarkViewModel";
import { PixState } from "../../entryability/AppState";


@Builder
export function UserBookmarkBuilder(name: string, param: Object) {
  UserBookmarkPage()
}


@ComponentV2
struct UserBookmarkPage {

  @Local vm: UserBookmarkViewModel = new UserBookmarkViewModel()

  build() {
    NaviContainer({
      title: $r('app.string.collection'),
      content: () => {
        this.Content()
      },
      onReady: (ctx: NavDestinationContext) => {
        const params: UserDetailParams = ctx?.pathInfo?.param as UserDetailParams
        if (params?.id) {
          this.vm.onReady(params.id)
        }
      }
    })
  }

  @Builder
  Content() {
    Stack() {
      if (this.vm.isLoading && this.vm.bookmarks.length === 0) {
        LoadingProgress()
          .width(40)
          .height(40)
          .color(PixState.currentThemeColor)
      } else {
        WaterFlowView({
          contentEndOffset: PixState.bottomRectHeight === 0 ? PixState.PageMarginValue : PixState.bottomRectHeight,
          illustList: this.vm.bookmarks,
          emptyText: $r('app.string.no_data'),
          showBookmarkBadge: false, // 收藏页内已全为收藏，不显示角标
          onCardClick: (illust) => {
            this.vm.handleIllustClick(illust)
          },
          onReachEnd: () => {
            this.vm.loadMore()
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }

}

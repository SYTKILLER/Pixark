import { PixState } from "../entryability/AppState";
import { createLogger } from "../common/utils/Logger";
import { NovelSeriesViewModel } from "../viewmodel/NovelSeriesViewModel";
import { NaviContainer } from "../components/NaviContainer";
import { NovelListView } from "../components/NovelListView";
import { EmptyStateView } from "../components/CommonWidgets";

const logger = createLogger('NovelSeriesPage');


@Builder
export function NovelSeriesBuilder() {
  NovelSeries()
}


export interface NovelSeriesParams {
  seriesId: number;
  seriesTitle?: string;
}


@ComponentV2
struct NovelSeries {

  @Local vm: NovelSeriesViewModel | null = null;
  @Local seriesTitle: string = '';

  build() {
    NaviContainer({
      title: this.seriesTitle !== '' ? this.seriesTitle : $r('app.string.series_works'),
      content: () => {
        this.Content()
      },
      onReady: (ctx: NavDestinationContext) => {
        const params = ctx.pathInfo.param as NovelSeriesParams | null;
        if (params && params.seriesId) {
          this.seriesTitle = params.seriesTitle || '';
          this.vm = new NovelSeriesViewModel(params.seriesId);
          this.vm.fetch();
        }
      }
    })
  }

  @Builder
  Content() {
    if (!this.vm || this.vm.isLoading) {
      Column({ space: 12 }) {
        LoadingProgress()
          .width(40).height(40)
          .color(PixState.currentThemeColor)
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else if (this.vm.isError) {
      Column() {
        EmptyStateView({
          icon: $r('sys.symbol.exclamationmark_triangle'),
          message: '系列作品加载失败',
          actionText: '重试',
          onAction: () => {
            this.vm?.fetch();
          }
        })
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else if (this.vm.novels.length === 0) {
      Column() {
        EmptyStateView({
          icon: $r('sys.symbol.book'),
          message: '暂无系列作品'
        })
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else {
      Column() {
        this.SeriesHeader()
        // 作品列表（点击条目由组件内部跳转 novel_detail）
        NovelListView({
          novelList: this.vm.novels,
          onReachEnd: () => {
            this.vm?.loadMore();
          }
        })
        // 加载更多提示
        if (this.vm.isLoadingMore) {
          Row({ space: 8 }) {
            LoadingProgress()
              .width(20).height(20)
              .color(PixState.currentThemeColor)
            Text('加载中...').fontSize(13).fontColor($r('sys.color.font_tertiary'))
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .padding({ top: 8, bottom: PixState.bottomRectHeight + 12 })
        }
      }
      .width('100%')
      .layoutWeight(1)
    }
  }

  @Builder
  SeriesHeader() {
    Row({ space: 12 }) {
      Text(`共 ${this.vm!.seriesDetail?.content_count ?? this.vm!.novels.length} 话`)
        .fontSize(13)
        .fontColor($r('sys.color.font_secondary'))
      if (this.vm!.seriesDetail?.is_concluded) {
        Text('已完结')
          .fontSize(11)
          .fontColor($r('sys.color.font_tertiary'))
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .borderRadius(8)
          .backgroundColor($r('sys.color.ohos_id_color_hover'))
      }
      Blank()
      if (this.vm!.seriesDetail?.total_character_count) {
        Text(`约 ${(this.vm!.seriesDetail.total_character_count / 10000).toFixed(1)} 万字`)
          .fontSize(13)
          .fontColor($r('sys.color.font_tertiary'))
      }
    }
    .width('100%')
    .padding({ left: PixState.PageMarginValue, right: PixState.PageMarginValue, top: 8, bottom: 4 })
  }

}

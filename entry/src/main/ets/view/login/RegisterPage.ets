import { webview } from "@kit.ArkWeb";
import { PixState } from "../../entryability/AppState";
import { createLogger } from "../../common/utils/Logger";
import { NaviContainer } from "../../components/NaviContainer";
import { AppConstants } from "../../common/constants/AppConstants";

const logger = createLogger('Register')

@Builder
export function RegisterPage() {
  RegisterPageComponent()
}

@ComponentV2
struct RegisterPageComponent {

  webviewController: webview.WebviewController = new webview.WebviewController();
  @Local pageLoading: boolean = true
  @Local loadProgress: number = 0

  build() {
    NaviContainer({
      title: $r('app.string.register'),
      content: () => {
        this.Content()
      }
    })
  }

  @Builder
  Content() {
    Stack() {
      Web({ src: AppConstants.REGISTER_URL, controller: this.webviewController })
        .domStorageAccess(true)
        .javaScriptAccess(true)
        .width('100%')
        .layoutWeight(1)
        .onPageBegin(() => {
          this.pageLoading = true
        })
        .onPageEnd(() => {
          this.pageLoading = false
        })

      // 顶部细进度线 + 加载指示
      if (this.pageLoading) {
        Column() {
          Progress({ value: this.loadProgress + 15, total: 100, type: ProgressType.Linear })
            .color($r('app.color.brand'))
            .style({ strokeWidth: 2 })
            .width('100%')
        }
        .padding({ top: 2 })
      }
    }
    .width('100%')
    .height('100%')
  }

}

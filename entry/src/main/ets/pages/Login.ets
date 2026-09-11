import { NaviContainer } from '../components/NaviContainer';
import { PixState, _PixState } from '../entryability/AppState';
import { curves } from '@kit.ArkUI';


@Builder
export function LoginBuilder() {
  Login()
}

@ComponentV2
export struct Login {

  @Param mode: 'main' | 'router' = 'router'
  private pageStack: NavPathStack = new NavPathStack()
  // 图标入场动效开关
  @Local iconEnter: boolean = false

  aboutToAppear(): void {
    setTimeout(() => {
      this.iconEnter = true
    }, 50)
  }

  build() {
    if (this.mode === 'main') {
      Navigation(this.pageStack) {
        this.Content()
      }
      .height('100%')
      .width('100%')
      .hideToolBar(true)
      .hideTitleBar(true)
      .mode(NavigationMode.Stack)
    } else {
      NaviContainer({
        hideTitleBar: !PixState.isAddingAccount,
        content: () => {
          this.Content()
        },
        onReady: (ctx) => {
          if (ctx.pathStack) {
            this.pageStack = ctx.pathStack
          }
        }
      })
    }
  }

  @Builder
  Content() {
    Column() {
      // 图标（入场动效）
      Image($r('app.media.app_icon_round'))
        .height(106)
        .margin({ bottom: 60 })
        .scale({ x: this.iconEnter ? 1 : 0.6, y: this.iconEnter ? 1 : 0.6 })
        .opacity(this.iconEnter ? 1 : 0)
        .animation({ duration: 500, curve: curves.springMotion(0.42, 0.8) })

      // 登录 (跳转到 Web 登录页) —— 主 CTA
      Button(PixState.isAddingAccount ? $r('app.string.add_an_account') : $r('app.string.login'))
        .width('80%')
        .height(50)
        .fontSize(18)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.brand'))
        .margin({ bottom: 16 })
        .onClick(() => {
          // 跳转到 Web 登录页
          this.pageStack.pushPathByName('web_login', null);
        })

      // 注册账号 (跳转到注册页) —— 次级描边按钮
      if (!PixState.isAddingAccount) {
        Button($r('app.string.register_account'))
          .width('80%')
          .height(50)
          .fontSize(18)
          .fontColor($r('app.color.brand'))
          .backgroundColor(Color.Transparent)
          .border({ width: 1, color: $r('app.color.brand') })
          .margin({ bottom: 16 })
          .onClick(() => {
            this.pageStack.pushPathByName('register', null);
          })
      }

      // Token 登录 (跳转到 Token 输入页) —— 文字按钮
      Button($r('app.string.token_login'))
        .width('80%')
        .height(44)
        .fontSize(15)
        .backgroundColor(Color.Transparent)
        .fontColor($r('sys.color.font_secondary'))
        .onClick(() => {
          // 跳转到 Token 登录页
          this.pageStack.pushPathByName('token_login', null);
        })

      // 底部版本号
      Text(`v${_PixState.appVersion}`)
        .fontSize(12)
        .fontColor($r('sys.color.font_tertiary'))
        .margin({ top: 40 })
    }
    .padding({ top: PixState.topRectHeight, bottom: PixState.bottomRectHeight })
    .justifyContent(FlexAlign.Center)
    .layoutWeight(1)
    .linearGradient({
      angle: 180,
      colors: [[$r('app.color.brand_weak'), 0], ['#00000000', 0.45]]
    })
  }

}

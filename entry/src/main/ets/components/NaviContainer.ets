import UIConstants from "../common/constants/UIConstants"
import { PixState } from "../entryability/AppState"
import { KeyCode } from "@kit.InputKit"


@ComponentV2
export struct NaviContainer {

  @Param title: ResourceStr | undefined = undefined
  @Param subTitle: ResourceStr = ''

  @Param showMenu: boolean = false
  @Param hideTitleBar: boolean = false

  @Param transitionEffect?: TransitionEffect = undefined

  /** 内容区是否已滚动（由页面滚动回调驱动），控制标题栏毛玻璃渐入 */
  @Param contentScrolled: boolean = false
  /** 是否启用标题栏滚动联动毛玻璃 */
  @Param enableTitleBlur: boolean = true

  @BuilderParam menusBuilder?: () => void
  @BuilderParam content: () => void;

  @Param buttons: NavigationMenuItem[] = []

  private pageStack: NavPathStack = new NavPathStack()

  @Event onReady: (ctx: NavDestinationContext) => void
  @Event onBackPressed: () => boolean
  @Event onNaviDisAppear: () => void

  private get showBlurBar(): boolean {
    return this.enableTitleBlur && !this.hideTitleBar && this.title !== undefined
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Top }) {
        // 滚动联动毛玻璃标题栏背景层（不拦截点击）
        if (this.showBlurBar) {
          Row()
            .width('100%')
            .height(PixState.topRectHeight + 56)
            .backgroundBlurStyle(BlurStyle.Thin, {
              colorMode: ThemeColorMode.SYSTEM,
              adaptiveColor: AdaptiveColor.DEFAULT
            })
            .border({ width: { bottom: 0.5 }, color: $r('sys.color.comp_divider') })
            .opacity(this.contentScrolled ? 1 : 0)
            .animation({ duration: 250, curve: Curve.Ease })
            .hitTestBehavior(HitTestMode.None)
        }
        Column() {
          if (this.menusBuilder) {
            Row().height(1).width('100%')
              .bindContextMenu(this.showMenu!!, this.menusBuilder,
                {
                  placement: PixState.widthBp < 2 ? Placement.LeftBottom : Placement.BottomRight,
                })
          }
          Column() {
            this.content()
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Start)
          .alignItems(HorizontalAlign.Center)
        }
        .width('100%')
      }
      .width('100%')
      .height('100%')
    }
    .height('100%')
    .hideToolBar(true)
    .menus(this.buttons)
    .hideTitleBar(this.hideTitleBar || !this.title)
    .transition(this.transitionEffect)
    .padding((this.hideTitleBar || !this.title) ? undefined : { top: PixState.topRectHeight || 12 })
    .title({ main: this.title, sub: this.subTitle }, { backgroundColor: Color.Transparent })
    .onBackPressed(() => {
      return this.onBackPressed()
    })
    .onKeyEvent((event: KeyEvent) => {
      if (event.type === KeyType.Down) {
        if (event.keyCode === KeyCode.KEYCODE_ESCAPE) {
          if (!this.onBackPressed()) {
            this.pageStack.pop()
          }
        }
      }
    })
    .onReady((ctx: NavDestinationContext) => {
      this.pageStack = ctx.pathStack
      this.onReady(ctx)
    })
    .animation({ duration: UIConstants.AnimationSpeed_300, curve: Curve.Ease })
  }

}


import { PixivUser, UserDetailResponse } from "../services/PixivTypes"
import { common } from "@kit.AbilityKit"
import { window } from "@kit.ArkUI"
import { HdsTabsController } from "@kit.UIDesignKit"
import { PageMargin,
  TabBarAvoidHeight,
  TabBarHeight, TabBarVertical, Window_BAR_HEIGHT } from "../common/utils/breakpoint/BreakPoint"
import { createLogger } from "../common/utils/Logger"

const logger = createLogger('PixivState')

/** HdsTabs 悬浮页签栏自身高度（悬浮样式官方默认值 56vp），手机端见 Index.ets 的 barFloatingStyle */
const FLOATING_BAR_HEIGHT = 56


@ObservedV2
export class _PixState {

  // 当前登录用户
  @Trace currentUser: PixivUser | null = null
  @Trace currentUserDetail: UserDetailResponse | null = null
  // 登录方式
  @Trace loginMethod: 'password' | 'token' = 'token'
  // refresh token
  @Trace refreshToken: string = ''
  // 是否处于多账号添加模式
  @Trace isAddingAccount: boolean = false
  // 是否初始化
  @Trace isInitializing: boolean = true
  // 加载状态
  @Trace isLoading: boolean = false
  // 是否登录过
  @Trace isLoggedIn: boolean = false

  public static appVersion: string = '1.0.0'

  // 窗口对象
  public static UIContext: UIContext
  public static Context: common.UIAbilityContext
  public static window: window.Window;
  /** @description 窗口高度 -px */
  public static windowWidth_px: number;
  /** @description 窗口高度 -px */
  public static windowHeight_px: number;
  /** @description 状态栏高度 -px */
  public static topAvoidAreaHeight_px: number;
  /** @description 导航栏高度 -px */
  public static navigationIndicatorHeight_px: number;
  /** @description 导航栏高度 */
  @Trace bottomRectHeight: number = 0
  /** @description 状态栏高度 */
  @Trace topRectHeight: number = 0
  /** @description 左侧避让宽度 */
  @Trace leftAvoidWidth: number = 0
  /** @description 右侧避让宽度 */
  @Trace rightAvoidWidth: number = 0
  /** @description 窗口高度 -vp */
  @Trace windowHeight: number = 0
  /** @description 窗口宽度 -vp */
  @Trace windowWidth: number = 0
  /** @description 当前宽度断点 */
  @Trace widthBp: number = 0
  /** @description 当前宽度断点 */
  @Trace heightBp: number = 0
  /** @description 窗口模式 true为PC窗口模式 false为普通窗口模式 */
  @Trace windowMode: boolean = false

  isTest: boolean = false

  @Trace currentTab: number = 0
  // 悬浮按钮位置
  @Trace buttonPosition: number = 0

  // 全局路由
  @Trace pageStack: NavPathStack = new NavPathStack()
  @Trace tabsController: HdsTabsController = new HdsTabsController()
  @Trace transitionEffect: TransitionEffect = TransitionEffect.IDENTITY;
  /** @description 当前主题色(Resource) */
  @Trace currentThemeColor: Resource = $r('app.color.brand')

  @Computed
  get TabBarVertical() {
    return TabBarVertical(this.widthBp, this.heightBp)
  }

  @Computed
  get PageMarginValue() {
    return PageMargin(this.widthBp, this.heightBp)
  }

  @Computed
  get TabBarHeight(): number | string {
    const isVerticalTab = PixState.TabBarVertical;
    // 窗口模式 + 横向 TabBar (TabBar在底部)
    if (PixState.windowMode && !isVerticalTab) {
      return Window_BAR_HEIGHT;
    }
    // 普通窗口，不避让安全区
    if (PixState.bottomRectHeight === 0) {
      return TabBarHeight(PixState.widthBp, PixState.heightBp);
    }
    // 普通窗口，避让安全区域高度 (沉浸式 + 安全区)
    return TabBarAvoidHeight(PixState.widthBp, PixState.heightBp);
  }

  /**
   * 手机悬浮页签栏底部避让总高度 = 页签栏高度(56) + barBottomMargin(底部安全区，无指示器时 16) + 12vp 呼吸空间。
   * 用于页面级底部 padding（如更多页）。宽屏/PC 为侧边页签，无需底部避让，返回 0
   */
  @Computed
  get FloatTabBarAvoid(): number {
    if (TabBarVertical(this.widthBp, this.heightBp)) {
      return 0
    }
    return (this.bottomRectHeight > 0 ? this.bottomRectHeight : 16) + FLOATING_BAR_HEIGHT + 12
  }

  /** 传给 WaterFlowView/NovelListView 等列表组件的 contentEndOffset（组件内部会再叠加 bottomRectHeight） */
  @Computed
  get FloatTabBarListAvoid(): number {
    return this.FloatTabBarAvoid - this.bottomRectHeight
  }

  @Monitor('pageStack')
  onPageStackChange() {
    if (this.currentTab == 3 && this.pageStack.size() <= 1 ) {
      }
  }

}

export const PixState: _PixState = new _PixState()
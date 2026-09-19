import { PixState, _PixState } from '../entryability/AppState';
import { TabBarPosition,
  TabBarWidth,
  WindowTabBarWidth } from '../common/utils/breakpoint/BreakPoint';
import { SymbolGlyphModifier, curves, window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { HdsTabs, hdsMaterial } from '@kit.UIDesignKit';
import { animation } from '../common/utils/AnimationUtil';
import { TabBuild, TAB_ORDER } from '../common/entity/IndexEntity';
import { Home } from './Home';
import { SearchPage } from './Search';
import { Trend } from './Trend';
import { Rank } from './Rank';
import { homeViewModel } from '../viewmodel/HomeViewModel';
import { Login } from './Login';
import UIConstants from '../common/constants/UIConstants';
import { More } from './More';
import { createLogger } from '../common/utils/Logger';
import { appSettings, UISettings } from '../common/entity/SettingsModel';
import { motion } from '@kit.MultimodalAwarenessKit';
import { HoldingHandleUtil } from '../common/utils/HoldingHandleUtil';


const logger = createLogger('Index')

// 握持状态须稳定保持该时长才换边，过滤系统左右手判定抖动（holdingHandChanged 高频抖动会导致按钮左右横跳）
const HOLDING_STABLE_MS = 500


@Entry
@ComponentV2
struct Index {

  // 页签栏双击检测时间戳（双击首个页签刷新主页推荐）
  @Local lastTabClickTime: number = 0

  // 待生效的换边定时器（-1 表示无）
  private holdDebounceTimer: number = -1

  // 主窗口引用与避让区变化监听（off 时需要同一引用）
  private mainWindow: window.Window | undefined = undefined
  private onAvoidAreaChange = () => {
    if (this.mainWindow) {
      this.readInsets(this.mainWindow)
    }
  }

  // 允许自定义转换的页面的名称 自
  private allowedCustomTransitionFromPageNames: string[] =
    ['illust_detail',
    ];
  // 允许自定义转换的页面的名称 至
  private allowedCustomTransitionToPageNames: string[] =
    ['illust_detail',
    ];

  aboutToAppear() {
    logger.debug('Page aboutToAppear');
    // 启动适人握持
    HoldingHandleUtil.start((status: motion.HoldingHandStatus) => {
      this.handleHoldingStatusChange(status);
    })
    // 从页面上下文读取避让区：Ability 侧过早调用 getWindowAvoidArea 会静默失败（1300002），
    // 页面就绪后读值才可靠，并监听变化持续更新（写入 PixState 供 HdsTabs 与各页面消费）
    this.initAvoidInsets()
  }

  aboutToDisappear(): void {
    // 丢弃尚未生效的换边
    if (this.holdDebounceTimer !== -1) {
      clearTimeout(this.holdDebounceTimer)
      this.holdDebounceTimer = -1
    }
    // 停止适人握持
    HoldingHandleUtil.stop()
    if (this.mainWindow) {
      this.mainWindow.off('avoidAreaChange', this.onAvoidAreaChange)
    }
  }

  private initAvoidInsets() {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext
    window.getLastWindow(ctx).then((win: window.Window) => {
      this.mainWindow = win
      this.readInsets(win)
      win.on('avoidAreaChange', this.onAvoidAreaChange)
    }).catch((err: BusinessError) => {
      logger.error('AvoidInsets', `Failed to get last window, ${err}`)
    })
  }

  private readInsets(win: window.Window) {
    try {
      const uiContext = this.getUIContext()
      const systemArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)
      const indicatorArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR)
      PixState.topRectHeight = uiContext.px2vp(systemArea.topRect.height)
      PixState.bottomRectHeight = uiContext.px2vp(indicatorArea.bottomRect.height)
      logger.debug('AvoidInsets', `top: ${PixState.topRectHeight}vp bottom: ${PixState.bottomRectHeight}vp`)
    } catch (error) {
      logger.error('AvoidInsets', `Failed to read avoid areas, ${error}`)
    }
  }

  build() {
    // 存在账号信息显示内容
    if (PixState.isLoggedIn) {
      Navigation(PixState.pageStack) {
        this.MainContent()
      }
      .height('100%')
      .width('100%')
      .hideToolBar(true)
      .hideTitleBar(true)
      .mode(NavigationMode.Stack)
      .transition(TransitionEffect.OPACITY)
    }
    // 未登录显示登录页
    else {
      Login({ mode: 'main' })
    }
  }

  @Builder
  MainContent() {
    Stack() {
      if (PixState.isLoading) {
        LoadingProgress()
          .width(40)
          .height(40)
          .margin({ bottom: 12 });
      }
      this.CustomTab()
    }
    .height('100%')
    .width('100%')
  }

  @Builder
  LogoStartLoading() {
    Column() {
      Image($r('app.media.app_icon_round'))
        .height(106)
        .margin({ bottom: 20 })

      LoadingProgress()
        .width(40)
        .height(40)
        .color($r('sys.color.brand'))

      Text('正在初始化...')
        .fontSize(14)
        .fontColor('#999')
        .margin({ top: 10 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.start_window_background'))
  }

  // 处理握持状态变化的业务逻辑
  private handleHoldingStatusChange(status: motion.HoldingHandStatus) {
    // 每个事件先取消未生效的换边：只有连续 HOLDING_STABLE_MS 保持不变的状态才落位
    if (this.holdDebounceTimer !== -1) {
      clearTimeout(this.holdDebounceTimer);
      this.holdDebounceTimer = -1;
    }
    let targetIndex = 0; // 默认右手/未握持
    switch (status) {
      case motion.HoldingHandStatus.LEFT_HAND_HELD:
        targetIndex = 2; // 左手 -> 左侧
        break;
      case motion.HoldingHandStatus.BOTH_HANDS_HELD:
        // 双手握持不换边，保持当前位置（单手定位只在"稳定单手"时生效）
        return;
      case motion.HoldingHandStatus.RIGHT_HAND_HELD:
      case motion.HoldingHandStatus.NOT_HELD:
      default:
        targetIndex = 0; // 右手/未握持 -> 右侧
        break;
    }
    // 与当前位置一致则无需换边
    if (targetIndex === PixState.buttonPosition) {
      return;
    }
    this.holdDebounceTimer = setTimeout(() => {
      this.holdDebounceTimer = -1;
      if (targetIndex === PixState.buttonPosition) {
        return;
      }
      // 执行动画和状态更新
      _PixState.UIContext.animateTo({ duration: 350, curve: curves.springMotion() }, () => {
        // 更新持久化配置
        PixState.buttonPosition = targetIndex;
      });
      logger.debug(`握持稳定落位: ${status}, 按钮位置:${targetIndex}`);
    }, HOLDING_STABLE_MS);
  }

  @Builder
  CustomTab() {
    if (PixState.TabBarVertical) {
      // 宽屏/PC：侧边竖排页签
      HdsTabs({
        barPosition: TabBarPosition(PixState.widthBp, PixState.heightBp),
        controller: PixState.tabsController
      }) {
        this.TabContents()
      }
      .zIndex(1)
      .barWidth(PixState.windowMode ? WindowTabBarWidth(PixState.widthBp, PixState.heightBp) : TabBarWidth(PixState.widthBp, PixState.heightBp))
      .barHeight(PixState.TabBarHeight)
      .vertical(true)
      .barOverlap(false)
      .onTabBarClick((index: number) => {
        this.handleTabBarClick(index)
      })
      .onAnimationStart((index: number, targetIndex: number) => {
        this.handleAnimationStart(index, targetIndex)
      })
      .onAppear(() => {
        PixState.tabsController.changeIndex(this.initialTabIndex())
      })
      .width('100%').height('100%')
      .margin({ top: PixState.windowMode ? 42 : 0 })
      .padding({
        top: PixState.topRectHeight,
        bottom: PixState.bottomRectHeight == 0 ? PixState.bottomRectHeight / 2 : 0
      })
    } else {
      // 手机：悬浮胶囊页签栏 + 沉浸光感材质（高度/宽度由 HdsTabs 悬浮样式自管理）
      HdsTabs({
        barPosition: BarPosition.End,
        controller: PixState.tabsController
      }) {
        this.TabContents()
      }
      .zIndex(1)
      .barOverlap(true)
      .vertical(false)
      .barFloatingStyle({
        barBottomMargin: PixState.bottomRectHeight > 0 ? PixState.bottomRectHeight : 16,
        adaptToHandedness: true,
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      })
      .onTabBarClick((index: number) => {
        this.handleTabBarClick(index)
      })
      .onAnimationStart((index: number, targetIndex: number) => {
        this.handleAnimationStart(index, targetIndex)
      })
      .onAppear(() => {
        PixState.tabsController.changeIndex(this.initialTabIndex())
      })
      .width('100%').height('100%')
      .padding({
        top: PixState.topRectHeight,
        bottom: PixState.bottomRectHeight == 0 ? PixState.bottomRectHeight / 2 : 0
      })
    }
  }

  @Builder
  TabContents() {
    ForEach(this.getTabList(), (item: TabBuild) => {
      TabContent() {
        this.TabContentBuilder(item)
      }
      .tabBar(new BottomTabBarStyle({
        normal: new SymbolGlyphModifier(item.icon).fontColor([$r('sys.color.font_primary')]),
        selected: new SymbolGlyphModifier(item.icon_fill).fontColor([PixState.currentThemeColor])
      }, item.title))
      // key 携带模式后缀：模式切换时图标等页签属性随 itemGenerator 重建（同 key 不会重执行）
    }, (item: TabBuild) => `${item.name}_${appSettings.novel_mode ? 'n' : 'i'}`)
  }

  // 页签点击：双击首个页签刷新主页推荐
  private handleTabBarClick(index: number) {
    const now = Date.now()
    if (index === 0 && now - this.lastTabClickTime < 300) {
      homeViewModel.refreshRecommended()
    }
    this.lastTabClickTime = now
    animation.animTo(() => {
      PixState.currentTab = index
    }, UIConstants.AnimationSpeed_300, 'app', 0)
  }

  // 滑动切页动画开始时同步选中态
  private handleAnimationStart(index: number, targetIndex: number) {
    animation.animTo(() => {
      PixState.currentTab = targetIndex;
    }, UIConstants.AnimationSpeed_300, 'app', 0)
  }
  @Builder
  TabContentBuilder(item: TabBuild) {
    // 页签列表随小说模式增删，索引会漂移，内容区按 name 分发
    if (item.name === 'home') {
      Home()
    } else if (item.name === 'rank') {
      Rank()
    } else if (item.name === 'trend') {
      Trend()
    } else if (item.name === 'search') {
      SearchPage()
    } else {
      More()
    }
  }

  // main_show 存储的是固定五页布局下的索引，换算为当前页签列表的索引；目标页签不存在（小说模式下选了排行榜）时回退主页
  private initialTabIndex(): number {
    const idx = Number(UISettings.main_show)
    const name = (idx >= 0 && idx < TAB_ORDER.length) ? TAB_ORDER[idx] : 'home'
    const index = this.getTabList().findIndex((item: TabBuild) => item.name === name)
    return index >= 0 ? index : 0
  }

  getTabList(): TabBuild[] {
    const tabList: TabBuild[] = [
      { name: 'home', title: $r('app.string.home'), icon: $r('sys.symbol.house'), icon_fill: $r('sys.symbol.house_fill') }
    ]
    // pixiv 源站无小说排行榜：小说模式下隐藏排行榜页签入口
    if (!appSettings.novel_mode) {
      tabList.push({
        name: 'rank',
        title: $r('app.string.rank'),
        icon: $r('sys.symbol.ranking_badge_bolt'),
        icon_fill: $r('sys.symbol.ranking_badge_bolt')
      })
    }
    tabList.push(
      // 小说模式下动态页展示小说热门内容，图标随之切换
      {
        name: 'trend',
        title: $r('app.string.trend'),
        icon: appSettings.novel_mode ? $r('sys.symbol.doc_text') : $r('sys.symbol.picture_fill'),
        icon_fill: appSettings.novel_mode ? $r('sys.symbol.doc_text') : $r('sys.symbol.picture_fill')
      },
      { name: 'search', title: $r('app.string.search'), icon: $r('sys.symbol.curve_magnifyingglass'), icon_fill: $r('sys.symbol.AI_search') },
      { name: 'more', title: $r('app.string.more'), icon: $r('sys.symbol.square_grid_2x2'), icon_fill: $r('sys.symbol.square_fill_grid_2x2') }
    )
    return tabList
  }

  private isCustomTransitionEnabled(fromName: string, toName: string): boolean {
    // 点击和返回都需要自定义过渡，因此分别判断
    if ((this.allowedCustomTransitionFromPageNames.includes(fromName)
      && this.allowedCustomTransitionToPageNames.includes(toName))
      || (this.allowedCustomTransitionFromPageNames.includes(toName)
        && this.allowedCustomTransitionToPageNames.includes(fromName))) {
      return true;
    }
    return false;
  }

}

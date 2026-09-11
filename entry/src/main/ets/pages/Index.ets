import { PixState, _PixState } from '../entryability/AppState';
import { TabBarPosition,
  TabBarWidth,
  WindowTabBarWidth } from '../common/utils/breakpoint/BreakPoint';
import { SymbolGlyphModifier, curves } from '@kit.ArkUI';
import { HdsTabs, hdsMaterial } from '@kit.UIDesignKit';
import { animation } from '../common/utils/AnimationUtil';
import { TabBuild } from '../common/entity/IndexEntity';
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


@Entry
@ComponentV2
struct Index {

  // 页签栏双击检测时间戳（双击首个页签刷新主页推荐）
  @Local lastTabClickTime: number = 0

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
  }

  aboutToDisappear(): void {
    // 停止适人握持
    HoldingHandleUtil.stop()
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
    let targetIndex = 0; // 默认右手/未握持
    switch (status) {
      case motion.HoldingHandStatus.LEFT_HAND_HELD:
        targetIndex = 2; // 左手 -> 左侧
        break;
      case motion.HoldingHandStatus.BOTH_HANDS_HELD:

        break;
      case motion.HoldingHandStatus.RIGHT_HAND_HELD:
      case motion.HoldingHandStatus.NOT_HELD:
      default:
        targetIndex = 0; // 右手/未握持 -> 右侧
        break;
    }
    // 执行动画和状态更新
    _PixState.UIContext.animateTo({ duration: 350, curve: curves.springMotion() }, () => {
      // 更新持久化配置
      PixState.buttonPosition = targetIndex;
    }
    );
    logger.debug(`握持逻辑触发: ${status}, 按钮位置:${targetIndex}`);
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
        PixState.tabsController.changeIndex(Number(UISettings.main_show))
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
        PixState.tabsController.changeIndex(Number(UISettings.main_show))
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
    ForEach(this.getTabList(), (item: TabBuild, index: number) => {
      TabContent() {
        this.TabContentBuilder(index)
      }
      .tabBar(new BottomTabBarStyle({
        normal: new SymbolGlyphModifier(item.icon).fontColor([$r('sys.color.font_primary')]),
        selected: new SymbolGlyphModifier(item.icon_fill).fontColor([PixState.currentThemeColor])
      }, item.title))
    })
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
  TabContentBuilder(index: number) {
    if (index == 0) {
      Home()
    } else if (index == 1) {
      Rank()
    } else if (index == 2) {
      Trend()
    } else if (index == 3) {
      SearchPage()
    } else {
      More()
    }
  }

  getTabList(): TabBuild[] {
    const tabList: TabBuild[] = [
      { name: 'home', title: $r('app.string.home'), icon: $r('sys.symbol.house'), icon_fill: $r('sys.symbol.house_fill') },
      { name: 'rank', title: $r('app.string.rank'), icon: $r('sys.symbol.ranking_badge_bolt'), icon_fill: $r('sys.symbol.ranking_badge_bolt') },
      { name: 'trend', title: $r('app.string.trend'), icon: $r('sys.symbol.picture_fill'), icon_fill: $r('sys.symbol.picture_fill') },
      { name: 'search', title: $r('app.string.search'), icon: $r('sys.symbol.curve_magnifyingglass'), icon_fill: $r('sys.symbol.AI_search') },
      { name: 'more', title: $r('app.string.more'), icon: $r('sys.symbol.square_grid_2x2'), icon_fill: $r('sys.symbol.square_fill_grid_2x2') }
    ]
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

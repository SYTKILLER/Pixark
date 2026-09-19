import { PixState } from '../entryability/AppState';
import { PixivUser } from '../services/PixivTypes';
import { createLogger } from '../common/utils/Logger';
import { pixiv } from '../services/PixivService';
import { appSettings } from '../common/entity/SettingsModel';
import { TAB_ORDER } from '../common/entity/IndexEntity';
import { EventHub, EventKey } from '../common/utils/EventHub';
import { toastUtil } from '../common/utils/ToastUtils';
import { ResourceUtils } from '../common/utils/ResourceUtil';


const logger = createLogger('MoreViewModel');

@ObservedV2
export class MoreViewModel {

  @Trace emailPrivacy: boolean = true

  // 获取当前登录用户信息
  get currentUser(): PixivUser | null {
    return PixState.currentUser
  }

  get isLogin(): boolean {
    return pixiv.isLogin();
  }

  // 获取显示名称：优先 nickname，其次 name
  get displayName(): ResourceStr {
    if (this.currentUser) {
      return this.currentUser.name || this.currentUser.account || '未知用户';
    }
    return $r('app.string.not_logged_in');
  }

  // 获取邮箱显示
  get email(): string {
    return this.currentUser?.mail_address || '';
  }

  get avatarUrl(): string {
    return this.currentUser?.profile_image_urls?.medium || '';
  }

  get userID(): string {
    return (this.currentUser?.id || 0).toString();
  }

  switchMode() {
    // 页签列表随模式增删排行榜（五页布局 <-> 四页布局），切换后需把当前页签换算回新布局的索引
    const currentName = TAB_ORDER[PixState.currentTab]
    appSettings.novel_mode = !appSettings.novel_mode
    EventHub.sendEvent(EventKey.FetchData)
    this.relocateTabAfterModeSwitch(currentName)
    if (appSettings.novel_mode) {
      toastUtil.showToast({ message: ResourceUtils.getString($r('app.string.enter')) + ResourceUtils.getString($r('app.string.novel_mode')) })
    } else {
      toastUtil.showToast({ message: ResourceUtils.getString($r('app.string.enter')) + ResourceUtils.getString($r('app.string.illust_mode')) })
    }
  }

  // 换算当前页签在切换后布局中的位置；排行榜页签被移除时回主页
  private relocateTabAfterModeSwitch(previousName: string) {
    if (!previousName) {
      return
    }
    if (previousName === 'rank' && appSettings.novel_mode) {
      PixState.tabsController.changeIndex(0)
      return
    }
    // 当前布局：小说模式四页，插画模式五页
    const tabList = appSettings.novel_mode
      ? TAB_ORDER.filter((name: string) => name !== 'rank')
      : TAB_ORDER
    const target = tabList.indexOf(previousName)
    if (target >= 0 && target !== PixState.currentTab) {
      // changeIndex 会触发 HdsTabs onAnimationStart，currentTab 由 Index 统一同步
      PixState.tabsController.changeIndex(target)
    }
  }

  // 处理登出逻辑
  async handleLogout() {
    try {
      // TODO 确认弹窗及登出操作
      logger.info('User requested logout.');
      // 执行登出清理
      // await pixiv.logout()
      // 跳转回登录页
    } catch (e) {
      logger.error('Logout failed: ' + e.message);
    }
  }

}

export const moreVM = new MoreViewModel();

import { NaviContainer } from "../../components/NaviContainer"
import { SymbolGlyphModifier } from "@kit.ArkUI";
import { AccountContext } from "../../services/PixivTypes";
import { PixivImageComponent } from "../../components/PixivImage";
import { pixiv } from '../../services/PixivService';
import { kvDbUtil } from '../../common/utils/KVdbUtil';
import { PixState } from "../../entryability/AppState";
import { EventHub, EventKey } from "../../common/utils/EventHub";
import { EmptyStateView } from "../../components/CommonWidgets";


@Builder
export function UserAccountsBuilder() {
  UserAccounts()
}

@ComponentV2
struct UserAccounts {

  @Local users: AccountContext[] = []
  @Local isLoading: boolean = false
  @Local activeUserId: string = ''; // 记录当前激活的账号 ID

  private pageStack: NavPathStack = new NavPathStack()

  build() {
    NaviContainer({
      title: $r('app.string.user_accounts'),
      buttons: this.buttons(),
      content: () => { this.Content() },
      onReady: (ctx) => {
        this.pageStack = ctx.pathStack
        this.loadAccounts()
      }
    })
  }

  @Builder Content() {
    // 增加加载提示
    if (this.isLoading && this.users.length === 0) {
      Row() {
        LoadingProgress().width(24).height(24)
        Text($r('app.string.loading_info')).fontSize(14).fontColor($r('sys.color.font_secondary')).margin({ left: 8 })
      }.margin({ top: 50 }).justifyContent(FlexAlign.Center)
    }

    if (!this.isLoading && this.users.length === 0) {
      EmptyStateView({
        icon: $r('sys.symbol.person_crop_circle_fill'),
        message: $r('app.string.not_logged_in')
      })
    }

    List({ space: 12 }) {
      ForEach(this.users, (item: AccountContext) => {
        ListItem() {
          this.UserAccount(item)
        }
        .onClick(async () => {
          if (item.userId === this.activeUserId) return;
          // 防抖，防止用户连续快速点击切换
          if (this.isLoading) return;
          this.isLoading = true;
          try {
            // 切换底层激活账号
            pixiv.switchAccount(item.userId);
            this.activeUserId = item.userId;
            // 立即更新全局状态 (UI 响应刷新)
            PixState.currentUser = pixiv.getCurrentUser();
            PixState.isLoggedIn = true;
            // 持久化当前的选择
            await kvDbUtil.putData('active_user_id', item.userId);
            // 发出全局刷新事件 (EntryAbility 会接收并重置所有 VM)
            EventHub.sendEvent(EventKey.FetchData);
            // 返回主页
            // PixState.pageStack.pop();
          } catch (error) {
            console.error('Switch account failed', error);
          } finally {
            this.isLoading = false;
          }
        })
      })
    }
    .layoutWeight(1)
    .padding({ left: 16, right: 16 })
    .contentEndOffset(PixState.bottomRectHeight || 28)
  }

  @Builder UserAccount(userInfo: AccountContext) {
    Row({ space: 16 }) {
      PixivImageComponent({
        imageUrl: userInfo.user.profile_image_urls?.medium,
        imageWidth: 56,
        imageHeight: 56,
        imageBorder: { radius: 28 }
      })
      // 账户名 + 邮箱
      Column({ space: 4 }) {
        Text(userInfo.user.name)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
        Text(userInfo.user.mail_address || '未绑定邮箱')
          .fontColor($r('sys.color.font_secondary'))
          .fontSize(14)
      }
      .alignItems(HorizontalAlign.Start)
      Blank()
      if (userInfo.userId === this.activeUserId) {
        Row() {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontColor([Color.White])
            .fontSize(14)
        }
        .width(28)
        .height(28)
        .borderRadius(14)
        .justifyContent(FlexAlign.Center)
        .backgroundColor($r('app.color.brand'))
      }
    }
    .width('100%')
    .padding(14)
    .borderRadius(20)
    .backgroundColor($r('app.color.card_bg'))
    .border({
      width: userInfo.userId === this.activeUserId ? 1.5 : 0.5,
      color: userInfo.userId === this.activeUserId ? $r('app.color.brand') : $r('sys.color.comp_divider')
    })
    .animation({ duration: 200, curve: Curve.Ease })
  }

  // 加载并补全账号信息
  async loadAccounts() {
    this.activeUserId = pixiv.getActiveAccount()?.userId || '';
    // 拿到现有数据先渲染
    this.users = pixiv.getAllAccounts()

    // 过滤出需要补全头像的账号
    const needUpdateUsers = this.users.filter(u => !u.user.profile_image_urls?.medium);

    if (needUpdateUsers.length > 0) {
      this.isLoading = true;
      const promises = needUpdateUsers.map(async (u) => {
        try {
          const detail = await pixiv.getUserDetail(Number(u.userId));
          const fullUser = detail.user;
          // 保留邮箱
          fullUser.mail_address = u.user.mail_address || fullUser.mail_address;
          // 更新 PixivAuth 内部状态
          pixiv.updateAccountUser(u.userId, fullUser);
          // 更新本地 UI 数据源
          const index = this.users.findIndex(item => item.userId === u.userId);
          if (index !== -1) {
            const userAccount = this.users[index]
            userAccount.user = fullUser
            this.users.splice(index, 1, userAccount)
          }
        } catch (e) {
          console.warn(`Fetch detail for ${u.userId} failed`, e);
        }
      });

      // 并发请求补全
      await Promise.all(promises);
      // 强制刷新 UI
      this.users = [...this.users];
      // 持久化更新到本地数据库
      const allAccounts = pixiv.getAllAccounts();
      await kvDbUtil.putData('pixiv_accounts', JSON.stringify(allAccounts));

      this.isLoading = false;
    }
  }

  private buttons(): NavigationMenuItem[] {
    const buttons: NavigationMenuItem[] = [
      {
        value: '',
        symbolIcon: new SymbolGlyphModifier($r('sys.symbol.plus')),
        action: () => {
          // 进入添加账号模式
          PixState.isAddingAccount = true;
          this.pageStack.pushPathByName('login', null)
        }
      }
    ]
    return buttons;
  }

}

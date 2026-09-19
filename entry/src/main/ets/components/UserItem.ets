import { UserDetailParams } from "../common/entity/UserDetailEntity"
import { PixState } from "../entryability/AppState"
import { PixivUser } from "../services/PixivTypes"
import { createLogger } from "../common/utils/Logger"
import { toastUtil } from "../common/utils/ToastUtils"
import { PixivImageComponent } from "./PixivImage"
import { pixiv } from "../services/PixivService"
import { SymbolGlyphModifier } from "@kit.ArkUI"

const logger = createLogger('UserItem')

@ComponentV2
export struct UserItem {

  @Param @Require user: PixivUser
  @Param isFollow: boolean = false
  // 初始关注方式（仅 isFollow 为 true 时有意义）
  @Param isFollowPrivate: boolean = false

  // 本地镜像状态：PixivUser 为普通 interface，V2 不观察其嵌套属性，
  // 且列表场景 ForEach 同 key 复用组件不会回传参数，点击/菜单后的文案刷新必须依赖本地状态
  @Local followState: boolean = false
  @Local privateState: boolean = false
  @Local showFollowMenu: boolean = false

  @Event onButtonClick: (result: boolean, err?: string) => void
  // 关注方式（公开/私密）变化时通知父级，父级可不传
  @Event onRestrictChange: (isPrivate: boolean) => void

  aboutToAppear(): void {
    this.followState = this.isFollow
    this.privateState = this.isFollowPrivate
  }

  // 父级状态驱动时同步本地镜像（如插画详情页 iDV.isFollow、收藏后自动关注）；
  // Monitor 回调触发时参数已完成更新，直接读参数即可
  @Monitor('isFollow') onIsFollowParamChange() {
    this.followState = this.isFollow
  }

  @Monitor('isFollowPrivate') onIsPrivateParamChange() {
    this.privateState = this.isFollowPrivate
  }

  /** 关注操作成功后的本地收尾：共享对象同步 + 镜像状态 + 父级回调 */
  private applyFollowResult(result: boolean, isPrivate: boolean) {
    this.user.is_followed = result
    this.followState = result
    this.privateState = result && isPrivate
    this.onRestrictChange(this.privateState)
  }

  /** 关注（restrict: 'public' | 'private'，对已关注用户调用可切换公开/私密） */
  private async doFollow(restrict: 'public' | 'private') {
    if (!this.user.id) {
      toastUtil.showToast({ message: "用户ID不存在" })
      return
    }
    try {
      await pixiv.followUser(this.user.id, restrict)
      this.applyFollowResult(true, restrict === 'private')
      toastUtil.showToast({ message: $r('app.string.follow_success', this.user.name) })
      this.onButtonClick(true)
    } catch (err) {
      toastUtil.showToast({ message: $r('app.string.follow_fail') })
      logger.error(`!!! 关注操作失败: ${JSON.stringify(err)}`);
      this.onButtonClick(false, err.message)
    }
  }

  /** 取消关注 */
  private async doUnfollow() {
    if (!this.user.id) {
      toastUtil.showToast({ message: "用户ID不存在" })
      return
    }
    try {
      await pixiv.unfollowUser(this.user.id)
      this.applyFollowResult(false, false)
      toastUtil.showToast({ message: $r('app.string.unfollow_success', this.user.name) })
      this.onButtonClick(false)
    } catch (err) {
      toastUtil.showToast({ message: $r('app.string.unfollow_fail') })
      logger.error(`!!! 取关操作失败: ${JSON.stringify(err)}`);
      this.onButtonClick(true, err.message)
    }
  }

  /** 长按菜单：按当前关注状态给出可切换项 */
  @Builder
  FollowMenu() {
    Menu() {
      if (!this.followState) {
        // 未关注：私密关注 / 公开关注
        MenuItem({
          content: $r('app.string.follow_private'),
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.eye_slash')).fontColor([$r('sys.color.font_secondary')])
        })
          .onClick(() => {
            // 选中即收起：必须先关菜单再改数据，否则数据刷新引发菜单收起-展开-收起的闪烁
            this.showFollowMenu = false
            this.doFollow('private')
          })
        MenuItem({
          content: $r('app.string.follow_public'),
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.eye')).fontColor([$r('sys.color.font_secondary')])
        })
          .onClick(() => {
            this.showFollowMenu = false
            this.doFollow('public')
          })
      } else if (!this.privateState) {
        // 已关注（公开）：取消关注 / 私密关注
        MenuItem({
          content: $r('app.string.unfollow'),
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.xmark')).fontColor([$r('sys.color.font_secondary')])
        })
          .onClick(() => {
            this.showFollowMenu = false
            this.doUnfollow()
          })
        MenuItem({
          content: $r('app.string.follow_private'),
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.eye_slash')).fontColor([$r('sys.color.font_secondary')])
        })
          .onClick(() => {
            this.showFollowMenu = false
            this.doFollow('private')
          })
      } else {
        // 私密关注：公开关注 / 取消关注
        MenuItem({
          content: $r('app.string.follow_public'),
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.eye')).fontColor([$r('sys.color.font_secondary')])
        })
          .onClick(() => {
            this.showFollowMenu = false
            this.doFollow('public')
          })
        MenuItem({
          content: $r('app.string.unfollow'),
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.xmark')).fontColor([$r('sys.color.font_secondary')])
        })
          .onClick(() => {
            this.showFollowMenu = false
            this.doUnfollow()
          })
      }
    }
  }

  build() {
    // 头像 名称 关注
    Flex({ direction: FlexDirection.Row, alignItems: ItemAlign.Center }) {
      Row({ space: 5 }) {
        PixivImageComponent({
          imageUrl: this.user.profile_image_urls.medium,
          imageWidth: 50, imageHeight: 50,
          imageBorder: { radius: 50 }
        })
        Text(this.user.name)
          .fontSize(12)
          .maxLines(1)
      }
      .onClick(() => {
        this.push()
      })
      Blank().onClick(() => {
        this.push()
      })
      Button(this.followState ? (this.privateState ? $r('app.string.follow_private') : $r('app.string.followed')) : $r('app.string.follow'))
        .type(ButtonType.Normal)
        .fontSize(12)
        .height(28)
        .padding({ left: 12, right: 12 })
        .borderRadius(14)
        .fontColor(Color.White)
        .onClick(async () => {
          // 点击默认语义：未关注→公开关注；已关注（含私密）→取消关注
          if (this.followState) {
            await this.doUnfollow()
          } else {
            await this.doFollow('public')
          }
        })
        .gesture(
          LongPressGesture({ repeat: false, duration: 400 })
            .onAction(() => {
              this.showFollowMenu = true
            })
        )
        .bindMenu(this.showFollowMenu, this.FollowMenu(), {
          placement: Placement.Bottom,
          backgroundBlurStyle: BlurStyle.Thin,
          onDisappear: () => {
            this.showFollowMenu = false
          }
        })
    }
  }

  push() {
    const params: UserDetailParams = {
      id: this.user.id,
      user: this.user
    }
    // 跳转详情页
    PixState.pageStack.pushPathByName('user_detail', params, true);
  }

}
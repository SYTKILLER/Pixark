import { CustomItemInfo, ItemActionType, ItemGroupData, makeItemGroups, MenuOption,
  ThirdPartyLibInfo } from "../../common/entity/CusItemInfo"
import { CustomListItem } from "../../components/CusItemBuilder"
import { NaviContainer } from "../../components/NaviContainer"
import { PixState, _PixState } from "../../entryability/AppState"
import { JumpUtil } from "../../common/utils/JumpUtils"
import { toastUtil } from "../../common/utils/ToastUtils"
import { AppConstants } from "../../common/constants/AppConstants"
import UIConstants from '../../common/constants/UIConstants';

@Builder
export function AboutPageBuilder() {
  AboutPage()
}


@ComponentV2
struct AboutPage {

  private pageStack: NavPathStack = new NavPathStack()
  // 控制三方库弹窗显示
  @Local showLibsDialog: boolean = false

  // 三方库数据列表
  private get thirdPartyLibs(): ThirdPartyLibInfo[] {
    return [
      {
        name: 'Axios',
        packageName: '@ohos/axios',
        description: '基于 Axios v1.3.4 适配 HarmonyOS 的 Promise 网络请求库，支持请求/响应拦截器、自动 JSON 转换、请求取消、文件上传下载等特性。',
        license: 'MIT',
        url: 'https://ohpm.openharmony.cn/#/cn/detail/@ohos%2Faxios'
      },
      {
        name: 'ImageKnifePro',
        packageName: '@ohos/imageknifepro',
        description: '专为 OpenHarmony 打造的高性能图片加载缓存库，核心逻辑下沉至 C/C++ Native 层，支持内存+磁盘二级缓存、图片变换、占位图、自定义下载等。',
        license: 'Apache-2.0',
        url: 'https://ohpm.openharmony.cn/#/cn/detail/@ohos%2Fimageknifepro'
      },
      {
        name: 'reflect-metadata',
        packageName: 'reflect-metadata',
        description: 'ES7 元数据反射提案的 polyfill 实现，允许为类、方法、属性附加元数据并在运行时读取，常用于依赖注入、装饰器元信息等场景。',
        license: 'Apache-2.0',
        url: 'https://ohpm.openharmony.cn/#/cn/detail/reflect-metadata'
      }
    ]
  }

  private get itemList(): CustomItemInfo[] {
    return [
      // 基本信息组
      new CustomItemInfo({ id: 'info', title: $r('app.string.basic_info'), type: ItemActionType.GROUP }),
      new CustomItemInfo({
        symbol: $r('sys.symbol.info_circle'),
        title: $r('app.string.app_version'),
        type: ItemActionType.TEXT,
        id: 'app_version',
        value: _PixState.appVersion,
        onChange: () => {
          // TODO 点击版本号可以做一些彩蛋
        }
      }),
      new CustomItemInfo({
        symbol: $r('sys.symbol.parkingsign_circle_badge_a'),
        title: $r('app.string.project_intro'),
        subtitle: 'HarmonyOS 原生轻量级 Pixiv 第三方客户端',
        type: ItemActionType.ROUTER,
        id: 'project_intro',
        onChange: () => {
          toastUtil.showAlertDialog({
            title: $r('app.string.project_intro'),
            message: 'Pixark 是一款为 HarmonyOS 开发的原生轻量级 Pixiv 第三方客户端，旨在为鸿蒙用户提供原生流畅的插画浏览体验。',
            alignment: DialogAlignment.Center,
            primaryButton: { value: 'OK', action: () => {} }
          })
        }
      }),
      new CustomItemInfo({
        symbol: $r('sys.symbol.arrow_2_circlepath'),
        title: $r('app.string.check_update'),
        type: ItemActionType.ROUTER,
        id: 'check_update',
        subtitle: _PixState.appVersion,
        onChange: () => {
          // TODO: 检查更新逻辑
          toastUtil.showToast({ message: '正在检查更新...' })
        }
      }),

      // 链接组
      new CustomItemInfo({ id: 'links', title: $r('app.string.project'), type: ItemActionType.GROUP }),
      new CustomItemInfo({
        symbol: $r('sys.symbol.person'),
        title: $r('app.string.author_home'),
        type: ItemActionType.ROUTER,
        id: 'author_home',
        onChange: () => { JumpUtil.goToWeb(AppConstants.GITHUB_OWNER_URL) }
      }),
      new CustomItemInfo({
        symbol: $r('sys.symbol.star_circle'),
        title: $r('app.string.project_repo'),
        type: ItemActionType.ROUTER,
        id: 'project_repo',
        onChange: () => { JumpUtil.goToWeb(AppConstants.GITHUB_REPO_URL) }
      }),
      new CustomItemInfo({
        symbol: $r('sys.symbol.person_2'),
        title: $r('app.string.tripartite_services'),
        type: ItemActionType.ROUTER,
        id: 'tripartite_services',
        onChange: () => {
          this.showLibsDialog = true
        }
      }),

      // 贡献者组
      new CustomItemInfo({ id: 'contributors', title: $r('app.string.contributors'), type: ItemActionType.GROUP }),
      new CustomItemInfo({
        icon: $rawfile('ya.jfif'),
        title: 'XHXYT',
        subtitle: $r('app.string.project_maintenance'),
        type: ItemActionType.ROUTER,
        id: 'contributor_xhxyt',
        onChange: () => { JumpUtil.goToWeb(AppConstants.GITHUB_OWNER_URL) }
      }),
      new CustomItemInfo({
        icon: $rawfile('March.png'),
        title: 'March',
        subtitle: $r('app.string.project_maintenance'),
        type: ItemActionType.ROUTER,
        id: 'contributor_march',
        onChange: () => { JumpUtil.goToWeb('https://github.com/SYTKILLER') }
      }),
      new CustomItemInfo({
        icon: $rawfile('kelan_kl.png'),
        title: 'kelanKL',
        subtitle: $r('app.string.icon_drawing'),
        type: ItemActionType.ROUTER,
        id: 'contributor_kelan_kl',
        onChange: () => { JumpUtil.goToWeb('https://github.com/kelanKL') }
      }),
      new CustomItemInfo({
        icon: $rawfile('liluolinder.jfif'),
        title: 'linderSeline',
        subtitle: $r('app.string.project_maintenance'),
        type: ItemActionType.ROUTER,
        id: 'contributor_liluolinder',
        onChange: () => { JumpUtil.goToWeb('https://github.com/liluolinder') }
      }),
      new CustomItemInfo({
        icon: $rawfile('summer_kaze.jfif'),
        title: 'SummerKaze',
        subtitle: $r('app.string.project_maintenance'),
        type: ItemActionType.ROUTER,
        id: 'contributor_summer_kaze',
        onChange: () => { JumpUtil.goToWeb('https://github.com/SummerKaze') }
      }),
      new CustomItemInfo({
        icon: $rawfile('crazypig321.jfif'),
        title: 'crazypig321',
        subtitle: $r('app.string.project_maintenance'),
        type: ItemActionType.ROUTER,
        id: 'contributor_crazypig321',
        onChange: () => { JumpUtil.goToWeb('https://github.com/crazypig321') }
      }),
      // 致谢组
      new CustomItemInfo({ id: 'thanks', title: $r('app.string.thanks'), type: ItemActionType.GROUP }),
      new CustomItemInfo({
        icon: $rawfile('pixez_flutter.png'),
        title: 'Pixez-Flutter',
        subtitle: '优秀开源项目，架构与业务设计参考',
        type: ItemActionType.ROUTER,
        id: 'thanks_pixez_flutter',
        onChange: () => { JumpUtil.goToWeb('https://github.com/Notsfsssf/pixez-flutter') }
      }),
      new CustomItemInfo({
        icon: $rawfile('pixivpy.png'),
        title: 'PixivPy',
        subtitle: 'API协议与签名逻辑参考',
        type: ItemActionType.ROUTER,
        id: 'thanks_pixivpy',
        onChange: () => { JumpUtil.goToWeb('https://github.com/upbit/pixivpy') }
      }),

      // 法律声明组
      new CustomItemInfo({ id: 'legal', title: $r('app.string.legal'), type: ItemActionType.GROUP }),
      new CustomItemInfo({
        symbol: $r('sys.symbol.doc_text_fill'),
        title: $r('app.string.open_source_license'),
        subtitle: 'GPL-3.0',
        type: ItemActionType.ROUTER,
        id: 'license',
        onChange: () => {
          toastUtil.showAlertDialog({
            title: $r('app.string.open_source_license'),
            message: '本项目基于 GNU General Public License v3.0 开源，你可自由使用、修改和分发，但衍生作品需以相同协议开源。',
            alignment: DialogAlignment.Center,
            primaryButton: { value: 'OK', action: () => {} }
          })
        }
      }),
      new CustomItemInfo({
        symbol: $r('sys.symbol.exclamationmark_shield_fill'),
        title: $r('app.string.disclaimer'),
        type: ItemActionType.ROUTER,
        id: 'disclaimer',
        onChange: () => {
          toastUtil.showAlertDialog({
            title: $r('app.string.disclaimer'),
            message: 'Pixark 是非官方第三方客户端，与 Pixiv Inc. 无任何从属关系。本项目仅供学习交流，请勿用于商业用途。使用本软件所产生的一切风险与责任由使用者自行承担，请遵守 Pixiv 官方服务条款及相关法律法规。',
            alignment: DialogAlignment.Center,
            primaryButton: { value: 'OK', action: () => {} }
          })
        }
      })
    ]
  }

  build() {
    NaviContainer({
      title: $r('app.string.about'),
      content: () => { this.Content() },
      onReady: (ctx) => { this.pageStack = ctx.pathStack },
      onBackPressed: () => false,
      onNaviDisAppear: () => {}
    })
  }

  @Builder
  Content() {
    Column() {
      List({ space: 16 }) {
        // 顶部应用图标 Header
        ListItem() {
          this.AppHeader()
        }
        // 渲染分组列表
        ForEach(makeItemGroups(this.itemList), (group: ItemGroupData) => {
          ListItemGroup({ header: group.group?.title ? this.GroupHeader(group.group.title) : undefined }) {
            ForEach(group.items, (item: CustomItemInfo) => {
              ListItem() {
                CustomListItem({ item: item, itemPadding: { left: 16, right: 16, top: 12, bottom: 12 } })
              }
            })
          }
          .backgroundColor($r('app.color.card_bg'))
          .borderRadius(UIConstants.RADIUS_CARD)
        })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .contentEndOffset(PixState.bottomRectHeight || 28)
    }
    .width('100%')
    .height('100%')
    .padding({ left: PixState.PageMarginValue, right: PixState.PageMarginValue })
    .bindSheet(this.showLibsDialog!!, this.ThirdPartyLibsSheet(), {
      height: '60%',
      dragBar: true,
      showClose: false,
    })
  }

  /**
   * 顶部应用图标与名称
   */
  @Builder
  AppHeader() {
    Column({ space: 12 }) {
      Image($r('app.media.app_icon'))
        .width(80)
        .height(80)
        .borderRadius(20)
        .margin({ top: 12 })

      Image($r('app.media.pixark_art'))
        .width(186)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ top: 16, bottom: 16 })
  }

  /**
   * 分组标题
   */
  @Builder
  GroupHeader(title: ResourceStr) {
    Text(title)
      .fontSize(14)
      .width('100%')
      .padding({ left: 4, top: 8, bottom: 4 })
      .fontColor($r('sys.color.font_secondary'))
  }

  @Builder ThirdPartyLibsSheet() {
    Column() {
      // 顶部标题
      Row() {
        Text($r('app.string.tripartite_services'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
          .fontColor($r('sys.color.font_primary'))
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(16)
            .fontColor([$r('sys.color.font_secondary')])
        }
        .width(32).height(32)
        .backgroundColor(Color.Transparent)
        .onClick(() => { this.showLibsDialog = false })
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 12, top: 12 })

      // 库列表
      Scroll() {
        Column({ space: 12 }) {
          ForEach(this.thirdPartyLibs, (lib: ThirdPartyLibInfo, index: number) => {
            this.LibCard(lib, index)
          }, (lib: ThirdPartyLibInfo) => lib.packageName)
          // 底部说明
          Text('感谢以上开源项目对 HarmonyOS 生态的贡献')
            .fontSize(12)
            .fontColor($r('sys.color.font_fourth'))
            .width('100%')
            .textAlign(TextAlign.Center)
            .margin({ top: 8, bottom: 16 })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: PixState.bottomRectHeight + 16 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_primary'))
  }

  /**
   * 单个三方库卡片
   */
  @Builder LibCard(lib: ThirdPartyLibInfo, index: number) {
    Column({ space: 8 }) {
      // 库名 + 协议标签
      Row() {
        Text(lib.name)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
        Text(lib.license)
          .fontSize(11)
          .fontColor($r('sys.color.font_tertiary'))
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(4)
          .backgroundColor($r('sys.color.ohos_id_color_hover'))
          .margin({ left: 8 })
        Blank()
        // 序号
        Text(`${index + 1}`)
          .fontSize(12)
          .fontColor($r('sys.color.font_fourth'))
      }
      .width('100%')

      // 包名
      Row({ space: 4 }) {
        SymbolGlyph($r('sys.symbol.archivebox_fill'))
          .fontSize(13)
          .fontColor([$r('sys.color.font_tertiary')])
        Text(lib.packageName)
          .fontSize(13)
          .fontColor($r('sys.color.font_tertiary'))
          .fontFamily('monospace')
      }
      .width('100%')

      // 简介
      Text(lib.description)
        .fontSize(13)
        .lineHeight(20)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')

      // 仓库链接按钮
      Row() {
        Button({ type: ButtonType.Normal }) {
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.link'))
              .fontSize(13)
              .fontColor([Color.White])
            Text($r('app.string.view_repo'))
              .fontSize(13)
              .fontColor(Color.White)
          }
        }
        .height(32)
        .borderRadius(16)
        .padding({ left: 16, right: 16 })
        .backgroundColor(PixState.currentThemeColor)
        .onClick(() => { JumpUtil.goToWeb(lib.url) })
        Blank()
      }
      .width('100%')
      .margin({ top: 4 })
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor($r('app.color.card_bg'))
  }

}

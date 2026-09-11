import UIConstants from "../common/constants/UIConstants";
import { PixState } from "../entryability/AppState";

/**
 * 通用空态视图：图标 + 文案 + 可选操作按钮
 */
@ComponentV2
export struct EmptyStateView {
  @Param icon: Resource = $r('sys.symbol.square_and_pencil')
  @Param message: ResourceStr = ''
  @Param actionText: ResourceStr | undefined = undefined
  @Event onAction: () => void = () => {}

  build() {
    Column() {
      SymbolGlyph(this.icon)
        .fontSize(56)
        .fontColor([$r('sys.color.font_fourth')])
      Text(this.message)
        .fontSize(15)
        .fontColor($r('sys.color.font_secondary'))
        .textAlign(TextAlign.Center)
        .margin({ top: 16 })
        .padding({ left: 32, right: 32 })
      if (this.actionText) {
        Button(this.actionText)
          .type(ButtonType.Capsule)
          .width(140)
          .height(40)
          .fontSize(15)
          .backgroundColor(PixState.currentThemeColor)
          .margin({ top: 24 })
          .onClick(() => this.onAction())
      }
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ top: 48, bottom: 48 })
  }
}

/**
 * 通用胶囊标签：排行模式 / 搜索标签共用
 */
@ComponentV2
export struct Chip {
  @Param label: ResourceStr = ''
  @Param selected: boolean = false
  @Event onChipClick: () => void = () => {}

  build() {
    Text(this.label)
      .fontSize(14)
      .fontColor(this.selected ? Color.White : $r('sys.color.font_secondary'))
      .fontWeight(this.selected ? FontWeight.Medium : FontWeight.Normal)
      .lineHeight(18)
      .padding({ left: 16, right: 16, top: 7, bottom: 7 })
      .borderRadius(UIConstants.RADIUS_PILL)
      .backgroundColor(this.selected ? PixState.currentThemeColor : $r('sys.color.button_background_color_transparent'))
      .border({
        width: 1,
        color: this.selected ? PixState.currentThemeColor : $r('sys.color.comp_divider')
      })
      .animation({ duration: 250, curve: Curve.Ease })
      .onClick(() => this.onChipClick())
  }
}

/**
 * 通用编辑模式悬浮底栏（下载管理 / 浏览历史共用）
 * 毛玻璃悬浮胶囊：全选 + 已选计数 + 删除
 */
@ComponentV2
export struct EditBottomBar {
  @Param selectedCount: number = 0
  @Param totalCount: number = 0
  @Param allSelected: boolean = false
  @Event onSelectAll: (selected: boolean) => void = () => {}
  @Event onDelete: () => void = () => {}

  build() {
    Row({ space: 12 }) {
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
          .fontSize(22)
          .fontColor([this.allSelected ? PixState.currentThemeColor : $r('sys.color.font_tertiary')])
          .animation({ duration: 200, curve: Curve.Ease })
        Text('全选')
          .fontSize(14)
          .fontColor($r('sys.color.font_primary'))
      }
      .padding({ left: 8, right: 8, top: 8, bottom: 8 })
      .borderRadius(UIConstants.RADIUS_ITEM)
      .onClick(() => this.onSelectAll(!this.allSelected))

      Blank()

      Text(`已选 ${this.selectedCount} 项`)
        .fontSize(13)
        .fontColor($r('sys.color.font_secondary'))

      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.trash_fill'))
          .fontSize(18)
          .fontColor([Color.Red])
        Text('删除')
          .fontSize(14)
          .fontColor(Color.Red)
          .fontWeight(FontWeight.Medium)
      }
      .padding({ left: 16, right: 16, top: 9, bottom: 9 })
      .borderRadius(UIConstants.RADIUS_PILL)
      .backgroundColor('#14FF3B30')
      .opacity(this.selectedCount > 0 ? 1 : 0.4)
      .animation({ duration: 200, curve: Curve.Ease })
      .onClick(() => {
        if (this.selectedCount > 0) {
          this.onDelete()
        }
      })
    }
    .width('auto')
    .alignItems(VerticalAlign.Center)
    .padding({ left: 12, right: 8, top: 8, bottom: 8 })
    .margin({
      left: 16,
      right: 16,
      bottom: PixState.bottomRectHeight + 12
    })
    .borderRadius(28)
    .backgroundBlurStyle(BlurStyle.Thin, {
      colorMode: ThemeColorMode.SYSTEM,
      adaptiveColor: AdaptiveColor.DEFAULT
    })
    .border({ width: 0.5, color: $r('sys.color.comp_divider') })
    .shadow({ radius: 24, color: '#1A000000', offsetY: 4 })
  }
}

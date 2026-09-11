import { NaviContainer } from "../../components/NaviContainer"
import { SymbolGlyphModifier } from "@kit.ArkUI"
import { toastUtil } from "../../common/utils/ToastUtils"
import { appSettings } from "../../common/entity/SettingsModel"
import { FunctionConstants } from "../../common/constants/FunctionConstants";
import { SavePlaceholderItem } from "../../common/entity/PlaceholderItem";
import { PixState } from "../../entryability/AppState";

@Builder
export function SaveFormatBuilder() {
  SaveFormat()
}

@ComponentV2
struct SaveFormat {

  private pageStack: NavPathStack = new NavPathStack()

  // 使用本地状态暂存编辑中的格式，避免直接修改全局设置导致未点保存就生效
  @Local tempFormat: string = appSettings.file_name || FunctionConstants.DEFAULT_SAVE_FORMAT;

  // 变量说明表数据源
  private placeholderList: SavePlaceholderItem[] = [
    { tag: '{illust_id}', desc: $r('app.string.illust_id_desc'), example: '12345678' },
    { tag: '{part}', desc: $r('app.string.part_desc'), example: '0, 1' },
    { tag: '{title}', desc: $r('app.string.title_desc'), example: $r('app.string.title_example') },
    { tag: '{user_name}', desc: $r('app.string.user_name_desc'), example: $r('app.string.user_name_example') },
    { tag: '{uid}', desc: $r('app.string.uid_desc'), example: '9876543' },
    { tag: '_', desc: $r('app.string.underline_desc'), example: '_' },
    { tag: 'p', desc: $r('app.string.part_type_desc'), example: 'p' }
  ];

  build() {
    NaviContainer({
      title: $r('app.string.file_save_format'),
      content: () => {
        this.Content()
      },
      buttons: this.buttons(),
      onReady: (ctx) => {
        this.pageStack = ctx.pathStack
      },
      onBackPressed: () => {
        return false
      },
      onNaviDisAppear: () => { }
    })
  }

  private buttons(): NavigationMenuItem[] {
    const btns: NavigationMenuItem[] = [
      {
        value: '',
        symbolIcon: new SymbolGlyphModifier($r('sys.symbol.arrow_2_circlepath')),
        action: () => {
          // 恢复默认格式
          this.tempFormat = FunctionConstants.DEFAULT_SAVE_FORMAT;
        }
      }
    ];
    btns.push({
      value: '',
      symbolIcon: new SymbolGlyphModifier($r('sys.symbol.save')),
      action: () => {
        // 保存格式到持久化
        appSettings.file_name = this.tempFormat.trim() || FunctionConstants.DEFAULT_SAVE_FORMAT;
        appSettings.save();
        toastUtil.showToast({ message: $r('app.string.success_save') });
      }
    });
    return btns;
  }

  // 实时预览生成器
  private getPreview(): string {
    return this.tempFormat
      .replace(/{illust_id}/g, '12345678')
      .replace(/{part}/g, '0')
      .replace(/{title}/g, '阳光沙滩')
      .replace(/{user_name}/g, '小可爱')
      .replace(/{uid}/g, '9876543') + '.jpg';
  }

  @Builder
  Content() {
    List({ space: 16 }) {
      // 格式输入区
      ListItem() {
        Column({ space: 8 }) {
          Text($r('app.string.file_name_format'))
            .fontSize(14)
            .width('100%')
            .fontColor($r('sys.color.font_secondary'))

          TextInput({ text: $$this.tempFormat, placeholder: $r('app.string.save_format_placeholder') })
            .type(InputType.Normal)
            .width('100%')
            .height(48)
            .borderRadius(8)
            .onChange((value: string) => {
              this.tempFormat = value;
            })
        }.width('100%')
      }

      // 实时预览区
      ListItem() {
        Column({ space: 8 }) {
          Text($r('app.string.preview_effect'))
            .fontSize(14)
            .width('100%')
            .fontColor($r('sys.color.font_secondary'))

          Text(this.getPreview())
            .fontSize(16)
            .fontColor(PixState.currentThemeColor)
            .fontWeight(FontWeight.Bold)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        .width('100%')
        .padding(16)
        .borderRadius(16)
        .backgroundColor($r('app.color.card_bg'))
        .border({
          width: 1,
          color: $r('app.color.brand_weak'),
          style: BorderStyle.Dashed
        })
        .margin({ top: 16, bottom: 16 })
      }

      // 变量说明表
      ListItem() {
        Column({ space: 12 }) {
          Text($r('app.string.available_variables'))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .width('100%')
            .margin({ top: 8 })

          // 表头
          Row() {
            Text($r('app.string.placeholder'))
              .fontColor($r('sys.color.font_secondary'))
              .fontSize(13)
              .width('40%')

            Text($r('app.string.description'))
              .fontSize(13)
              .layoutWeight(1)
              .fontColor($r('sys.color.font_secondary'))

            Text($r('app.string.example'))
              .fontSize(13)
              .width('25%')
              .textAlign(TextAlign.End)
              .fontColor($r('sys.color.font_secondary'))
          }
          .width('100%')

          Divider().color($r('sys.color.comp_divider'))

          // 列表内容
          ForEach(this.placeholderList, (item: SavePlaceholderItem) => {
            Row() {
              Text(item.tag)
                .fontSize(14)
                .fontColor($r('sys.color.ohos_id_color_emphasize'))
                .fontFamily('monospace')
                .width('40%')

              Text(item.desc)
                .fontSize(14)
                .layoutWeight(1)
                .fontColor($r('sys.color.font_secondary'))

              Text(item.example)
                .fontSize(13)
                .width('25%')
                .textAlign(TextAlign.End)
                .fontColor($r('sys.color.font_tertiary'))
            }
            .width('100%')
            .borderRadius(8)
            .padding(12)
            .backgroundColor($r('sys.color.button_background_color_transparent'))
            .onClick(() => {
              // 点击将变量追加到输入框
              this.tempFormat += item.tag;
            })
          }, (item: SavePlaceholderItem) => item.tag)
        }
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .contentStartOffset(16)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .padding({ left: PixState.PageMarginValue, right: PixState.PageMarginValue })
  }

}

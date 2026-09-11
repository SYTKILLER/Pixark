import { curves } from '@kit.ArkUI';
import { PixState } from "../entryability/AppState";
import { PixivImageComponent } from "./PixivImage";
import { PixivImage } from '../services/PixivTypes';
import { appSettings } from '../common/entity/SettingsModel';
import { ImageUtils } from '../common/utils/ImageUtils';

const MAX_SCALE = 5;
const MIN_SCALE = 0.5;
const DOUBLE_TAP_SCALE = 2.5;
const DISMISS_THRESHOLD = 120;
// 单击 vs 双击判定延时
const TAP_TIMEOUT = 280;

// 悬浮栏胶囊圆角
const UI_RADIUS = 28;

/** 可缩放单图：双指缩放 / 双击放大 / 放大拖动 / 1x 下滑关闭（官方《图片预览器》最佳实践） */
@ComponentV2
struct ZoomableImage {
  @Param imageUrl: string = ''
  @Event onSingleTap: () => void = () => {}
  @Event onDismiss: () => void = () => {}
  @Event onDragProgress: (progress: number) => void = () => {}
  @Event onZoomChanged: (zoomed: boolean) => void = () => {}

  // 缩放与平移状态（.translate 与 .scale 属性组合：平移量在父坐标空间）
  @Local imgScale: number = 1
  @Local offsetX: number = 0
  @Local offsetY: number = 0
  // 下滑关闭跟手状态
  @Local dragY: number = 0
  @Local dragScale: number = 1
  // 组件区域尺寸（vp）
  private areaW: number = 0
  private areaH: number = 0
  private pinchStartScale: number = 1
  private pinchStartOffsetX: number = 0
  private pinchStartOffsetY: number = 0
  private panStartOffsetX: number = 0
  private panStartOffsetY: number = 0
  private singleTapTimer: number = -1

  aboutToDisappear(): void {
    if (this.singleTapTimer >= 0) {
      clearTimeout(this.singleTapTimer)
    }
  }

  private clampBound(v: number, min: number, max: number): number {
    return Math.min(max, Math.max(min, v))
  }

  private clampOffset(value: number, axisIsX: boolean): number {
    const area = axisIsX ? this.areaW : this.areaH
    const max = Math.max(0, (area * this.imgScale - area) / 2)
    return this.clampBound(value, -max, max)
  }

  private toggleZoom() {
    const zoomed = this.imgScale > 1.01
    this.getUIContext().animateTo({ duration: 280, curve: curves.springMotion(0.42, 0.8) }, () => {
      if (zoomed) {
        this.imgScale = 1
        this.offsetX = 0
        this.offsetY = 0
      } else {
        this.imgScale = DOUBLE_TAP_SCALE
        this.offsetX = 0
        this.offsetY = 0
      }
    })
    this.onZoomChanged(!zoomed)
  }

  build() {
    Stack() {
      PixivImageComponent({
        imageUrl: this.imageUrl,
        imageObjectFit: ImageFit.Contain,
        imageWidth: '100%',
        imageHeight: '100%',
        needMask: false
      })
    }
    .width('100%')
    .height('100%')
    .scale({ x: this.imgScale * this.dragScale, y: this.imgScale * this.dragScale })
    .translate({ x: this.offsetX, y: this.offsetY + this.dragY })
    .onAreaChange((_old: Area, newArea: Area) => {
      this.areaW = newArea.width as number
      this.areaH = newArea.height as number
    })
    // 单击：延时触发，等待双击判定（双击识别成功时单击手势自动竞争失败）
    .gesture(TapGesture({ count: 1 })
      .onAction(() => {
        if (this.singleTapTimer >= 0) {
          clearTimeout(this.singleTapTimer)
        }
        this.singleTapTimer = setTimeout(() => {
          this.singleTapTimer = -1
          this.onSingleTap()
        }, TAP_TIMEOUT)
      }))
    .gesture(TapGesture({ count: 2 })
      .onAction(() => {
        if (this.singleTapTimer >= 0) {
          clearTimeout(this.singleTapTimer)
          this.singleTapTimer = -1
        }
        this.toggleZoom()
      }))
    // 未放大时仅接管纵向手势（下拉关闭），横向让给外层 Swiper 翻页；放大后全向接管自由拖动
    .gesture(PanGesture({ fingers: 1, direction: this.imgScale > 1.01 ? PanDirection.All : PanDirection.Vertical, distance: 5 })
      .onActionStart((event: GestureEvent) => {
        this.pinchStartOffsetX = this.offsetX
        this.pinchStartOffsetY = this.offsetY
        this.panStartOffsetX = this.offsetX
        this.panStartOffsetY = this.offsetY
      })
      .onActionUpdate((event: GestureEvent) => {
        if (this.imgScale > 1.01) {
          // 放大态：自由拖动并限制边界
          this.offsetX = this.clampOffset(this.panStartOffsetX + event.offsetX, true)
          this.offsetY = this.clampOffset(this.panStartOffsetY + event.offsetY, false)
        } else {
          // 1x 态：仅响应下拉关闭
          const dy = event.offsetY
          if (dy > 0) {
            this.dragY = dy
            this.dragScale = Math.max(0.92, 1 - dy / 1500)
            this.onDragProgress(this.clampBound(dy / 300, 0, 1))
          }
        }
      })
      .onActionEnd((event: GestureEvent) => {
        if (this.imgScale > 1.01) {
          return
        }
        if (this.dragY > DISMISS_THRESHOLD) {
          this.onDismiss()
          this.dragY = 0
          this.dragScale = 1
          this.onDragProgress(0)
        } else {
          this.getUIContext().animateTo({ duration: 250, curve: curves.springMotion(0.42, 0.8) }, () => {
            this.dragY = 0
            this.dragScale = 1
          })
          this.onDragProgress(0)
        }
      }))
    .gesture(PinchGesture({ fingers: 2 })
      .onActionStart((event: GestureEvent) => {
        this.pinchStartScale = this.imgScale
        this.pinchStartOffsetX = this.offsetX
        this.pinchStartOffsetY = this.offsetY
      })
      .onActionUpdate((event: GestureEvent) => {
        if (event.scale <= 0) return
        const newScale = this.clampBound(this.pinchStartScale * event.scale, MIN_SCALE, MAX_SCALE)
        // 以双指中心为焦点缩放：保持焦点下的内容点不动
        const fx = event.pinchCenterX - this.areaW / 2
        const fy = event.pinchCenterY - this.areaH / 2
        const k = newScale / this.pinchStartScale
        this.offsetX = fx - (fx - this.pinchStartOffsetX) * k
        this.offsetY = fy - (fy - this.pinchStartOffsetY) * k
        this.imgScale = newScale
        if (newScale <= 1.001) {
          this.offsetX = 0
          this.offsetY = 0
        }
        this.onZoomChanged(newScale > 1.01)
      })
      .onActionEnd((event: GestureEvent) => {
        if (this.imgScale <= 1.001) {
          this.getUIContext().animateTo({ duration: 250, curve: curves.springMotion(0.42, 0.8) }, () => {
            this.imgScale = 1
            this.offsetX = 0
            this.offsetY = 0
          })
          this.onZoomChanged(false)
        } else if (this.imgScale < 1.2) {
          // 接近 1x 时回弹归位，避免残留微小缩放
          this.getUIContext().animateTo({ duration: 250, curve: curves.springMotion(0.42, 0.8) }, () => {
            this.imgScale = 1
            this.offsetX = 0
            this.offsetY = 0
          })
          this.onZoomChanged(false)
        }
      }))
  }
}

/** 全屏看图器：Swiper 翻页 + 悬浮毛玻璃顶栏/工具栏 */
@ComponentV2
export struct PixivImageViewer {
  // 图片URL列表 (保持接收完整的 PixivImage 对象)
  @Param imageUrls: PixivImage[] = [];
  // 初始索引
  @Param startIndex: number = 0;
  // 当前作品是否已收藏
  @Param bookmarked: boolean = false;
  // 当前索引 (用于显示页码)
  @Local currentIndex: number = 0;
  // 顶栏/工具栏显隐
  @Local barsVisible: boolean = true;
  // 放大态禁用翻页
  @Local imageZoomed: boolean = false;
  // 背景透明度（下拉跟手渐隐）
  @Local bgOpacity: number = 1;
  // 按钮弹跳动效触发器
  @Local bookmarkBounce: number = 0;
  @Local downloadBounce: number = 0;
  @Local shareBounce: number = 0;

  private swiperController: SwiperController = new SwiperController();

  // 事件：关闭查看器
  @Event onClose: () => void = () => {};
  // 事件：下载当前图片
  @Event onDownload: (index: number) => void = () => {};
  // 事件：分享当前图片
  @Event onShare: (url: string, index: number) => void = () => {};
  // 事件：收藏/取消收藏当前作品
  @Event onBookmark: (index: number) => void = () => {};

  aboutToAppear(): void {
    this.currentIndex = this.startIndex;
  }

  private toggleBars() {
    this.barsVisible = !this.barsVisible
  }

  @Builder
  BarButton(icon: Resource, bounce: number, action: () => void, activeColor?: ResourceColor) {
    Row() {
      SymbolGlyph(icon)
        .fontSize(24)
        .fontColor([activeColor ?? Color.White])
        .symbolShadow({ radius: 8, color: '#66000000' })
        .symbolEffect(new BounceSymbolEffect(EffectScope.WHOLE), bounce)
    }
    .width(48)
    .height(48)
    .borderRadius(24)
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#1AFFFFFF')
    .onClick(() => {
      action()
    })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 黑色背景（下拉关闭时跟手渐隐）
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Black)
        .opacity(this.bgOpacity)

      // Swiper 图片浏览区
      Swiper(this.swiperController) {
        ForEach(this.imageUrls, (image: PixivImage, index: number) => {
          ZoomableImage({
            imageUrl: ImageUtils.getImageUrlByQuality(image, appSettings.image_view_quality),
            onSingleTap: () => {
              this.toggleBars()
            },
            onDismiss: () => {
              this.onClose()
            },
            onDragProgress: (progress: number) => {
              this.bgOpacity = 1 - progress * 0.9
            },
            onZoomChanged: (zoomed: boolean) => {
              this.imageZoomed = zoomed
              if (zoomed) {
                this.barsVisible = false
              }
            }
          })
        }, (image: PixivImage, index: number): string => `${index}_${image.medium}`)
      }
      .index(this.startIndex)
      .loop(false)
      .indicator(false)
      .cachedCount(1)
      .disableSwipe(this.imageZoomed)
      .onChange((index) => {
        this.currentIndex = index;
      })
      .width('100%')
      .height('100%')

      // 顶栏 + 底部工具栏覆盖层（不拦截图片区点击）
      Column() {
        // 顶部悬浮栏：关闭 + 页码
        Row({ space: 12 }) {
          this.BarButton($r('sys.symbol.chevron_left'), 0, (): void => {
            this.onClose()
          })
          Blank()
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.shutter_photo'))
              .fontSize(16)
              .fontColor([Color.White])
            Text(`${this.currentIndex + 1} / ${this.imageUrls.length}`)
              .fontSize(14)
              .fontColor(Color.White)
              .fontWeight(FontWeight.Medium)
          }
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .borderRadius(UI_RADIUS)
          .backgroundColor('#33000000')
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: PixState.topRectHeight + 12 })
        .opacity(this.barsVisible ? 1 : 0)
        .translate({ y: this.barsVisible ? 0 : -16 })
        .visibility(this.barsVisible ? Visibility.Visible : Visibility.Hidden)
        .animation({ duration: 250, curve: Curve.Ease })

        Blank()

        // 底部悬浮工具栏：收藏 / 下载 / 分享
        Row({ space: 28 }) {
          this.BarButton(this.bookmarked ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'),
            this.bookmarkBounce, (): void => {
              this.bookmarkBounce++
              this.onBookmark(this.currentIndex)
            }, this.bookmarked ? '#FF3B30' : undefined)
          this.BarButton($r('sys.symbol.circle_and_arrow_down'), this.downloadBounce, (): void => {
            this.downloadBounce++
            this.onDownload(this.currentIndex)
          })
          this.BarButton($r('sys.symbol.share'), this.shareBounce, (): void => {
            this.shareBounce++
            const image = this.imageUrls[this.currentIndex]
            // 分享的链接也跟随当前展示的质量设置
            const currentUrl = ImageUtils.getImageUrlByQuality(image, appSettings.image_view_quality);
            this.onShare(currentUrl, this.currentIndex)
          })
        }
        .padding({ left: 20, right: 20, top: 8, bottom: 8 })
        .margin({ bottom: PixState.bottomRectHeight + 16 })
        .borderRadius(UI_RADIUS)
        .backgroundBlurStyle(BlurStyle.Thin, {
          colorMode: ThemeColorMode.DARK,
          adaptiveColor: AdaptiveColor.DEFAULT
        })
        .backgroundColor('#33000000')
        .border({ width: 0.5, color: '#33FFFFFF' })
        .opacity(this.barsVisible ? 1 : 0)
        .translate({ y: this.barsVisible ? 0 : 24 })
        .visibility(this.barsVisible ? Visibility.Visible : Visibility.Hidden)
        .animation({ duration: 250, curve: Curve.Ease })
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height('100%')
  }
}

import { curves } from '@kit.ArkUI'

class Animation {

  ctx: UIContext | undefined

  // 模式切换进行中才播转场；平时组件挂载（如页签滑动首次构建）不播
  private modeSwitching: boolean = false

  init(UIContext: UIContext) {
    this.ctx = UIContext
  }

  public isTranslate() {
    const effectEvent = TransitionEffect.OPACITY
      .animation({ duration: 300, delay: 0 })
      .combine(TransitionEffect.translate({ y: 50 }))
    return effectEvent
  }

  // 图片/小说模式切换的内容转场：与搜索页列表切换一致——新视图上滑淡入，旧视图立即消失
  public modeSwitchTransition() {
    if (!this.modeSwitching) {
      return TransitionEffect.IDENTITY
    }
    return TransitionEffect.asymmetric(
      TransitionEffect.OPACITY
        .combine(TransitionEffect.translate({ y: 100 })),
      TransitionEffect.OPACITY.animation({ duration: 0 })
    )
  }

  // 模式切换入口：切换窗口期内 modeSwitchTransition 生效
  public switchModeAnimate(v: () => void) {
    if (!this.ctx) {
      console.error('switchModeAnimate UIContext未初始化')
      v()
      return
    }
    this.modeSwitching = true
    this.ctx.animateTo({ curve: curves.interpolatingSpring(0, 1, 342, 38) }, () => {
      v()
    })
    // 弹簧曲线无固定时长，给足窗口后复位，避免影响后续普通挂载
    setTimeout(() => {
      this.modeSwitching = false
    }, 1000)
  }

  public animTo(v: () => void, time: number = 300, witchOne?: 'default' | 'app' , d?: number, curve?: string | Curve | ICurve){
    if (this.ctx) {
      if (witchOne === 'app') {
        this.ctx.animateTo(this.animNormalApp(time, d ?? 0, curve ?? Curve.EaseOut),()=> {
          v()
        })
      } else {
        this.ctx.animateTo(this.animNormal(d ?? 0),()=> {
          v()
        })
      }
    } else {
      console.error('animTo UIContext未初始化')
    }
  }

  // 普通动画参数,根据软件选择参数
  public animNormalApp(time: number, d: number, curve?: string | Curve | ICurve) {
    const animationUtils: AnimateParam = {
      duration: time,
      curve: curve, // Curve.EaseOut,
      iterations: 1,
      playMode: PlayMode.Normal,
      delay:d
    }
    return animationUtils
  }

  // 普通动画参数
  public animNormal(d: number) {
    const animation: AnimateParam = {
      duration: 300,
      curve: Curve.EaseOut,
      iterations: 1,
      playMode: PlayMode.Normal,
      delay:d
    }
    return animation
  }

}

export const animation = new Animation()
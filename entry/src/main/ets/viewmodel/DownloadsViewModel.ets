import { request } from "@kit.BasicServicesKit";
import { common } from '@kit.AbilityKit';
import { fileUri, fileIo as fs } from "@kit.CoreFileKit";
import { getDownloadRecordTable } from "../common/utils/database/impl/DownloadRecordTable";
import DownloadRecordInfo from "../common/entity/DownloadRecordInfo";
import { PixivIllust } from "../services/PixivTypes";
import { createLogger } from "../common/utils/Logger";
import { photoAccessHelper } from "@kit.MediaLibraryKit";
import { toastUtil } from "../common/utils/ToastUtils";
import { appSettings } from "../common/entity/SettingsModel";

const logger = createLogger('DownloadsViewModel')

/** 保存到系统相册的文件条目 */
interface GallerySaveItem {
  filePath: string;
  title: string;
}

@ObservedV2
export class DownloadsViewModel {

  @Trace selectedIds: Set<string> = new Set()

  @Trace displayList: DownloadRecordInfo[] = []
  @Trace tasks: DownloadRecordInfo[] = []

  @Trace isEditMode: boolean = false
  @Trace currentPage: number = 0

  private downloadDir = ""
  private context: common.Context | null = null
  // 正在批量保存的作品 id，防止回调连续到达时重复弹窗
  private savingIllustIds: Set<number> = new Set()

  // 公共请求头
  private readonly PIXIV_HEADERS: Record<string, string> = {
    "Referer": "https://www.pixiv.net/",
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
  };

  /** 初始化下载目录 */
  async initDownLoad(context: common.Context) {
    this.context = context
    try {
      this.downloadDir = `${context.filesDir}/Pixiv/Pictures`;
      if (!fs.accessSync(this.downloadDir)) fs.mkdirSync(this.downloadDir);
    } catch (e) {
      logger.error("initDownLoad Error:", e)
    }
  }

  // 监听页码和总任务列表的变化，自动刷新显示列表
  @Monitor('currentPage', 'tasks')
  onDataChanged() {
    this.refreshDisplayList();
  }

  /** 切换编辑模式 */
  toggleEditMode() {
    this.isEditMode = !this.isEditMode;
    this.selectedIds.clear();
  }

  /** 切换选中状态 */
  toggleSelect(task_id: string) {
    if (this.selectedIds.has(task_id)) {
      this.selectedIds.delete(task_id);
    } else {
      this.selectedIds.add(task_id);
    }
  }

  /** 切换缩略图显示 */
  toggleThumbnail() {
    appSettings.show_thumbnail = !appSettings.show_thumbnail;
  }

  /** 判断是否选中 */
  isSelected(task_id: string): boolean {
    return this.selectedIds.has(task_id); // O(1) 复杂度
  }

  /** 全选当前页面 */
  selectAllVisible() {
    this.selectedIds.clear();
    this.displayList.forEach(task => this.selectedIds.add(task.task_id));
  }

  /** 取消全选 */
  deselectAll() {
    this.selectedIds.clear();
  }

  /** 获取选中数量 */
  getSelectedCount(): number {
    return this.selectedIds.size;
  }

  editDelete() {
    // 筛选出当前选中的任务对象数组
    const selectedTasks = this.tasks.filter(t => this.selectedIds.has(t.task_id));
    const count = selectedTasks.length;
    // 根据数量动态生成提示文案
    let message = '';
    if (count === 1) {
      // 只选了一个：显示具体作品名
      const title = selectedTasks[0].title || '未知作品';
      message = `确定要删除「${title}」吗？此操作不可恢复。`;
    } else if (count > 1) {
      // 选了多个：显示数量
      message = `确定要删除选中的 ${count} 个任务吗？此操作不可恢复。`;
    }

    // 召唤弹窗
    if (message) {
      toastUtil.showAlertDialog({
        title: '确认删除',
        message: message,
        alignment: DialogAlignment.Center,
        primaryButton: {
          value: '删除',
          fontColor: Color.Red,
          action: async () => {
            await this.batchRemoveSelectedTasks();
          }
        },
        secondaryButton: {
          value: '取消',
          action: () => {}
        }
      })
    }
  }

  /** 多选后批量删除 */
  async batchRemoveSelectedTasks() {
    if (this.selectedIds.size === 0) return;
    // 获取待删除 ID
    const idsToDelete = Array.from(this.selectedIds);
    // 调用底层删除
    await this.batchDeleteTasksByIds(idsToDelete);
    // 清空勾选、退出编辑模式
    this.toggleEditMode();
  }

  async getFileUri(filePath: string | undefined): Promise<string> {
    return filePath ? fileUri.getUriFromPath(filePath) : '';
  }

  /** 刷新当前展示的列表数据 */
  refreshDisplayList() {
    const statusList: (number[] | null)[] = [
      null, // 0: 所有
      [request.agent.State.RUNNING, request.agent.State.RETRYING], // 1: 下载中
      [request.agent.State.COMPLETED], // 2: 已完成
      [request.agent.State.STOPPED, request.agent.State.FAILED] // 3: 失败
    ];
    const targetStatus = statusList[this.currentPage] ?? null;
    // 赋新数组引用，确保 @Trace 能通知到 UI
    this.displayList = targetStatus
      ? this.tasks.filter(d => targetStatus.includes(d.status))
      : [...this.tasks];
  }

  /** 获取任务列表 */
  async fetchSysTask() {
    if (!this.context) return;
    const db = getDownloadRecordTable(this.context);
    let dbRecords = await db.queryAllDesc();

    const stateTypes = [
      request.agent.State.RUNNING, request.agent.State.FAILED, request.agent.State.PAUSED,
      request.agent.State.COMPLETED, request.agent.State.STOPPED, request.agent.State.RETRYING,
      request.agent.State.WAITING, request.agent.State.INITIALIZED,
    ];
    try {
      const task_ids = (await Promise.all(stateTypes.map(s => request.agent.search({ state: s })))).flat();
      const sysTasks = await Promise.all(task_ids.map(id => request.agent.show(id).catch(() => null)));

      const sysTaskMap = new Map<string, request.agent.TaskInfo>();
      sysTasks.forEach(task => {
        if (task) {
          sysTaskMap.set(task.tid, task);
        }
      });

      this.tasks = dbRecords.map(record => {
        const sysTask = sysTaskMap.get(record.task_id);
        if (sysTask) {
          record.status = sysTask.progress.state;
          if (sysTask.progress.sizes && sysTask.progress.sizes.length > 0) {
            const total = sysTask.progress.sizes[0];
            if (total > 0) {
              record.progress = Math.floor((sysTask.progress.processed / total) * 100);
            }
          }
        } else if (record.status !== request.agent.State.COMPLETED) {
          record.status = request.agent.State.FAILED;
        }
        return record;
      }).sort((a, b) => b.create_time - a.create_time);

      this.tasks.forEach(record => {
        if (record.status !== request.agent.State.COMPLETED &&
          record.status !== request.agent.State.FAILED &&
          record.status !== request.agent.State.STOPPED) {
          this.attachSysTask(record.task_id);
        }
      });
    } catch (e) {
      logger.error("fetchSysTask failed", e);
    }
  }

  /** 检查沙箱文件是否真实存在 */
  isFileInSandbox(filePath: string | undefined): boolean {
    if (!filePath) return false;
    try {
      // accessSync 是微秒级的本地校验，在这里使用不会卡 UI
      return fs.accessSync(filePath);
    } catch (e) {
      return false;
    }
  }

  /** 手动保存到相册 */
  async manualSaveToGallery(record: DownloadRecordInfo) {
    if (!this.isFileInSandbox(record.filePath)) {
      toastUtil.showToast({ message: "文件不存在或已保存" });
      return;
    }
    toastUtil.showToast({ message: `正在导出 ${record.title || '未命名作品'}` })
    // 复用保存逻辑，保存成功后它会自动 deleteFile 删除沙箱文件
    await this.saveImageToGallery(record.filePath, record.title || '未命名作品');
    // 保存成功后，主动刷新一次列表
    this.refreshDisplayList()
  }

  async pauseTask(id: string) {
    (await this.getSysTask(id))?.pause();
  }

  // 恢复任务
  async resumeTask(id: string) {
    const task = await this.getSysTask(id);
    if (task) this.TryRunTask(task, true);
  }

  // 重启任务
  async restartTask(id: string) {
    if (!this.context) return;
    const record = this.tasks.find(d => d.task_id === id);
    if (!record) {
      toastUtil.showToast({ message: `未查询到下载记录` })
      return;
    }
    toastUtil.showToast({ message: `开始重试「${record.title}」任务` })
    const task = await this.getSysTask(id);
    if (task) {
      this.TryRunTask(task);
    } else {
      await this.recreateLostTask(record);
    }
  }

  async deleteOneTask(task: DownloadRecordInfo) {
    await this.removeTask(task)
  }

  async pauseAllTask() {
    const task_ids = await request.agent.search({ state: request.agent.State.RUNNING });
    for (let id of task_ids) {
      const task = await this.getSysTask(id);
      if (task) { this.attachTask(task); await task.pause(); }
    }
  }

  async resumeAllTask() {
    const task_ids = await request.agent.search({ state: request.agent.State.PAUSED });
    for (let id of task_ids) {
      const task = await this.getSysTask(id);
      if (task) {
        this.attachTask(task);
        await this.TryRunTask(task, true);
        await new Promise<void>(res => setTimeout(res, 100));
      }
    }
  }

  async restartAllTask() {
    // 找出本地内存中所有处于 失败 或 停止 状态的任务
    const failedTasks = this.tasks.filter(d =>
    d.status === request.agent.State.FAILED ||
      d.status === request.agent.State.STOPPED
    );
    if (failedTasks.length === 0) return;

    logger.debug(`restartAllSysTask: 发现 ${failedTasks.length} 个失败/停止任务，开始批量重试`);
    // 遍历并直接调用单个重试逻辑
    for (const task of failedTasks) {
      try {
        // 复用完善后的单个重试方法
        await this.restartTask(task.task_id);
      } catch (e) {
        toastUtil.showToast({ message: `任务 ${task.title} 重试失败`})
        // 防止某一个任务重试时抛出异常中断了整个批量循环
        logger.error(`restartAllSysTask: 单个任务重试异常 task_id: ${task.task_id}, err: ${JSON.stringify(e)}`);
      }
    }
  }

  /** 清空所有已完成的任务 */
  async clearAllCompletedTasks() {
    // 筛选已完成任务
    const completedTasks = this.tasks.filter(d => d.status === request.agent.State.COMPLETED);
    if (completedTasks.length === 0) {
      logger.warn("clearAllCompletedTasks: 没有已完成的任务需要清理");
      return;
    }
    // 提取 ID
    const ids = completedTasks.map(task => task.task_id);
    // 调用底层删除
    await this.batchDeleteTasksByIds(ids);
  }

  async attachSysTask(id: string) {
    const task = await this.getSysTask(id);
    if (task) this.attachTask(task);
  }

  /** 添加 Pixiv 图片下载任务 */
  async addTask(context: common.Context, illustInfo: PixivIllust, url: string) {
    // 按 URL 检查该张图片是否已存在（同一作品的不同页允许同时入队）
    const existingTask = this.tasks.find(t => t.url === url);
    if (existingTask) {
      // 存在则弹窗询问，用 Promise 等待用户选择
      const shouldContinue = await new Promise<boolean>((resolve) => {
        toastUtil.showAlertDialog({
          title: '提示',
          message: `「${existingTask.title || '未知作品'}」已在下载列表中，是否继续下载？`,
          alignment: DialogAlignment.Center,
          primaryButton: {
            value: '继续下载',
            action: () => resolve(true)
          },
          secondaryButton: {
            value: '取消',
            action: () => resolve(false)
          }
        });
      });
      // 用户点了取消，直接 return
      if (!shouldContinue) return;
    }

    // 添加逻辑
    if (!this.downloadDir) await this.initDownLoad(context);
    const db = getDownloadRecordTable(context);
    const fileName = this._generateSafeFileName(illustInfo, url);
    const filePath = `${this.downloadDir}/${fileName}`;
    try {
      let task = await request.agent.create(context, this.getTaskConfig(url, fileName, filePath));
      const record = new DownloadRecordInfo();
      record.task_id = task.tid;
      record.illust_id = illustInfo.id;
      record.title = illustInfo.title;
      record.artistName = illustInfo.user?.name;
      record.artist_avatar = illustInfo.user?.profile_image_urls?.medium;
      record.thumbnail = illustInfo.image_urls?.medium || illustInfo.image_urls?.large;
      record.filePath = filePath;
      record.url = url;
      record.status = request.agent.State.INITIALIZED;
      record.create_time = Date.now();
      await db.insert(record);
      this.tasks.unshift(record);
      toastUtil.showToast({ message: $r('app.string.download_now', illustInfo.title) });
      await this.attachTask(task);
      await this.TryRunTask(task);
    } catch (e) {
      logger.error("Add Task Error", e);
    }
  }


  private async getSysTask(id: string | undefined): Promise<request.agent.Task | undefined> {
    if (!id || !this.context) return undefined;
    try {
      return await request.agent.getTask(this.context, id);
    } catch (e) {
      return undefined;
    }
  }

  // 丢失任务重建
  private async recreateLostTask(record: DownloadRecordInfo) {
    if (!record.url || !this.context) {
      record.status = request.agent.State.FAILED;
      return;
    }
    logger.info(`restartTask: 系统任务丢失, 使用链接重建: ${record.url}`);

    try {
      const db = getDownloadRecordTable(this.context);
      const fileName = record.filePath ? record.filePath.substring(record.filePath.lastIndexOf('/') + 1) : `pixiv_${Date.now()}`;
      const filePath = record.filePath || `${this.downloadDir}/${fileName}`;

      const newTask = await request.agent.create(this.context, this.getTaskConfig(record.url, fileName, filePath));

      record.task_id = newTask.tid;
      record.status = request.agent.State.INITIALIZED;
      record.progress = 0;
      await db.update(record);

      await this.attachTask(newTask);
      await this.TryRunTask(newTask);
    } catch (e) {
      logger.error(`restartTask: 重建失败. ${JSON.stringify(e)}`);
      record.status = request.agent.State.FAILED;
    }
  }

  private async attachTask(task: request.agent.Task) {
    if (!this.context) return;
    this.unAttackTask(task);
    const db = getDownloadRecordTable(this.context);

    task.on('progress', (progress) => {
      const target = this.tasks.find(d => d.task_id === task.tid);
      if (target && progress.sizes && progress.sizes.length > 0) {
        const total = progress.sizes[0];
        if (total > 0) target.progress = Math.floor((progress.processed / total) * 100);
      }
    });

    task.on('completed', async () => {
      const target = this.tasks.find(d => d.task_id === task.tid);
      if (target) {
        target.status = request.agent.State.COMPLETED;
        target.progress = 100;
        await db.updateStatus(task.tid, request.agent.State.COMPLETED);
        // 等同作品所有页下载结束后，合并为一次授权弹窗批量保存
        await this.trySaveIllustGroup(target.illust_id);
      }
      this.TryRunNextTask();
    });

    task.on('pause', () => {
      const target = this.tasks.find(d => d.task_id === task.tid);
      if (target) target.status = request.agent.State.PAUSED;
      db.updateStatus(task.tid, request.agent.State.PAUSED);
      this.TryRunNextTask();
    });

    task.on('resume', () => {
      const target = this.tasks.find(d => d.task_id === task.tid);
      if (target) target.status = request.agent.State.RUNNING;
      db.updateStatus(task.tid, request.agent.State.RUNNING);
    });

    task.on('failed', async () => {
      const target = this.tasks.find(d => d.task_id === task.tid);
      if (target) target.status = request.agent.State.FAILED;
      await db.updateStatus(task.tid, request.agent.State.FAILED);
      // 部分页失败时，若其余页均已终态，把已完成的页批量保存（一次弹窗）
      if (target) await this.trySaveIllustGroup(target.illust_id);
      this.TryRunNextTask();
    });

    task.on('remove', () => {
      this.tasks = this.tasks.filter(d => d.task_id !== task.tid);
      this.TryRunNextTask();
    });
  }

  private async TryRunNextTask() {
    const waiting = await request.agent.search({ state: request.agent.State.INITIALIZED });
    if (waiting.length === 0) return;
    const sysTask = await this.getSysTask(waiting.pop());
    if (sysTask) {
      const started = await this.TryRunTask(sysTask);
      if (started) {
        const target = this.tasks.find(d => d.task_id === sysTask.tid);
        if (target) target.status = request.agent.State.RUNNING;
      }
    }
  }

  private async TryRunTask(task: request.agent.Task, resume: boolean = false) {
    const running = await request.agent.search({ state: request.agent.State.RUNNING });
    if (running.length < Number(appSettings.max_download_count)) {
      resume ? await task.resume() : await task.start();
      return true;
    }
    return false;
  }

  private unAttackTask(task: request.agent.Task) {
    task.off('progress'); task.off('completed'); task.off('failed');
    task.off('pause'); task.off('resume'); task.off('remove');
  }

  /**
   * 按作品分组保存：当同一作品的所有下载任务均到达终态（完成/失败/停止）后，
   * 将其中已完成且沙箱文件仍存在的图片合并为一次 showAssetsCreationDialog 授权弹窗批量保存。
   * 仍有任务处于排队/下载中/暂停时不触发，等最后一页结束后再统一处理。
   */
  private async trySaveIllustGroup(illustId: number | undefined) {
    if (illustId === undefined || illustId === null || this.savingIllustIds.has(illustId)) return;
    const group = this.tasks.filter(d => d.illust_id === illustId);
    if (group.length === 0) return;

    const activeStates = [
      request.agent.State.INITIALIZED,
      request.agent.State.WAITING,
      request.agent.State.RUNNING,
      request.agent.State.RETRYING,
      request.agent.State.PAUSED
    ];
    // 还有页未结束（含暂停，用户可能恢复下载），暂不保存
    if (group.some(d => activeStates.includes(d.status))) return;

    const readyItems: GallerySaveItem[] = group
      .filter(d => d.status === request.agent.State.COMPLETED && this.isFileInSandbox(d.filePath))
      .map(d => ({ filePath: d.filePath as string, title: d.title || '未命名作品' } as GallerySaveItem));
    if (readyItems.length === 0) return;

    this.savingIllustIds.add(illustId);
    try {
      await this.saveImagesToGallery(readyItems);
    } finally {
      this.savingIllustIds.delete(illustId);
    }
  }

  /** 将单个沙箱文件保存到系统相册（内部复用批量保存） */
  private async saveImageToGallery(localPath: string, title: string) {
    if (!localPath || !this.context) return;
    await this.saveImagesToGallery([{ filePath: localPath, title: title } as GallerySaveItem]);
  }

  /** 将多个沙箱文件一次性保存到系统相册，只弹一次授权弹窗 */
  private async saveImagesToGallery(items: Array<GallerySaveItem>) {
    if (!this.context || items.length === 0) return;

    try {
      // 过滤出沙箱中真实存在的文件
      const validItems = items.filter(item => item.filePath && this.isFileInSandbox(item.filePath));
      if (validItems.length === 0) return;

      const phAccessHelper = photoAccessHelper.getPhotoAccessHelper(this.context);
      const srcUris: string[] = [];
      const configs: Array<photoAccessHelper.PhotoCreationConfig> = [];
      for (const item of validItems) {
        const fileName = item.filePath.substring(item.filePath.lastIndexOf('/') + 1);
        const dotIndex = fileName.lastIndexOf('.');
        let safeTitle = dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
        const extension = dotIndex > 0 ? fileName.substring(dotIndex + 1) : 'jpg';
        safeTitle = safeTitle.replace(/\./g, '_');
        srcUris.push(fileUri.getUriFromPath(item.filePath));
        configs.push({
          title: safeTitle,
          fileNameExtension: extension,
          photoType: photoAccessHelper.PhotoType.IMAGE,
          subtype: photoAccessHelper.PhotoSubtype.DEFAULT
        });
      }
      logger.info(`[SaveDebug] 准备批量保存 ${srcUris.length} 张图片, 调起 showAssetsCreationDialog...`);
      // 一次弹窗授权所有图片
      const desFileUris = await phAccessHelper.showAssetsCreationDialog(srcUris, configs);
      logger.info(`[SaveDebug] 弹窗返回结果: ${JSON.stringify(desFileUris)}`);
      if (desFileUris && desFileUris.length > 0) {
        // 逐个拷贝，任一张失败则跳过该张继续，其余不受影响
        let savedCount = 0;
        for (let i = 0; i < validItems.length && i < desFileUris.length; i++) {
          try {
            const srcFd = fs.openSync(validItems[i].filePath, fs.OpenMode.READ_ONLY);
            const destFd = await fs.open(desFileUris[i], fs.OpenMode.WRITE_ONLY);
            await fs.copyFile(srcFd.fd, destFd.fd);
            fs.closeSync(srcFd);
            await fs.close(destFd.fd);
            await this.deleteFile(validItems[i].filePath);
            savedCount++;
          } catch (e) {
            logger.error(`[SaveDebug] 拷贝第 ${i} 张失败: ${JSON.stringify(e)}`);
          }
        }
        if (savedCount > 0) {
          toastUtil.showToast({ message: savedCount === 1
            ? `已保存 ${validItems[0].title || '未命名作品'}`
            : `已保存 ${savedCount} 张图片到相册` });
        }
      } else {
        // 用户点击取消，或者弹窗莫名返回空数组
        logger.warn(`[SaveDebug] 弹窗返回为空，大概率是用户取消了保存`);
      }
    } catch (e) {
      logger.error(`[SaveDebug] ❌ 发生异常！错误码: ${e.code}, 错误信息: ${e.message}`);
      logger.error(`[SaveDebug] 完整错误堆栈: ${JSON.stringify(e)}`);
    }
  }

  private async removeTask(task: DownloadRecordInfo) {
    if (!this.context) return;
    const db = getDownloadRecordTable(this.context);
    try { await request.agent.remove(task.task_id); } catch (e) { /* ignore */ }
    await this.deleteFile(task.filePath);
    if (task.id) await db.deleteByID(task.id);
    this.tasks = this.tasks.filter(f => f.task_id !== task.task_id);
  }

  private async deleteFile(filePath: string | undefined) {
    if (!filePath) return;
    try {
      if (fs.accessSync(filePath)) await fs.unlink(filePath);
    } catch (e) {
      logger.warn("Delete file failed", e);
    }
  }

  /**
   * @param ids 待删除的任务ID列表
   * 底层辅助函数：根据 任务ID 列表批量删除任务
   * 只负责删文件、删数据库、更新内存列表
   */
  private async batchDeleteTasksByIds(ids: string[]) {
    if (ids.length === 0) return;

    logger.info(`batchDeleteTasksByIds: 开始批量删除 ${ids.length} 个任务`);

    for (const id of ids) {
      const task = this.tasks.find(d => d.task_id === id);
      if (task) {
        try {
          // 复用单条删除（里面包含了删系统任务、删文件、删DB、更新 this.tasks）
          await this.removeTask(task);
        } catch (e) {
          logger.error(`batchDeleteTasksByIds: 删除任务失败 id: ${id}, err:${JSON.stringify(e)}`);
        }
      }
    }
  }

  /** 提取公共的下载任务配置 */
  private getTaskConfig(url: string, fileName: string, filePath: string): request.agent.Config {
    return {
      action: request.agent.Action.DOWNLOAD,
      url: url,
      title: fileName,
      saveas: filePath,
      headers: this.PIXIV_HEADERS,
      retry: true,
      gauge: true,
      mode: request.agent.Mode.BACKGROUND,
      overwrite: true,
    };
  }

  /** 纯函数：仅负责生成文件名 */
  private _generateSafeFileName(illustInfo: PixivIllust, url: string): string {
    // 获取后缀名
    const extension = url.split('.').pop() || 'jpg';
    // 只提取页码数字部分（如 _p0 → "0"，_p12 → "12"）
    const pageMatch = url.match(/_p(\d+)/);

    // 提取并安全化各个字段
    const safeIllustId = `${illustInfo.id}`;
    const safePart = pageMatch ? pageMatch[1] : '0'; // 纯数字，单图默认 "0"
    const safeUid = `${illustInfo.user?.id || '0'}`;

    // 安全过滤：去除非法字符和点号，保留空格
    const safeTitle = (illustInfo.title || 'Untitled')
      .replace(/[\\/:*?"<>|.]+/g, '_')
      .trim()
      .replace(/\s+/g, ' ')
      .replace(/^_|_$/g, '');
    const safeUserName = (illustInfo.user?.name || 'Pixiv')
      .replace(/[\\/:*?"<>|.]+/g, '_')
      .trim()
      .replace(/\s+/g, ' ')
      .replace(/^_|_$/g, '');

    // 读取模板，为空则使用默认模板
    const template = appSettings.file_name.trim() || '{illust_id}_p{part}_{title}_{user_name}';

    // 执行占位符替换
    let fileName = template
      .replace(/{illust_id}/g, safeIllustId)
      .replace(/{part}/g, safePart)
      .replace(/{title}/g, safeTitle)
      .replace(/{user_name}/g, safeUserName)
      .replace(/{uid}/g, safeUid);

    // 兜底防错（防止用户在设置页瞎填一堆非法字符导致替换完为空）
    if (!fileName || fileName.trim() === '') {
      fileName = `pixiv_${safeIllustId}_p${safePart}`;
    }

    return `${fileName}.${extension}`;
  }

}

export const downloaderVM = new DownloadsViewModel();

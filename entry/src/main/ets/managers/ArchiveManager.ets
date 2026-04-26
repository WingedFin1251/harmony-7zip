import { fileIo } from '@kit.CoreFileKit';
import worker from '@ohos.worker';
import { ToastUtil } from '../utils/ToastUtil';
import { CompressOptions, ExtractOptions, ValidationResult, SupportedFormat } from '../types/types';

// 顶层接口声明
interface WorkerResponse {
  success: boolean;
  error?: string;
  taskId: number;
}

interface TaskCallback {
  resolve: (value: void) => void;
  reject: (reason: Error) => void;
}

interface WorkerMessage {
  type: string;
  params: object;
  taskId: number;
}

interface WorkerCompressOptions {
  format: string;
  password?: string;
  splitSize?: string;
}

interface CompressWorkerParams {
  files: string[];
  archivePath: string;
  options: WorkerCompressOptions;
}

interface ExtractWorkerParams {
  archivePath: string;
  destPath: string;
  password: string;
}

interface CopyWorkerParams {
  srcDir: string;
  destDirUri: string;
}

interface DeleteWorkerParams {
  path: string;
}

interface WorkerMessageEvent {
  data: WorkerResponse;
}

export class ArchiveManager {
  private worker: worker.ThreadWorker | null = null;
  private taskCounter = 0;
  private pendingTasks = new Map<number, TaskCallback>();

  constructor() {
    this.worker = new worker.ThreadWorker('entry/ets/workers/archive.worker.ets');
    this.worker.onmessage = (event: WorkerMessageEvent): void => {
      const data = event.data;
      const task = this.pendingTasks.get(data.taskId);
      if (task) {
        if (data.success) {
          task.resolve();
        } else {
          task.reject(new Error(data.error || 'Unknown error'));
        }
        this.pendingTasks.delete(data.taskId);
      }
    };
    // 使用 Object 类型，兼容鸿蒙的 MessageEvents 等未知类型
    this.worker.onerror = (err: Object): void => {
      console.error('Worker error:', err);
    };
    this.worker.onmessageerror = (err: Object): void => {
      console.error('Worker message error:', err);
    };
  }

  // 清理Worker资源
  terminate(): void {
    if (this.worker) {
      try {
        this.worker.terminate();
      } catch (err) {
        console.error('Worker terminate error:', err);
      } finally {
        this.worker = null;
        this.pendingTasks.clear();
      }
    }
  }

  private postTask(type: string, params: object): Promise<void> {
    return new Promise((resolve, reject) => {
      if (!this.worker) {
        reject(new Error('Worker not initialized'));
        return;
      }
      const taskId = this.taskCounter++;
      const callback: TaskCallback = { resolve, reject };
      this.pendingTasks.set(taskId, callback);
      const message: WorkerMessage = { type, params, taskId };
      try {
        this.worker.postMessage(message);
      } catch (err) {
        // 发生异常时清理 pending 任务并 reject
        this.pendingTasks.delete(taskId);
        reject(err instanceof Error ? err : new Error(String(err)));
      }
    });
  }
  // 检查是否为外部存储URI
  private isExternalUri(path: string): boolean {
    return path.startsWith('file://docs/') || path.startsWith('file://media/');
  }

  // 从外部URI提取目录路径
  private getExternalDirFromUri(uri: string): string {
    // file://docs/storage/Users/currentUser/Download -> /storage/Users/currentUser/Download
    return uri.replace('file://docs/', '').replace('file://media/', '');
  }

  // 开始压缩
  async startCompress(selectedPaths: string[], currentPath: string, options: CompressOptions): Promise<void> {
    try {
      // 检查参数
      if (!selectedPaths || selectedPaths.length === 0) {
        throw new Error('请选择要压缩的文件');
      }

      const archiveName = 'archive_' + Date.now() + '.' + options.format;
      const archivePath = currentPath + '/' + archiveName;
      console.log('开始压缩:', selectedPaths, '->', archivePath);
      
      // 提交到 Worker
      const compressOptions: WorkerCompressOptions = {
        format: options.format,
        password: options.password,
        splitSize: options.splitSize
      };
      const compressParams: CompressWorkerParams = {
        files: selectedPaths,
        archivePath: archivePath,
        options: compressOptions
      };
      await this.postTask('compress', compressParams);
      
      ToastUtil.showToast('压缩完成: ' + archiveName);
    } catch (err) {
      console.error('压缩失败 catch 块:', JSON.stringify(err), err);
      console.error('压缩失败类型:', typeof err);
      if (err && typeof err === 'object') {
        console.error('压缩失败对象键:', Object.keys(err));
      }
      const errMsg = err instanceof Error ? err.message : String(err);
      console.error('压缩失败信息:', errMsg);
      
      if (errMsg.includes('password')) {
        ToastUtil.showToast('密码错误或加密失败');
      } else if (errMsg.includes('format')) {
        ToastUtil.showToast('不支持的压缩格式');
      } else if (errMsg.includes('size')) {
        ToastUtil.showToast('文件过大或磁盘空间不足');
      } else if (errMsg.includes('未加载') || errMsg.includes('不可用')) {
        ToastUtil.showToast('压缩功能暂时不可用');
      } else {
        ToastUtil.showToast('压缩失败: ' + errMsg);
      }
      throw new Error(errMsg);
    }
  }

  // 开始解压（修改后）
  async startExtract(selectedPaths: string[], currentPath: string, options: ExtractOptions): Promise<void> {
    try {
      if (!selectedPaths || selectedPaths.length === 0) {
        throw new Error('请选择要解压的文件');
      }

      const archivePath = selectedPaths[0];
      // 检查文件存在（轻量操作，可保留在主线程）
      try {
        fileIo.statSync(archivePath);
      } catch {
        throw new Error('压缩文件不存在或无法访问');
      }

      const timestamp = Date.now();
      const extractPath = options.extractPath || currentPath + '/extracted_' + timestamp;
      const isExternal = this.isExternalUri(extractPath);
      let actualExtractPath: string;
      let externalUri: string = '';

      if (isExternal) {
        externalUri = extractPath;
        actualExtractPath = currentPath + '/temp_extract_' + timestamp;
        fileIo.mkdirSync(actualExtractPath, true);

        // 解压到临时目录（Worker）
        const extractParams: ExtractWorkerParams = {
          archivePath: archivePath,
          destPath: actualExtractPath,
          password: options.password || ''
        };
        await this.postTask('extract', extractParams);

        // 复制到外部目录（Worker）
        const copyParams: CopyWorkerParams = {
          srcDir: actualExtractPath,
          destDirUri: externalUri
        };
        await this.postTask('copyToExternal', copyParams);

        // 删除临时目录（Worker）
        const deleteParams: DeleteWorkerParams = {
          path: actualExtractPath
        };
        await this.postTask('delete', deleteParams);
        ToastUtil.showToast('解压完成（已扁平化复制到外部目录）');
      } else {
        actualExtractPath = extractPath;
        fileIo.mkdirSync(actualExtractPath, true);
        const extractParams2: ExtractWorkerParams = {
          archivePath: archivePath,
          destPath: actualExtractPath,
          password: options.password || ''
        };
        await this.postTask('extract', extractParams2);
        ToastUtil.showToast('解压完成到: ' + extractPath);
      }
    } catch (err) {
      console.error('解压失败 catch 块:', JSON.stringify(err), err);
      console.error('解压失败类型:', typeof err);
      if (err && typeof err === 'object') {
        console.error('解压失败对象键:', Object.keys(err));
      }
      const errMsg = err instanceof Error ? err.message : String(err);
      console.error('解压失败信息:', errMsg);
      ToastUtil.showToast('解压失败: ' + errMsg);
      throw new Error(errMsg);
    }
  }

  // 检查是否支持压缩格式
  isSupportedCompressFormat(format: string): boolean {
    return ['7z', 'zip', 'tar'].includes(format);
  }

  // 获取压缩格式的默认扩展名
  getDefaultExtension(format: string): string {
    switch (format) {
      case '7z': return '.7z';
      case 'zip': return '.zip';
      case 'tar': return '.tar';
      default: return '.zip';
    }
  }

  // 验证压缩选项
  validateCompressOptions(options: CompressOptions): ValidationResult {
    if (!this.isSupportedCompressFormat(options.format)) {
      return { isValid: false, error: '不支持的压缩格式' };
    }

    if (options.password && options.password.length < 4) {
      return { isValid: false, error: '密码至少需要4个字符' };
    }

    if (options.splitSize) {
      const match = options.splitSize.match(/^(\d+)([KMGT]?B)$/i);
      if (!match) {
        return { isValid: false, error: '分割大小格式不正确，例如：100MB, 1GB' };
      }
    }

    return { isValid: true };
  }

  // 验证解压选项
  validateExtractOptions(options: ExtractOptions): ValidationResult {
    if (options.password && options.password.length < 4) {
      return { isValid: false, error: '密码至少需要4个字符' };
    }

    return { isValid: true };
  }

  // 获取压缩格式的描述
  getFormatDescription(format: string): string {
    switch (format) {
      case '7z':
        return '7z格式 - 高压缩比，支持加密和分卷';
      case 'zip':
        return 'ZIP格式 - 广泛兼容，支持加密';
      case 'tar':
        return 'TAR格式 - Unix/Linux标准归档格式';
      default:
        return '未知格式';
    }
  }

  // 估算压缩后大小（简化版本）
  estimateCompressedSize(selectedPaths: string[], format: string): string {
    // 这是一个简化的估算，实际实现需要更复杂的逻辑
    const totalSize = selectedPaths.reduce((total) => total + 1024 * 1024, 0);
    const compressionRatio = format === '7z' ? 0.3 : format === 'zip' ? 0.5 : 0.9;
    const estimatedSize = totalSize * compressionRatio;

    if (estimatedSize < 1024) {
      return `${estimatedSize.toFixed(0)} B`;
    } else if (estimatedSize < 1024 * 1024) {
      return `${(estimatedSize / 1024).toFixed(1)} KB`;
    } else if (estimatedSize < 1024 * 1024 * 1024) {
      return `${(estimatedSize / (1024 * 1024)).toFixed(1)} MB`;
    } else {
      return `${(estimatedSize / (1024 * 1024 * 1024)).toFixed(1)} GB`;
    }
  }

  // 检查文件是否为压缩文件
  isArchiveFile(filename: string): boolean {
    const archiveExtensions = ['.7z', '.zip', '.tar', '.gz', '.bz2', '.xz', '.rar'];
    return archiveExtensions.some(ext => filename.toLowerCase().endsWith(ext));
  }

  // 获取支持的压缩格式列表
  getSupportedFormats(): SupportedFormat[] {
    return [
      { value: '7z', label: '7z', description: '高压缩比，支持加密和分卷' },
      { value: 'zip', label: 'ZIP', description: '广泛兼容，支持加密' },
      { value: 'tar', label: 'TAR', description: 'Unix/Linux标准归档格式' }
    ];
  }

  // 获取默认压缩选项
  getDefaultCompressOptions(): CompressOptions {
    return {
      format: 'zip',
      password: '',
      splitSize: ''
    };
  }

  // 获取默认解压选项
  getDefaultExtractOptions(): ExtractOptions {
    return {
      password: '',
      extractPath: ''
    };
  }
}
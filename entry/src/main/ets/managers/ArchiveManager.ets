import * as native from 'libentry.so';
import { fileIo } from '@kit.CoreFileKit';
import { ToastUtil } from '../utils/ToastUtil';
import { CompressOptions, ExtractOptions, ValidationResult, SupportedFormat } from '../types/types';

export class ArchiveManager {
  // 开始压缩
  async startCompress(selectedPaths: string[], currentPath: string, options: CompressOptions): Promise<void> {
    try {
      // 检查原生模块是否可用
      if (!native || typeof native.compress !== 'function') {
        throw new Error('压缩模块未加载或不可用');
      }

      // 检查参数
      if (!selectedPaths || selectedPaths.length === 0) {
        throw new Error('请选择要压缩的文件');
      }

      // 生成压缩文件路径
      const archiveName = 'archive_' + Date.now() + '.' + options.format;
      const archivePath = currentPath + '/' + archiveName;

      console.log('开始压缩:', selectedPaths, '->', archivePath);
      
      await native.compress(
        selectedPaths,
        archivePath,
        options
      );
      ToastUtil.showToast('压缩完成: ' + archiveName);
    } catch (err) {
      const errMsg = (err as Error).message;
      console.error('压缩失败详情:', JSON.stringify(err));
      
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

  // 开始解压
  async startExtract(selectedPaths: string[], currentPath: string, options: ExtractOptions): Promise<void> {
    try {
      // 检查原生模块是否可用
      if (!native || typeof native.extract !== 'function') {
        throw new Error('解压模块未加载或不可用');
      }

      // 检查参数
      if (!selectedPaths || selectedPaths.length === 0) {
        throw new Error('请选择要解压的文件');
      }

      const archivePath = selectedPaths[0];
      
      // 检查文件是否存在
      try {
        const stat = fileIo.statSync(archivePath);
        if (!stat) {
          throw new Error('压缩文件不存在');
        }
      } catch (statErr) {
        throw new Error('无法访问压缩文件: ' + (statErr as Error).message);
      }

      // 生成解压目录
      const timestamp = Date.now();
      const extractPath = options.extractPath || currentPath + '/extracted_' + timestamp;

      console.log('开始解压:', archivePath, '->', extractPath);
      
      await native.extract(
        archivePath,
        extractPath,
        options.password || ''
      );
      ToastUtil.showToast('解压完成到: ' + extractPath);
    } catch (err) {
      const errMsg = (err as Error).message;
      console.error('解压失败详情:', JSON.stringify(err));
      
      if (errMsg.includes('password')) {
        ToastUtil.showToast('密码错误');
      } else if (errMsg.includes('format')) {
        ToastUtil.showToast('不支持的压缩格式或文件损坏');
      } else if (errMsg.includes('size')) {
        ToastUtil.showToast('磁盘空间不足');
      } else if (errMsg.includes('未加载') || errMsg.includes('不可用')) {
        ToastUtil.showToast('解压功能暂时不可用');
      } else if (errMsg.includes('不存在') || errMsg.includes('无法访问')) {
        ToastUtil.showToast('压缩文件不存在或无法访问');
      } else {
        ToastUtil.showToast('解压失败: ' + errMsg);
      }
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
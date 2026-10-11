/**
 * 文件类型识别工具类
 * 提供文件扩展名识别、MIME类型映射等功能
 */

// 文件类型枚举
export enum FileType {
  UNKNOWN = 'unknown',
  ARCHIVE = 'archive',     // 压缩包
  DOCUMENT = 'document',   // 文档
  IMAGE = 'image',         // 图片
  AUDIO = 'audio',         // 音频
  VIDEO = 'video',         // 视频
  CODE = 'code',           // 代码文件
  EXECUTABLE = 'executable', // 可执行文件
  FOLDER = 'folder'        // 文件夹
}

// 文件类型信息接口
export interface FileTypeInfo {
  type: FileType;
  mimeType: string;
  icon: Resource;          // 图标资源
  description: string;     // 类型描述
}

// 文件扩展名到类型的映射
const EXTENSION_TO_TYPE: Record<string, FileType> = {
  // 压缩包类型
  '7z': FileType.ARCHIVE,
  'zip': FileType.ARCHIVE,
  'rar': FileType.ARCHIVE,
  'tar': FileType.ARCHIVE,
  'gz': FileType.ARCHIVE,
  'bz2': FileType.ARCHIVE,
  'xz': FileType.ARCHIVE,
  'lz': FileType.ARCHIVE,
  'lzma': FileType.ARCHIVE,
  'lzo': FileType.ARCHIVE,
  'zst': FileType.ARCHIVE,
  'cab': FileType.ARCHIVE,
  'iso': FileType.ARCHIVE,
  'pkg': FileType.ARCHIVE,
  
  // 文档类型
  'pdf': FileType.DOCUMENT,
  'doc': FileType.DOCUMENT,
  'docx': FileType.DOCUMENT,
  'xls': FileType.DOCUMENT,
  'xlsx': FileType.DOCUMENT,
  'ppt': FileType.DOCUMENT,
  'pptx': FileType.DOCUMENT,
  'txt': FileType.DOCUMENT,
  'rtf': FileType.DOCUMENT,
  'odt': FileType.DOCUMENT,
  'ods': FileType.DOCUMENT,
  'odp': FileType.DOCUMENT,
  'md': FileType.DOCUMENT,
  
  // 图片类型
  'jpg': FileType.IMAGE,
  'jpeg': FileType.IMAGE,
  'png': FileType.IMAGE,
  'gif': FileType.IMAGE,
  'bmp': FileType.IMAGE,
  'svg': FileType.IMAGE,
  'webp': FileType.IMAGE,
  'ico': FileType.IMAGE,
  'tiff': FileType.IMAGE,
  'tif': FileType.IMAGE,
  'heic': FileType.IMAGE,
  'heif': FileType.IMAGE,
  
  // 音频类型
  'mp3': FileType.AUDIO,
  'wav': FileType.AUDIO,
  'flac': FileType.AUDIO,
  'aac': FileType.AUDIO,
  'ogg': FileType.AUDIO,
  'wma': FileType.AUDIO,
  'm4a': FileType.AUDIO,
  'opus': FileType.AUDIO,
  
  // 视频类型
  'mp4': FileType.VIDEO,
  'avi': FileType.VIDEO,
  'mkv': FileType.VIDEO,
  'mov': FileType.VIDEO,
  'wmv': FileType.VIDEO,
  'flv': FileType.VIDEO,
  'webm': FileType.VIDEO,
  'm4v': FileType.VIDEO,
  'mpg': FileType.VIDEO,
  'mpeg': FileType.VIDEO,
  
  // 代码文件类型
  'js': FileType.CODE,
  'ts': FileType.CODE,
  'jsx': FileType.CODE,
  'tsx': FileType.CODE,
  'html': FileType.CODE,
  'htm': FileType.CODE,
  'css': FileType.CODE,
  'scss': FileType.CODE,
  'less': FileType.CODE,
  'json': FileType.CODE,
  'xml': FileType.CODE,
  'yaml': FileType.CODE,
  'yml': FileType.CODE,
  'java': FileType.CODE,
  'kt': FileType.CODE,
  'cpp': FileType.CODE,
  'c': FileType.CODE,
  'h': FileType.CODE,
  'py': FileType.CODE,
  'php': FileType.CODE,
  'rb': FileType.CODE,
  'go': FileType.CODE,
  'rs': FileType.CODE,
  'swift': FileType.CODE,
  'dart': FileType.CODE,
  'sql': FileType.CODE,
  'sh': FileType.CODE,
  'bat': FileType.CODE,
  'ps1': FileType.CODE,
  
  // 可执行文件类型
  'exe': FileType.EXECUTABLE,
  'msi': FileType.EXECUTABLE,
  'apk': FileType.EXECUTABLE,
  'app': FileType.EXECUTABLE,
  'dmg': FileType.EXECUTABLE,
  'deb': FileType.EXECUTABLE,
  'rpm': FileType.EXECUTABLE,
  'bin': FileType.EXECUTABLE
};

// 文件类型到MIME类型的映射
const TYPE_TO_MIME: Record<FileType, string> = {
  [FileType.UNKNOWN]: 'application/octet-stream',
  [FileType.ARCHIVE]: 'application/zip',
  [FileType.DOCUMENT]: 'application/pdf',
  [FileType.IMAGE]: 'image/jpeg',
  [FileType.AUDIO]: 'audio/mpeg',
  [FileType.VIDEO]: 'video/mp4',
  [FileType.CODE]: 'text/plain',
  [FileType.EXECUTABLE]: 'application/octet-stream',
  [FileType.FOLDER]: 'inode/directory'
};

// 文件类型到图标的映射
const TYPE_TO_ICON: Record<FileType, Resource> = {
  [FileType.UNKNOWN]: $r('app.media.file'),
  [FileType.ARCHIVE]: $r('app.media.file'),  // 暂时使用通用文件图标
  [FileType.DOCUMENT]: $r('app.media.file'),  // 暂时使用通用文件图标
  [FileType.IMAGE]: $r('app.media.file'),     // 暂时使用通用文件图标
  [FileType.AUDIO]: $r('app.media.file'),     // 暂时使用通用文件图标
  [FileType.VIDEO]: $r('app.media.file'),     // 暂时使用通用文件图标
  [FileType.CODE]: $r('app.media.file'),      // 暂时使用通用文件图标
  [FileType.EXECUTABLE]: $r('app.media.file'), // 暂时使用通用文件图标
  [FileType.FOLDER]: $r('app.media.folder')
};

// 文件类型描述
const TYPE_TO_DESCRIPTION: Record<FileType, string> = {
  [FileType.UNKNOWN]: '未知文件',
  [FileType.ARCHIVE]: '压缩文件',
  [FileType.DOCUMENT]: '文档文件',
  [FileType.IMAGE]: '图片文件',
  [FileType.AUDIO]: '音频文件',
  [FileType.VIDEO]: '视频文件',
  [FileType.CODE]: '代码文件',
  [FileType.EXECUTABLE]: '可执行文件',
  [FileType.FOLDER]: '文件夹'
};

/**
 * 根据文件名获取文件类型信息
 * @param fileName 文件名（可以包含路径）
 * @param isDir 是否是目录
 * @returns 文件类型信息
 */
export function getFileTypeInfo(fileName: string, isDir: boolean = false): FileTypeInfo {
  if (isDir) {
    return {
      type: FileType.FOLDER,
      mimeType: TYPE_TO_MIME[FileType.FOLDER],
      icon: TYPE_TO_ICON[FileType.FOLDER],
      description: TYPE_TO_DESCRIPTION[FileType.FOLDER]
    };
  }
  
  // 获取文件扩展名
  const extension = getFileExtension(fileName).toLowerCase();
  
  // 查找文件类型
  const fileType = EXTENSION_TO_TYPE[extension] || FileType.UNKNOWN;
  
  return {
    type: fileType,
    mimeType: getMimeTypeByExtension(extension) || TYPE_TO_MIME[fileType],
    icon: TYPE_TO_ICON[fileType],
    description: TYPE_TO_DESCRIPTION[fileType]
  };
}

/**
 * 获取文件扩展名
 * @param fileName 文件名
 * @returns 文件扩展名（小写）
 */
export function getFileExtension(fileName: string): string {
  const lastDotIndex = fileName.lastIndexOf('.');
  if (lastDotIndex === -1 || lastDotIndex === fileName.length - 1) {
    return '';
  }
  return fileName.substring(lastDotIndex + 1);
}

/**
 * 根据扩展名获取MIME类型
 * @param extension 文件扩展名
 * @returns MIME类型
 */
export function getMimeTypeByExtension(extension: string): string {
  const ext = extension.toLowerCase();
  
  // 常用MIME类型映射
  const mimeTypes: Record<string, string> = {
    // 压缩包
    '7z': 'application/x-7z-compressed',
    'zip': 'application/zip',
    'rar': 'application/x-rar-compressed',
    'tar': 'application/x-tar',
    'gz': 'application/gzip',
    'bz2': 'application/x-bzip2',
    'xz': 'application/x-xz',
    
    // 文档
    'pdf': 'application/pdf',
    'doc': 'application/msword',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt': 'application/vnd.ms-powerpoint',
    'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'txt': 'text/plain',
    'rtf': 'application/rtf',
    'md': 'text/markdown',
    
    // 图片
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'gif': 'image/gif',
    'bmp': 'image/bmp',
    'svg': 'image/svg+xml',
    'webp': 'image/webp',
    'ico': 'image/x-icon',
    'tiff': 'image/tiff',
    'tif': 'image/tiff',
    
    // 音频
    'mp3': 'audio/mpeg',
    'wav': 'audio/wav',
    'flac': 'audio/flac',
    'aac': 'audio/aac',
    'ogg': 'audio/ogg',
    'wma': 'audio/x-ms-wma',
    'm4a': 'audio/mp4',
    
    // 视频
    'mp4': 'video/mp4',
    'avi': 'video/x-msvideo',
    'mkv': 'video/x-matroska',
    'mov': 'video/quicktime',
    'wmv': 'video/x-ms-wmv',
    'flv': 'video/x-flv',
    'webm': 'video/webm',
    'm4v': 'video/x-m4v',
    
    // 代码
    'js': 'application/javascript',
    'ts': 'application/typescript',
    'html': 'text/html',
    'htm': 'text/html',
    'css': 'text/css',
    'json': 'application/json',
    'xml': 'application/xml',
    'yaml': 'application/x-yaml',
    'yml': 'application/x-yaml',
    'java': 'text/x-java-source',
    'py': 'text/x-python',
    'php': 'application/x-php',
    'sh': 'application/x-sh',
    
    // 可执行文件
    'exe': 'application/x-msdownload',
    'msi': 'application/x-msi',
    'apk': 'application/vnd.android.package-archive',
    'deb': 'application/x-deb',
    'rpm': 'application/x-rpm'
  };
  
  return mimeTypes[ext] || 'application/octet-stream';
}

/**
 * 判断文件是否是压缩包
 * @param fileName 文件名
 * @returns 是否是压缩包
 */
export function isArchiveFile(fileName: string): boolean {
  const extension = getFileExtension(fileName).toLowerCase();
  const archiveExtensions = ['7z', 'zip', 'rar', 'tar', 'gz', 'bz2', 'xz', 'lz', 'lzma', 'lzo', 'zst', 'cab', 'iso', 'dmg', 'pkg'];
  return archiveExtensions.includes(extension);
}

/**
 * 判断文件是否可以直接打开（非压缩包）
 * @param fileName 文件名
 * @returns 是否可以直接打开
 */
export function isOpenableFile(fileName: string): boolean {
  const extension = getFileExtension(fileName).toLowerCase();
  const openableExtensions = [
    // 文档
    'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'rtf', 'md',
    // 图片
    'jpg', 'jpeg', 'png', 'gif', 'bmp', 'svg', 'webp', 'ico', 'tiff', 'tif',
    // 音频
    'mp3', 'wav', 'flac', 'aac', 'ogg', 'wma', 'm4a',
    // 视频
    'mp4', 'avi', 'mkv', 'mov', 'wmv', 'flv', 'webm', 'm4v'
  ];
  return openableExtensions.includes(extension);
}

/**
 * 获取文件类型的友好描述
 * @param fileName 文件名
 * @param isDir 是否是目录
 * @returns 文件类型描述
 */
export function getFileTypeDescription(fileName: string, isDir: boolean = false): string {
  const info = getFileTypeInfo(fileName, isDir);
  return info.description;
}
/**
 * 压缩选项
 */
interface CompressOptions {
  /** 压缩格式: "7z" | "zip" | "tar" */
  format?: string;
  /** 密码（可选） */
  password?: string;
  /** 压缩级别 0-9，默认5 */
  level?: string;
}

/**
 * 压缩文件或目录
 * @param srcPaths 源文件/目录路径数组
 * @param destArchive 目标压缩包路径
 * @param options 压缩选项（可选）
 * @returns Promise<void>
 */
export const compress: (srcPaths: string[], destArchive: string, options?: CompressOptions) => Promise<void>;

/**
 * 解压压缩包
 * @param archivePath 压缩包路径
 * @param destDir 目标解压目录
 * @param password 密码（可选）
 * @returns Promise<void>
 */
export const extract: (archivePath: string, destDir: string, password?: string) => Promise<void>;

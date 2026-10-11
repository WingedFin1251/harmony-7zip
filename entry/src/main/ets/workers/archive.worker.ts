import worker from '@ohos.worker';
import * as native from 'libentry.so';
import fs from '@ohos.file.fs';

const parentPort = worker.workerPort;

// 辅助函数：递归收集文件
async function collectAllFiles(dir: string, fileList: string[]): Promise<void> {
  const entries = fs.listFileSync(dir);
  for (const entry of entries) {
    const fullPath = `${dir}/${entry}`;
    const stat = fs.statSync(fullPath);
    if (stat.isDirectory()) {
      await collectAllFiles(fullPath, fileList);
    } else {
      fileList.push(fullPath);
    }
  }
}

// 辅助函数：检查文件是否存在（URI）
async function fileExists(uri: string): Promise<boolean> {
  try {
    fs.accessSync(uri);
    return true;
  } catch {
    return false;
  }
}

// 辅助函数：复制文件
async function copyFile(srcPath: string, destUri: string): Promise<void> {
  const srcFd = fs.openSync(srcPath, fs.OpenMode.READ_ONLY);
  try {
    const destFd = fs.openSync(destUri, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
    try {
      const buffer = new ArrayBuffer(64 * 1024);
      let bytesRead: number;
      while ((bytesRead = fs.readSync(srcFd.fd, buffer)) > 0) {
        fs.writeSync(destFd.fd, buffer, { length: bytesRead });
      }
    } finally {
      fs.closeSync(destFd.fd);
    }
  } finally {
    fs.closeSync(srcFd.fd);
  }
}

// 扁平化复制目录到外部 URI
async function copyDirToExternal(srcDir: string, destDirUri: string): Promise<void> {
  const allFiles: string[] = [];
  await collectAllFiles(srcDir, allFiles);

  let successCount = 0;
  let failCount = 0;

  for (const srcPath of allFiles) {
    const fileName = srcPath.split('/').pop()!;
    let destFileName = fileName;
    let destFileUri = `${destDirUri}/${destFileName}`;
    let counter = 1;
    while (await fileExists(destFileUri)) {
      const dotIndex = fileName.lastIndexOf('.');
      if (dotIndex === -1) {
        destFileName = `${fileName}_${counter}`;
      } else {
        destFileName = `${fileName.substring(0, dotIndex)}_${counter}${fileName.substring(dotIndex)}`;
      }
      destFileUri = `${destDirUri}/${destFileName}`;
      counter++;
    }
    try {
      await copyFile(srcPath, destFileUri);
      successCount++;
    } catch (err) {
      console.error(`复制失败: ${fileName}`, err);
      failCount++;
    }
  }
  if (failCount > 0) {
    throw new Error(`文件复制成功 ${successCount} 个，失败 ${failCount} 个`);
  }
}

// 递归删除目录
async function deleteDirectory(path: string): Promise<void> {
  try {
    const files = fs.listFileSync(path);
    for (const file of files) {
      const subPath = `${path}/${file}`;
      const stat = fs.statSync(subPath);
      if (stat.isDirectory()) {
        await deleteDirectory(subPath);
      } else {
        fs.unlinkSync(subPath);
      }
    }
    fs.rmdirSync(path);
  } catch (err) {
    console.error('删除目录失败:', path, err);
  }
}

// 消息处理
parentPort.onmessage = async (event) => {
  console.log('Worker收到消息，类型:', event.data.type);
  const { type, params, taskId } = event.data;
  try {
    if (type === 'compress') {
      console.log('Worker: 开始压缩，文件:', params.files, '，输出路径:', params.archivePath, '，选项:', params.options);
      await native.compress(params.files, params.archivePath, params.options);
      console.log('Worker: 压缩成功');
      parentPort.postMessage({ success: true, taskId });
    } else if (type === 'extract') {
      console.log('Worker: 开始解压，压缩包:', params.archivePath, '，目标路径:', params.destPath, '，密码:', params.password || '无');
      await native.extract(params.archivePath, params.destPath, params.password);
      console.log('Worker: 解压成功');
      parentPort.postMessage({ success: true, taskId });
    } else if (type === 'copyToExternal') {
      console.log('Worker: 开始复制到外部目录，源目录:', params.srcDir, '，目标URI:', params.destDirUri);
      await copyDirToExternal(params.srcDir, params.destDirUri);
      console.log('Worker: 复制成功');
      parentPort.postMessage({ success: true, taskId });
    } else if (type === 'delete') {
      console.log('Worker: 开始删除目录:', params.path);
      await deleteDirectory(params.path);
      console.log('Worker: 删除成功');
      parentPort.postMessage({ success: true, taskId });
    } else {
      throw new Error(`未知的任务类型: ${type}`);
    }
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    console.error('Worker 内部错误:', errorMessage, error);
    console.error('Worker 错误类型:', typeof error);
    console.error('Worker 错误对象键:', Object.keys(error || {}));
    parentPort.postMessage({ success: false, error: errorMessage, taskId });
  }
};

parentPort.onerror = (err) => {
  console.error('Worker内部错误:', err);
};

parentPort.onmessageerror = (err) => {
  console.error('Worker消息错误:', err);
};
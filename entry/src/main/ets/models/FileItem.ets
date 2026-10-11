// FileItem.ets
export interface FileItem {
  name: string;
  path: string;
  isDir: boolean;
  size: number;
  modified: number;
  uri?: string;
}
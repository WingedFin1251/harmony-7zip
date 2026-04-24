// abilityAccessCtrl.d.ts
declare module '@ohos.abilityAccessCtrl' {
  // 补充 Permissions 类型（如果需要）
  export type Permissions = string;

  // 补充 PermissionRequestResult 接口（确保包含 authResults）
  export interface PermissionRequestResult {
    permissions: string[];
    authResults: number[];
  }
}
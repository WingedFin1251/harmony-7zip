// permissions.d.ts
declare module '@ohos.abilityAccessCtrl' {
  // 使用默认导入 UIAbilityContext（注意使用 import type 或直接 import）
  import type UIAbilityContext from '@ohos.app.ability.common';

  // 或者使用命名空间导入（如果模块既默认导出又包含命名导出，但根据提示应使用默认导入）
  // 但默认导入后，UIAbilityContext 就是该类型本身

  // 定义权限联合类型
  export interface PermissionRequestResult {
    permissions: string[];
    authResults: number[];
  }

  // 定义权限请求结果接口
  export interface PermissionRequestResult {
    permissions: string[];
    authResults: number[];
  }

  // 定义 AbilityAccessCtrl 类
  export class AbilityAccessCtrl {
    requestPermissionsFromUser(
      context: object,          // 使用 object 类型，兼容任何上下文对象
      permissions: string[]     // 直接接受字符串数组
    ): Promise<PermissionRequestResult>;
  }

  const abilityAccessCtrl: {
    createAtManager(): AbilityAccessCtrl;
  };

  export default abilityAccessCtrl;
}
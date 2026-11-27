/**
 * SlTsExtraUtil.mts —— typescript_nodev8 插件单文件引入示例（jsonc
 * plugins.typescript_nodev8.sources 声明，Front 编译期按原始文件名部署到
 * <libDir>\scripts\；块内以 './SlTsExtraUtil.mts' 相对 import 复用，与
 * CsharpCode/JavaCode/COrCplusCode/JsCode 四语言 Code 目录规范同位）。
 *
 * Node >= 22.6 原生类型擦除执行（.mts 扩展名 = ESM + strip-only）。
 */

export const GREET = 'v8ts';

export function addTen(x: number): number {
    return x + 10;
}

export function joinTag(parts: string[]): string {
    return parts.join('|');
}

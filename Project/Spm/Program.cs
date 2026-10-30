// spm：SLang 包/插件管理器（独立 CLI，2026-10-30 自 SlangAllInOne 宿主子命令
// slang spm 独立成工程；部署位 = slang.exe 同目录，直接 `spm <命令>` 驱动）。
//
// 两大命令域：
//   包（module 编译产物，装载即用）→ 安装位 modules\<名>\<名>.module.slb|json
//     - 工程侧：<工程目录>\modules\（slang spm install 项目模式）
//     - 语言侧：<lang>\modules\（-g 全局共享）
//   插件（多层运行时扩展：plugin.jsonc + 原生库 + 前端）→ 安装位
//     <lang>\plugin\<id>\（全局共享，与 Front FindPluginsParent /
//     package-layout.md §7.2 插件安装位一致）。
//
// 服务器协作（registry 基 URL，官网门户 API 约定 = SLangOfficialWebsite
// doc/18-包管理中心spm设计.md §9 + doc/09 §5）：
//   GET <registry>/api/packages/<名>     单包元数据（版本/描述/产物链接）
//   GET <registry>/api/packages          全量索引（search 过滤）
//   GET <registry>/api/plugins/<id>      单插件元数据（版本/支持平台/产物链接）
//   GET <registry>/api/plugins           全量索引
//   静态回落（无门户 API 的简单文件服务器）：<registry>/<名>.json /
//   <registry>/plugins/<id>.json；包体缺省 <registry>/<名>.zip（旧约定）。
//   registry 解析优先级：--registry 参数 > 工程 jsonc "spm"."registry" 段 >
//   <lang>\spm.json 全局（spm config registry 写入）。
//
// 本地版本记录：装包时写 modules\<名>\spm.json（name/version/source/
// installedAt）供 spm outdated 与服务器版本对比；插件版本以
// plugin\<id>\plugin.jsonc 的 plugin.version 为准。

return Spm.Program.Run(args);

namespace Spm
{
    internal static class Program
    {
        public static int Run(string[] args)
        {
            if (args.Length == 0)
            {
                return PrintUsage();
            }
            var cmd = args[0].ToLowerInvariant();
            var rest = args.Skip(1).ToArray();
            return cmd switch
            {
                "install" or "add" => PackageCommands.RunInstall(rest),
                "search" or "find" => PackageCommands.RunSearch(rest),
                "list" or "ls" => PackageCommands.RunList(rest),
                "outdated" or "check" => PackageCommands.RunOutdated(rest),
                "remove" or "uninstall" => PackageCommands.RunRemove(rest),
                "config" => PackageCommands.RunConfig(rest),
                "plugin" or "plugins" => PluginCommands.Run(rest),
                "help" or "--help" or "-h" => PrintUsage(code: 0),
                "version" => PrintVersion(),
                _ => PrintUsage(),
            };
        }

        static int PrintVersion()
        {
            Console.WriteLine("spm 0.2.0 (SLang package & plugin manager)");
            Console.WriteLine($"lang dir: {SpmContext.LangDir}");
            return 0;
        }

        internal static int PrintUsage(int code = 2)
        {
            Console.WriteLine(@"
spm - SLang package & plugin manager

Packages (module artifacts -> modules\<name>\):
  spm install <url|package> [--registry <url>] [-g]
      url      : download a .zip and extract into modules\<package>\
      package  : 1) already in project modules\ -> skip
                 2) found in <lang>\modules\     -> moved into project modules\
                 3) query server GET /api/packages/<name> (fallback <reg>/<name>.json),
                    download meta link or <registry>/<name>.zip
      -g       : install into <lang>\modules\ (global, shared by all projects)
  spm search <keyword>
      Query packages by name (server GET /api/packages/<name> exact hit,
      then GET /api/packages index filter by name/description).
  spm list
      List installed packages in project modules\ and <lang>\modules\.
  spm outdated
      Compare installed package versions against the server
      (local modules\<name>\spm.json vs GET /api/packages/<name>).
  spm remove <package> [-g]
      Delete the package directory (-g = language-wide side).

Plugins (multi-layer runtime extensions -> <lang>\plugin\<id>\):
  spm plugin list
      List installed plugins (reads plugin\<id>\plugin.jsonc).
  spm plugin search <id>
      Query plugin info from server (GET /api/plugins/<id>).
  spm plugin probe <id>
      Environment probe: compare plugin's supported platforms against
      the current host OS/arch (from server meta or installed manifest).
  spm plugin install <id|url> [--registry <url>]
      Download plugin zip (meta link or <registry>/plugins/<id>.zip) and
      extract into <lang>\plugin\<id>\.
  spm plugin remove <id>
      Delete <lang>\plugin\<id>\.

Config:
  spm config registry [<url>]
      Show / set the global registry (stored in <lang>\spm.json).

Registry resolution: --registry > project jsonc ""spm"".""registry"" >
<lang>\spm.json.  Server API contract: SLangOfficialWebsite doc/18 & doc/09.");
            return code;
        }
    }
}

# S语言的工程配置

## 工程

S语言需要配合工程才可以真正的编译使用，即使最终导出javascript或者是csharp的情况，都需要配置管理，相当于在rust中的cargo 一样，所以在使用语言前，要对工程进行配置。

> 2026-10-25 起 `.sp` 工程入口文件**非必需**：同名 `<ProjectName>.jsonc` 存在即认定为合法工程锚点；无 `.sp` 时自动按非 main 入口（库）工程编译（无 `Project{}` 与 `_main_`，导出 `entryMethodId` 为 null）。详见 `project_sp-guide.md` §0。

### 操作
- 新建 在使用语言时，需要先建立工程：工程锚点为同名 `<ProjectName>.jsonc` 配置文件，工程入口为 `<ProjectName>.sp`（非必需）；`.sp` 中以 `Project{}` 类承载入口，`.jsonc` 以 jsonc 格式承载编译配置
- 编辑 在新新工程后，则编译语言的位置，是以工程文件为基地址，进行相对路径查找，所以工程文件就是语言编译时的核心。

### 配置格式
- 在 xxx.ProjectConfig{}的格式文件，里边是配置的核心
    + name 工程的名称
    + compileFile=[] 表示 要编译的文件 以下是对象结构
        - path = "aaaa.s"  编译文件的相对路径
        - group = "temp"    编译分组 all表示 没有组别限制
        - tag = "all"   编译的标签
    + globalVariable 表示 ，全局变量，可定义全局使用的一些内容 可以在文中配合global.PI等方式使用
        - PI = 3.14f
        - minInt = -1i  
- 在Project{}中，一般是函数的入口，或者是静态处理等一些操作
    + static Main(){ } 函数的入口
    + static Test(){} 测试入口，可以配合传入参数，看调用启动不同入口




# GameBox v4.0 — 引擎补丁构建套件 v4

本文件夹提供两种把补丁源码编成 `shadPS4-415907b-patched.exe` 的方式，
任选其一：

## 方式 A：GitHub 云端编译（推荐，电脑零负担）

见上传包根目录的《先看我-GitHub云编译三步搞定-v4.txt》。
三个文件夹（.github / engine / build-engine）拖进仓库，点 Run workflow，
约 1~1.5 小时后下载 Artifacts（shadPS4-415907b-patched-v4）。

云端流程（本套件已内置，自动执行）：
合并源码分卷 → 解压 → 应用 v2 主补丁（10 文件）→ 应用 v3 遮挡查询补丁
（2 文件）→ 应用 v4 Vulkan 默认优化补丁（2 文件）→ 从 GitHub 克隆 45 个
依赖库 + 4 个嵌套依赖（锁定提交）→ 应用依赖构建补丁 → clang-cl 编译 →
产物上传。

## 方式 B：本地编译（需自装工具链）

先装三样（都免费）：
1. Visual Studio 2022 生成工具（勾"使用 C++ 的桌面开发"）
2. Git for Windows —— https://git-scm.com/download/win
3. CMake ≥ 3.24 —— https://cmake.org/download/

然后双击本目录 `build-patched-engine.bat`，全自动：
合并分卷 → 解压 → 应用 v2+v3+v4 补丁 → `restore-submodules.ps1` 克隆依赖 →
CMake(VS 2022 x64) → 编译 → 产物 `output\shadPS4-415907b-patched.exe`。
首次约 40~70 分钟；中断可重跑（已完成步骤自动跳过）。

## 文件清单

```
build-engine/
├── build-patched-engine.bat          一键本地构建（方式 B 入口，产物在 output\）
├── restore-submodules.ps1            45+4 个依赖库克隆脚本（bat 会调）
├── 补丁语法验证程序.cpp               位域布局 + v2 语义断言（g++ -std=c++20 编译运行，exit 0 即通过）
└── source/
    ├── shadps4-sifac4k-source.zip.001   源码分卷 1（16MB）
    └── shadps4-sifac4k-source.zip.002   源码分卷 2（15MB）
```

> 源码分卷合出来的 `shadps4-sifac4k-source.zip`（31MB）与 GameBox v4.0
> 主包 `build-engine\source\` 里的完全一致（MD5 可比对）。
> 云端/本地都会自动合并分卷——**zip 不需要解压**，分卷也不要单独改动。

## 装回 GameBox（关键：两处落位 + 版本管理器勾选，缺一不可）

编译得到 `shadPS4-415907b-patched.exe` 后（详见 `engine\patches\装回说明-v4.txt`）：
1. 复制到 `GameBox-v4.0\engine\shadps4\`（与原版并排，不删原版；DLL 运行库在这里）
2. 再复制一份到 `GameBox-v4.0\build-engine\output\shadPS4-415907b-patched.exe`
   （前端体检页只认这个路径+这个文件名——v2 版"-v2 后缀/放引擎目录"导致
   体检页永远"未找到"的问题已修正）
3. GameBox → 设置 → 版本管理器 → 新增自订 → 选中
   `engine\shadps4\shadPS4-415907b-patched.exe` → 勾选启用（最关键一步！）
4. 验证：设置 → 体检 →「补丁引擎编译产物」就绪；游戏日志出现
   `Present mode: mailbox` / `Vulkan PipelineCacheEnabled: 1`
   / `D16S8 depth format fallback (D24S8) detected: depth-bias units rescaled by 256x`
   与 `Occlusion query (ZpassDone) synthesized`
   （第二次启动起还会出现 `Preloaded N pipelines` = 管线缓存预载入生效）

补丁技术细节见 `engine\patches\修复补丁说明-v4.md`。

# GameBox v5.1 — 引擎补丁构建套件 v5.1

本文件夹提供两种把补丁源码编成 `shadPS4-415907b-patched.exe` 的方式，
任选其一：

## 方式 A：GitHub 云端编译（推荐，电脑零负担）

见上传包根目录的《先看我-GitHub云编译三步搞定-v5.1.txt》。
三个文件夹（.github / engine / build-engine）拖进仓库，点 Run workflow，
约 1~1.5 小时后下载 Artifacts（shadPS4-415907b-patched-v5）。

云端流程（本套件已内置，自动执行）：
合并源码分卷 → 解压 → 应用 v2 主补丁（10 文件）→ 应用 v3 遮挡查询补丁
（2 文件）→ 应用 v4 Vulkan 默认优化补丁（2 文件）→ **应用 v5 GPU 鲁棒
选择补丁（1 文件：选卡校验回退 + 越界钳制 + Using GPU 日志 —— 0x80000003
闪退根因的引擎侧根治）** → 从 GitHub 克隆 45 个依赖库 + 4 个嵌套依赖
（锁定提交）→ 应用依赖构建补丁 → clang-cl 编译 → 产物上传。

## 方式 B：本地编译（需自装工具链）

先装三样（都免费）：
1. Visual Studio 2022 生成工具（勾"使用 C++ 的桌面开发"）
2. Git for Windows —— https://git-scm.com/download/win
3. CMake ≥ 3.24 —— https://cmake.org/download/

然后双击本目录 `build-patched-engine.bat`，全自动：
合并分卷 → 解压 → 应用 v2+v3+v4+v5 补丁 → `restore-submodules.ps1`
克隆依赖 → CMake(VS 2022 x64) → 编译 → 产物 `output\shadPS4-415907b-patched.exe`。
首次约 40~70 分钟；中断可重跑（已完成步骤自动跳过，含 v5 独立标记）。

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

## v5 补丁速览（为什么值得编译一次）

`engine/patches/shadps4-gamebox-v5-gpu-select.patch`（1 文件 76 行）：
- 您遇到的「游戏启动即闪退（0x80000003）」根因是引擎选中了不支持
  Vulkan 1.3 的核显 Intel HD 530 —— v5 给引擎装上校验与自动回退，
  选错卡不再中止进程，而是自动换到最佳卡（GTX 960M）。
- 装回后日志新增 `Using GPU: NVIDIA GeForce GTX 960M (Vulkan 1.4.309)`，
  用哪张卡从此看得见。

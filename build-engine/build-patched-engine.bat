@echo off
rem ============================================================================
rem GameBox v4.0 — shadPS4 渲染修复增强补丁 v2 引擎本地一键构建（Windows）
rem
rem 依赖（装好后再运行本脚本）：
rem   1. Visual Studio 2022 生成工具（含 C++ 桌面开发工作负载）
rem      https://visualstudio.microsoft.com/downloads/ -> "Tools for Visual Studio"
rem   2. Git for Windows          https://git-scm.com/download/win
rem   3. CMake (>= 3.24)          https://cmake.org/download/
rem
rem 用法：把本文件与 source 分卷放在同一文件夹，双击运行（或 cmd 里执行）。
rem 产物：本文件夹下 shadPS4-415907b-patched-v2.exe
rem ============================================================================

setlocal enabledelayedexpansion
cd /d "%~dp0"
set "SRCZIP=shadps4-sifac4k-source.zip"
set "SRCDIR=src\shadps4-sifac4k-main"
set "FFMPEG_SHA=94dde08"

echo.
echo ===== GameBox shadPS4 增强补丁引擎构建 v2 =====
echo.

rem ---- 工具检查 ----
where git >nul 2>nul || (echo [缺] 没找到 git，请先安装 Git for Windows & goto :fail)
where cmake >nul 2>nul || (echo [缺] 没找到 cmake，请先安装 CMake & goto :fail)
echo [OK] git / cmake 就绪

rem ---- 合并分卷（如有）----
if exist "%SRCZIP%" goto :have_zip
set /a parts=0
for %%f in (shadps4-sifac4k-source.zip.0*) do set /a parts+=1
if %parts%==0 (
    echo [缺] 当前文件夹既没有 %SRCZIP% 也没有分卷 .001/.002
    goto :fail
)
echo 正在合并 %parts% 个分卷……
copy /b shadps4-sifac4k-source.zip.* "%SRCZIP%" >nul || goto :fail
echo [OK] 分卷已合并
:have_zip

rem ---- 解压源码 ----
if exist "%SRCDIR%\CMakeLists.txt" (
    echo [OK] 源码已解压，跳过
) else (
    echo 正在解压源码……
    powershell -NoProfile -Command "Expand-Archive -LiteralPath '%SRCZIP%' -DestinationPath 'src' -Force" || goto :fail
    if not exist "%SRCDIR%\CMakeLists.txt" (echo [错误] 解压后未找到源码 & goto :fail)
)

rem ---- 应用补丁 ----
cd /d "%~dp0"
pushd "%SRCDIR%"
if exist .patched-v2 (
    echo [OK] 补丁已应用，跳过
) else (
    echo 正在应用主补丁（10 文件 611 行）……
    rem v2.1: --ignore-whitespace 防止克隆文件 CRLF 行尾导致 patch does not apply
    git apply --check --ignore-whitespace "..\..\engine\patches\shadps4-gamebox-v2-combined.patch" || goto :fail_popd
    git apply --ignore-whitespace "..\..\engine\patches\shadps4-gamebox-v2-combined.patch" || goto :fail_popd
    echo 正在恢复依赖目录（从 GitHub 克隆 45+4 个库，首次约 5-10 分钟）……
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0restore-submodules.ps1" -SourceDir . || goto :fail_popd
    echo 正在应用依赖构建补丁（ffmpeg SHA 覆盖 + IGFD 兼容）……
    rem v2.1: 子模块克隆文件在 Windows 上是 CRLF 行尾，必须加 --ignore-whitespace
    git apply --ignore-whitespace "..\..\engine\patches\ffmpeg-cmake-sha-override.patch" || goto :fail_popd
    git apply --ignore-whitespace "..\..\engine\patches\imguifiledialog-childflags-compat.patch" || goto :fail_popd
    echo ok > .patched-v2
)
echo [OK] 补丁全部就绪

rem ---- CMake 配置 + 编译（VS 2022 生成器，自动并行）----
if not exist build\CMakeCache.txt (
    echo 正在配置 CMake（Visual Studio 2022 x64）……
    cmake -S . -B build -G "Visual Studio 17 2022" -A x64 -DFFMPEG_GIT_SHA=%FFMPEG_SHA% || goto :fail_popd
)
echo 正在编译 shadps4（首次约 40-70 分钟，耐心等待）……
cmake --build build --config Release --target shadps4 --parallel || goto :fail_popd

rem ---- 收集产物 ----
for /R "build" %%f in (shadps4.exe) do (
    copy /y "%%f" "%~dp0shadPS4-415907b-patched-v2.exe" >nul
)
if not exist "%~dp0shadPS4-415907b-patched-v2.exe" (
    echo [错误] 编译完成但没找到 shadps4.exe，请检查上方日志
    goto :fail_popd
)
echo.
echo ===== 构建成功！ =====
echo 产物: %~dp0shadPS4-415907b-patched-v2.exe
echo 替换到 GameBox: 把它改名为 shadPS4-415907b.exe 覆盖 GameBox 主程序目录同名文件
echo.
popd
endlocal
exit /b 0

:fail_popd
popd
:fail
echo.
echo ===== 构建失败 =====
echo 常见原因：
echo   1. 没装 VS2022 生成工具/CMake/Git —— 按文件头链接安装
echo   2. ffmpeg 下载 404 —— 编辑本文件把 FFMPEG_SHA 改为 b0de1dc 或 42557a7
echo   3. 网络波动 —— 直接重跑本脚本（已完成的步骤会自动跳过）
echo   4. 也可以改用 GitHub 云编译（见上传包教程）
endlocal
exit /b 1

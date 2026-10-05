# GameBox v4.0 — shadPS4 源码树子模块恢复（配合 build-patched-engine.bat 使用）
# 源码 zip 的 45 个 externals 目录是空挂载点（git submodule 结构），需从 GitHub 克隆填充。
# 用法: powershell -ExecutionPolicy Bypass -File restore-submodules.ps1 [-SourceDir <路径>]
param(
    [string]$SourceDir = "."
)

$ErrorActionPreference = "Stop"
Set-Location $SourceDir

if (-not (Test-Path ".gitmodules")) {
    Write-Host "[错误] $SourceDir 下没有 .gitmodules，请确认路径指向 shadps4-sifac4k-main"
    exit 1
}

Write-Host "== 第 1 步：解析 .gitmodules（45 个子模块）……" -ForegroundColor Cyan

# 用 git config 解析 INI（子模块名允许含 /，如 externals/aacdec/fdk-aac）
$lines = & git config -f .gitmodules --get-regexp '^submodule\..*\.path$'
$submodules = @()
foreach ($line in $lines) {
    # 形如 "submodule.externals/fmt.path externals/fmt"
    if ($line -match '^submodule\.(.+)\.path\s+(.+)$') {
        $name = $Matches[1]
        $path = $Matches[2]
        $url = (& git config -f .gitmodules --get "submodule.$name.url") 2>$null
        $branch = (& git config -f .gitmodules --get "submodule.$name.branch") 2>$null
        if ($LASTEXITCODE -ne 0) { $branch = $null }
        $submodules += [PSCustomObject]@{ Name = $name; Path = $path; Url = $url; Branch = $branch }
    }
}
Write-Host "共发现 $($submodules.Count) 个子模块。"

Write-Host "== 第 2 步：从 GitHub 克隆（跳过已有内容的目录）……" -ForegroundColor Cyan
$failed = @()
foreach ($sm in $submodules) {
    if ((Test-Path $sm.Path) -and (Get-ChildItem $sm.Path -Force | Measure-Object).Count -gt 0) {
        Write-Host "  跳过（已有内容）: $($sm.Path)"
        continue
    }
    Write-Host "  克隆: $($sm.Path) <- $($sm.Url)$(if ($sm.Branch) { " (分支 $($sm.Branch))" })"
    $args = @("clone", "--depth", "1")
    if ($sm.Branch) { $args += @("--branch", $sm.Branch) }
    $args += @($sm.Url, $sm.Path)
    & git @args
    if ($LASTEXITCODE -ne 0) {
        $failed += $sm.Path
        Write-Host "    [失败] $($sm.Path)" -ForegroundColor Red
    }
}

Write-Host "== 第 3 步：恢复嵌套子依赖（4 个）……" -ForegroundColor Cyan
$nested = @(
    @{ Path = "externals/zydis/dependencies/zycore";      Url = "https://github.com/zyantific/zycore-c.git" },
    @{ Path = "externals/sirit/externals/SPIRV-Headers";  Url = "https://github.com/KhronosGroup/SPIRV-Headers.git" },
    @{ Path = "externals/freetype/subprojects/dlg";       Url = "https://github.com/nyorain/dlg.git" },
    @{ Path = "externals/discord-rpc/thirdparty/rapidjson"; Url = "https://github.com/Tencent/rapidjson.git" }
)
foreach ($n in $nested) {
    if ((Test-Path $n.Path) -and (Get-ChildItem $n.Path -Force | Measure-Object).Count -gt 0) {
        Write-Host "  跳过（已有内容）: $($n.Path)"
        continue
    }
    Write-Host "  克隆: $($n.Path) <- $($n.Url)"
    & git clone --depth 1 $n.Url $n.Path
    if ($LASTEXITCODE -ne 0) {
        $failed += $n.Path
        Write-Host "    [失败] $($n.Path)" -ForegroundColor Red
    }
}

# 结果检查
$emptyDirs = @()
Get-ChildItem "externals" -Directory | ForEach-Object {
    if ((Get-ChildItem $_.FullName -Force | Measure-Object).Count -eq 0) { $emptyDirs += $_.Name }
}

if ($emptyDirs.Count -gt 0 -or $failed.Count -gt 0) {
    Write-Host "`n[警告] 仍有 $($emptyDirs.Count) 个空目录、$($failed.Count) 个克隆失败：" -ForegroundColor Yellow
    $emptyDirs | ForEach-Object { Write-Host "  空: $_" }
    $failed | ForEach-Object { Write-Host "  失败: $_" }
    Write-Host "网络波动时可重跑本脚本（已完成的会自动跳过）。"
    exit 2
}

Write-Host "`n[成功] 全部 $($($submodules.Count + $nested.Count)) 个依赖目录就绪。" -ForegroundColor Green
exit 0

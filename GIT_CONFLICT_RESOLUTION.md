# Git 冲突解决指南（远程服务器）

## 问题
在远程服务器上运行 `git pull origin` 时遇到：
```
error: Your local changes to the following files would be overwritten by merge:
	Manifest.toml
	Project.toml
```

## 解决方案

### 方案 1：暂存本地更改（推荐，如果更改不重要）

```bash
# 在远程服务器上执行
cd /path/to/optim_injr_DT  # 替换为实际路径

# 暂存本地更改
git stash

# 拉取远程更新
git pull origin

# 如果需要恢复本地更改（通常不需要，因为 Manifest.toml 和 Project.toml 会自动更新）
# git stash pop
```

### 方案 2：提交本地更改（如果更改重要）

```bash
# 在远程服务器上执行
cd /path/to/optim_injr_DT

# 查看更改内容
git diff Manifest.toml Project.toml

# 如果更改是合理的（比如添加了新依赖），提交它们
git add Manifest.toml Project.toml
git commit -m "Update Julia dependencies"

# 然后拉取并合并
git pull origin

# 如果有冲突，解决后：
# git add Manifest.toml Project.toml
# git commit -m "Merge remote changes"
```

### 方案 3：强制使用远程版本（最简单，如果本地更改不重要）

```bash
# 在远程服务器上执行
cd /path/to/optim_injr_DT

# 放弃本地更改，使用远程版本
git checkout -- Manifest.toml Project.toml

# 然后拉取
git pull origin
```

### 方案 4：查看差异后决定

```bash
# 在远程服务器上执行
cd /path/to/optim_injr_DT

# 查看远程的更改
git fetch origin
git diff HEAD origin/main -- Manifest.toml Project.toml

# 根据差异决定如何处理
# 如果远程的更新更好，使用方案 3
# 如果本地的更改重要，使用方案 2
```

## 推荐操作（对于 Manifest.toml 和 Project.toml）

对于 Julia 的 `Manifest.toml` 和 `Project.toml` 文件，通常建议：

1. **使用远程版本**（方案 3），因为这些文件通常由 `Pkg` 自动管理
2. 如果本地有重要的依赖更改，先提交再拉取（方案 2）

## 快速解决（推荐）

```bash
# 在远程服务器上执行
cd /path/to/optim_injr_DT

# 放弃本地更改，使用远程版本
git checkout -- Manifest.toml Project.toml

# 拉取更新
git pull origin

# 如果需要，重新生成依赖
julia --project=. -e "using Pkg; Pkg.instantiate()"
```

## 检查状态

```bash
# 检查 Git 状态
git status

# 检查是否与远程同步
git log --oneline -5
git fetch origin
git log --oneline origin/main -5
```


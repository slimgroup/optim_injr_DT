# 多机器开发工作流程指南

## 🖥️ 机器配置

- **PACE集群**: `/storage/coda1/p-fherrmann9/0/hli853/optim_injr_DT`
  - 用途：运行计算任务、生成数据
  - 特点：有大量本地文件（日志、数据、图片）

- **SSH机器**: 你的开发机器
  - 用途：代码开发、测试
  - 特点：干净的工作环境

- **中央仓库**: GitHub (`git@github.com:haoyunl2/optim_injr_DT.git`)
  - 用途：代码同步、版本控制

---

## 🔄 推荐工作流程：GitHub作为中央仓库

### 核心原则
1. **GitHub是唯一真相源**：所有代码更改都通过GitHub同步
2. **先拉后推**：开始工作前先拉取最新代码
3. **只同步代码**：数据/日志保留在各自机器本地

---

## 📋 标准工作流程

### 在PACE上工作

```bash
# 1. 开始工作前：拉取最新代码
git pull origin main

# 2. 进行开发/修改
vim src/threshold_sensitivity.jl

# 3. 只添加代码文件
git add src/threshold_sensitivity.jl

# 4. 检查状态（确认不提交本地文件）
git status

# 5. 提交
git commit -m "描述你的修改"

# 6. 推送到GitHub
git push origin main
```

### 在SSH机器上工作

```bash
# 1. 开始工作前：拉取最新代码
git pull origin main

# 2. 进行开发/修改
vim src/threshold_sensitivity.jl

# 3. 添加文件
git add src/threshold_sensitivity.jl

# 4. 提交
git commit -m "描述你的修改"

# 5. 推送到GitHub
git push origin main
```

---

## ⚠️ 避免冲突的最佳实践

### 1. 工作前总是先拉取
```bash
# 在开始工作前，先拉取最新代码
git pull origin main
```

### 2. 频繁提交和推送
```bash
# 完成一个小功能就提交推送，避免长时间不同步
git add <files>
git commit -m "小功能描述"
git push origin main
```

### 3. 如果遇到冲突
```bash
# 拉取时如果有冲突
git pull origin main

# 如果有冲突，Git会提示
# 手动解决冲突后
git add <resolved-files>
git commit -m "Resolve merge conflict"
git push origin main
```

---

## 🎯 场景示例

### 场景1：在SSH机器上开发，在PACE上运行

```bash
# === 在SSH机器上 ===
# 1. 拉取最新代码
git pull origin main

# 2. 开发新功能
vim src/new_feature.jl
git add src/new_feature.jl
git commit -m "Add new feature"
git push origin main

# === 切换到PACE ===
# 3. 拉取新代码
git pull origin main

# 4. 运行任务
sbatch scripts/shell/submit_job.sh

# 5. 如果有bug修复
vim src/new_feature.jl  # 修复bug
git add src/new_feature.jl
git commit -m "Fix bug in new feature"
git push origin main

# === 回到SSH机器 ===
# 6. 拉取修复
git pull origin main
```

### 场景2：两台机器同时工作（不同文件）

```bash
# === PACE：修改 threshold_sensitivity.jl ===
git pull origin main
vim src/threshold_sensitivity.jl
git add src/threshold_sensitivity.jl
git commit -m "Fix threshold sensitivity"
git push origin main

# === SSH机器：修改 optim_inject.jl ===
git pull origin main  # 获取PACE的更改
vim src/optim_inject.jl
git add src/optim_inject.jl
git commit -m "Update optimization"
git push origin main

# === PACE：获取SSH的更改 ===
git pull origin main  # 获取SSH机器的更改
```

---

## 🔧 设置辅助脚本（可选）

### 在PACE上创建快捷脚本

```bash
# 创建 ~/git-sync-pace.sh
cat > ~/git-sync-pace.sh << 'EOF'
#!/bin/bash
# PACE机器上的Git同步脚本

cd /storage/coda1/p-fherrmann9/0/hli853/optim_injr_DT

echo "=== 拉取最新代码 ==="
git pull origin main

echo ""
echo "=== 当前状态 ==="
git status --short

echo ""
echo "=== 最近5次提交 ==="
git log --oneline -5
EOF

chmod +x ~/git-sync-pace.sh
```

### 在SSH机器上创建快捷脚本

```bash
# 创建 ~/git-sync-ssh.sh
cat > ~/git-sync-ssh.sh << 'EOF'
#!/bin/bash
# SSH机器上的Git同步脚本

cd /path/to/optim_injr_DT  # 修改为你的实际路径

echo "=== 拉取最新代码 ==="
git pull origin main

echo ""
echo "=== 当前状态 ==="
git status --short

echo ""
echo "=== 最近5次提交 ==="
git log --oneline -5
EOF

chmod +x ~/git-sync-ssh.sh
```

---

## 📝 检查清单

### 开始工作前
- [ ] `git pull origin main` - 拉取最新代码
- [ ] `git status` - 检查当前状态

### 提交前
- [ ] `git status` - 确认只提交代码文件
- [ ] `git diff --cached` - 检查要提交的更改

### 提交后
- [ ] `git push origin main` - 推送到GitHub
- [ ] 在另一台机器上 `git pull origin main` - 同步更改

---

## 🚨 常见问题

### Q: 如果忘记先pull就push了？
```bash
# 如果远程有更新，push会失败
git push origin main
# 错误：Updates were rejected

# 解决方案：先pull再push
git pull origin main
# 如果有冲突，解决后
git push origin main
```

### Q: 如何查看两台机器的差异？
```bash
# 查看本地和远程的差异
git fetch origin
git log HEAD..origin/main  # 远程有但本地没有的提交
git log origin/main..HEAD  # 本地有但远程没有的提交
```

### Q: 如何撤销本地的未提交更改？
```bash
# 查看更改
git status

# 撤销工作区的更改（危险！）
git restore <file>

# 撤销暂存区的更改
git restore --staged <file>
```

---

## 💡 最佳实践总结

1. **GitHub是中心**：所有代码都通过GitHub同步
2. **先拉后推**：工作前先pull，完成后push
3. **频繁同步**：小改动就提交推送，避免大冲突
4. **只同步代码**：数据/日志保留在各自机器
5. **清晰提交信息**：便于追踪更改历史

---

## 🔗 快速参考

```bash
# 标准工作流
git pull origin main          # 拉取
git add <files>               # 添加
git commit -m "message"       # 提交
git push origin main          # 推送

# 检查状态
git status                    # 当前状态
git log --oneline -10         # 提交历史
git diff                      # 查看更改
```


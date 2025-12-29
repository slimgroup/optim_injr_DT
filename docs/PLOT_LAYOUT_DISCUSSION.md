# Histogram布局优化讨论

## 当前设置（2025-12-28更新）

### 字体大小
- **小标题**：13（已减小）
- **轴标签**（Injectivity/Frequency）：16（已增大）
- **坐标轴数字**：13
- **主标题**：18

### 布局参数
- **Figure size**: `(4.0*ncols, 3.0*nrows)` - 对于20个cases（5行4列）= (16.0, 15.0)
- **Subplot spacing**: 
  - `wspace=0.25` - 子图之间的水平间距
  - `hspace=0.35` - 子图之间的垂直间距
- **Margins**:
  - `left=0.08, right=0.95` - 左右边距
  - `top=0.94, bottom=0.06` - 上下边距

## 关于Histogram压缩和留白的讨论

### 当前可能的问题

1. **Histogram看起来压缩**：
   - 20个cases需要5行4列的网格，每个subplot相对较小
   - 如果数据分布范围很大，histogram可能会显得"压缩"

2. **留白过多**：
   - 可能的原因：
     - `wspace` 和 `hspace` 设置过大
     - `figsize` 相对于内容过大
     - `tight_layout` 和 `subplots_adjust` 的冲突

### 优化选项

#### 选项1：减少子图间距（更紧凑）
```julia
PyPlot.subplots_adjust(left=0.08, right=0.95, top=0.94, bottom=0.06, 
                       wspace=0.15, hspace=0.25)  # 减小间距
```

#### 选项2：增大每个subplot的尺寸
```julia
fig = PyPlot.figure(figsize=(4.5*ncols, 3.5*nrows))  # 增大整体尺寸
```

#### 选项3：调整bin数量
```julia
const NBINS = 25  # 从30减少到25，让histogram看起来更"宽松"
```

#### 选项4：使用不同的布局策略
- 可以考虑分成两个图（每个10个cases）
- 或者使用更宽的布局（比如6列4行，但最后一行只有4个）

### 建议的调整方向

**如果histogram看起来压缩**：
1. 减少bin数量（从30到20-25）
2. 增大figure size
3. 检查数据范围，可能需要log scale

**如果留白太多**：
1. 减小 `wspace` 和 `hspace`（当前0.25/0.35可以减到0.15/0.25）
2. 调整margins（left/right/top/bottom）
3. 确保没有使用 `tight_layout` 和 `subplots_adjust` 同时使用

### 测试建议

可以尝试以下组合：

```julia
# 更紧凑的版本
PyPlot.subplots_adjust(left=0.07, right=0.96, top=0.95, bottom=0.05, 
                       wspace=0.15, hspace=0.25)

# 或者更宽松的版本（如果histogram太压缩）
fig = PyPlot.figure(figsize=(4.5*ncols, 3.5*nrows))
PyPlot.subplots_adjust(left=0.08, right=0.95, top=0.94, bottom=0.06, 
                       wspace=0.20, hspace=0.30)
```

### 当前设置的优势

- 字体大小已经优化（小标题13，轴标签16）
- 使用 `subplots_adjust` 可以精确控制间距
- Figure size已经适当增大（4.0 x 3.0 per subplot）

### 需要进一步调整的地方

根据实际查看图片的效果，可以：
1. 如果histogram bars太窄 → 减少NBINS
2. 如果subplot之间空白太多 → 减小wspace/hspace
3. 如果整体图片太大 → 减小figsize
4. 如果数据分布需要更好展示 → 考虑使用log scale或调整bin edges


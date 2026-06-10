# AutoCAD for Mac Dogbone AutoLISP Plugin

当前主文件 `dogbone.lsp` 是 `V2.1-Nest` 版本。

`dogbone-v2.0-stable.lsp` 保留为 V2.0 备份版本。

目标 Dogbone 类型已确认使用 `C 45 Degree Dogbone`。

`DBAUTO` 会读取闭合直线段 `LWPOLYLINE`，识别材料内角，按 C 型 45 度 dogbone 生成新的闭合 `LWPOLYLINE`。默认删除原始轮廓，避免新旧线重叠。

## 文件

- `dogbone.lsp`: 可直接加载到 AutoCAD for Mac 的 AutoLISP 插件。

## 加载方式

1. 在 AutoCAD for Mac 中打开图纸。
2. 输入 `APPLOAD`。
3. 选择本文件夹里的 `dogbone.lsp`。
4. 命令行出现 `Dogbone plugin V2.1-Nest loaded. Commands: DBSET, DB1, DBDEBUG, DBAUTO, DBADD, DBRESTORE, DBRESTOREALL, DBNSET, DBNEST.` 后即可使用。

## 命令

### DBSET

设置参数：

- Tool diameter: 刀具直径，默认 `6.0`。
- Process contained hole outlines: 是否处理被外轮廓包含的孔洞轮廓，默认 `Yes`。

其他生产参数已固定隐藏：

- Dogbone type: 固定为 `C 45 Degree Dogbone`。
- Duplicate tolerance: 固定为 `0.01mm`。
- 90 degree tolerance: 固定为 `0.1°`。
- Keep original: 固定为 `No`，生成新轮廓后删除原始 polyline。
- Debug mode: 固定为 `No`。
- Preview markers: 固定为 `No`。

### DB1

单角几何验证命令。依次点击：

1. 角点。
2. 角点前一条边的方向点。
3. 角点后一条边的方向点。

插件会同时生成三种测试方案：

- `DB_TEST_A`: Offset-Center Dogbone，圆心沿角平分线偏移，圆与两边相切。
- `DB_TEST_B`: Corner-Centered Relief，圆心在原始角点。
- `DB_TEST_C`: 45 Degree Dogbone，圆心沿 45 度释放方向移动一个刀具半径。

当前已确认 `DB_TEST_C` 是目标类型。这个命令仍保留，方便以后更换刀具或复查几何。

### DBDEBUG

选择闭合 `LWPOLYLINE` 后只生成调试标记，不生成生产轮廓：

- `DBDEBUG_CORNER`: 识别到的角点。
- `DBDEBUG_CENTER`: dogbone 圆心。
- `DBDEBUG_TANGENT`: 两个截断点。
- `DBDEBUG_DIRECTION`: dogbone 方向线。
- `DBDEBUG_TEXT`: 角度标注。
- `DBDEBUG_CIRCLE`: 参考切割圆。

### DBAUTO

批量命令。选择一条或多条闭合 `LWPOLYLINE` 后，插件会：

- 跳过未闭合、多段线顶点不足、面积无效的对象。
- 跳过带 bulge 弧线段的多段线，并在命令行提示数量。
- 对外轮廓凹角生成 C 型 45 度 dogbone。
- 对被外轮廓包含的孔洞轮廓，在开启孔洞处理时处理孔洞角点。
- 输出新的闭合 `LWPOLYLINE`，保持原图层和基本属性。
- 默认删除原始 polyline，避免与新轮廓重叠。

### DBADD

局部新增 dogbone。用于某些内角漏做 dogbone 的情况。

流程：

1. 选择一条或多条闭合 `LWPOLYLINE`。
2. 框选一片区域，区域内的可处理内角都会补 dogbone。
   - 小框可以只处理一个角。
   - 大框可以一次处理多个角。
3. 插件生成新的闭合 polyline，并删除旧 polyline。

### DBRESTORE

还原 dogbone 为尖角。用于撤销某些 dogbone，或者先还原再用新刀具尺寸重做。

流程：

1. 选择一条或多条已有 dogbone 的闭合 `LWPOLYLINE`。
2. 框选一片区域，区域内的 dogbone 都会还原。
   - 小框可以只还原一个 dogbone。
   - 大框可以一次还原多个 dogbone。
3. 插件生成新的闭合 polyline，并删除旧 polyline。

### DBRESTOREALL

批量还原整条多段线里的所有 dogbone。这个命令与 `DBAUTO` 对称：

- `DBAUTO`: 选择多段线，批量生成 dogbone。
- `DBRESTOREALL`: 选择多段线，批量取消 dogbone，恢复尖角。

流程：

1. 选择一条或多条已有 dogbone 的闭合 `LWPOLYLINE`。
2. 插件自动识别整条 polyline 里的 dogbone。
3. 插件生成还原后的新闭合 polyline，并删除旧 polyline。

如果要修改已有 dogbone 大小，推荐流程：

```text
DBRESTORE 还原需要修改的 dogbone
DBSET 设置新的刀具直径
DBADD 或 DBAUTO 重新生成 dogbone
```

### DBNSET

设置排料（Nesting）间距参数。

- 输入新的间距值（单位与图纸一致，通常为 mm）。
- 直接回车保持当前值。
- 默认间距为 `6.0`。

### DBNEST

排料命令。将选中的零件按间距排进一个矩形板框内。

流程：

1. 选择要排料的零件（支持 `LWPOLYLINE` 和 `INSERT` 块参照）。
2. 点选一个矩形闭合多段线作为板框（必须是 4 顶点闭合 LWPOLYLINE）。
3. 插件自动按面积从大到小排序，使用层架（Shelf）算法排布。
4. 排得下的零件移入板框，排不下的留在原位。
5. 命令行显示统计：共几个零件、排入几个、剩余几个。
6. 支持 `UNDO` 一步撤销。

排料使用流程：

```text
DBNSET       可选，先设置零件间距
DBNEST       选择零件 → 选择板框 → 自动排布
```

## 几何规则

对每个顶点取：

- `P0`: 前一点
- `P1`: 当前角点
- `P2`: 后一点

计算：

- `v1 = normalize(P0 - P1)`
- `v2 = normalize(P2 - P1)`
- `theta = angle(v1, v2)`
- `dir = normalize(v1 + v2)`
- `center = P1 + dir * R`
- `trim = 2 * R * cos(theta / 2)`
- `A = P1 + v1 * trim`
- `B = P1 + v2 * trim`

直角时：

- 圆心距离角点等于 `R`。
- 两侧截断点距离角点等于 `R * sqrt(2)`。
- 使用绿色参考圆中靠近原角点的那一段圆弧重建 polyline。
- 对 90° C 型 dogbone，这段圆弧是半圆，bulge 绝对值为 `1.0`。

## V2.1-Nest 限制

- 仅支持闭合 `LWPOLYLINE`。
- 仅处理直线段。
- 不处理普通 `POLYLINE`、样条曲线、圆弧段。
- 成功生成新闭合 polyline 后，默认删除原始 polyline。
- 孔洞识别基于"所选多段线之间的包含关系"。建议批量处理时同时选择外轮廓和内部孔洞轮廓。
- `DBRESTORE` 当前主要面向 V2.0/V2.1 生成的 90° C 型 dogbone 半圆。
- 排料算法为简单层架（Shelf）排布，不做旋转优化。
- 排料仅基于 AABB 包围盒，不考虑零件实际轮廓的嵌套。

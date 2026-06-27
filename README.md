# AutoCAD for Mac Dogbone AutoLISP Plugin

当前主文件 `dogbone.lsp` 是 `V2.1-Nest-Compact-500` 版本。

`dogbone-v2.0-stable.lsp` 保留为 V2.0 备份版本。

目标 Dogbone 类型已确认使用 `C 45 Degree Dogbone`。

`DBAUTO` 会读取闭合 `LWPOLYLINE`，识别 sharp line-line 材料内角，按 C 型 45 度 dogbone 生成新的闭合 `LWPOLYLINE`。默认删除原始轮廓，避免新旧线重叠。

## 文件

- `dogbone.lsp`: 可直接加载到 AutoCAD for Mac 的 AutoLISP 插件。

## 加载方式

1. 在 AutoCAD for Mac 中打开图纸。
2. 输入 `APPLOAD`。
3. 选择本文件夹里的 `dogbone.lsp`。
4. 命令行出现 `Dogbone plugin V2.1-Nest-Compact-500 loaded. Commands: DBVER, DBSET, DB1, DBDEBUG, DBAUTO, DBADD, DBRESTORE, DBRESTOREALL, DBNSET, DBNEST, DBNESTM.` 后即可使用。
5. 如需确认 AutoCAD 当前加载的是这份文件，输入 `DBVER`，应显示 `V2.1-Nest-Compact-500`。

## 命令

### DBVER

显示当前加载的插件版本和命令列表。排查加载旧文件时先运行这个命令。

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

批量命令。可以选择一条或多条闭合 `LWPOLYLINE`，也可以选择比例为 `1:1` 的 `INSERT` 块参照。

选择块参照时，插件会通过 `entmod` 原位修改其共享块定义内的多段线，因此图中所有同名块实例都会同步更新。选中多个同名块实例时，同一块定义只处理一次。块参照本身不会被炸开、删除或重建，模型空间也不会额外生成一套独立的 dogbone 多段线。

插件会：

- 跳过未闭合、多段线顶点不足、面积无效的对象。
- 接受带 bulge 弧线段的闭合多段线；未命中的原有圆弧段会被保留。
- 对 sharp line-line 材料内角，以及非相切的直线–圆弧材料内角生成 C 型 dogbone；平滑相切的圆角和外凸榫头角会跳过。
- 当候选角一侧直线太短，标准 C 型 dogbone 放不下时，会使用短边 fallback：保留短边终点，在长边上反算另一端点，用刀具半径 `R` 的半圆弧连接。
- 自动识别由至少 `24` 条直线组成的偶数对称闭合分段圆：圆心取任一顶点与其对向顶点的中点，各组对向顶点中点和所有顶点半径的误差均不得超过 `0.1%`；识别后不会对这些顶点生成 dogbone。
- 直接选择的分段圆会转换为真正的 `CIRCLE`；块定义内的分段圆会原位转换为由两个精确半圆弧组成的闭合 `LWPOLYLINE`，以保留块归属和同步更新所有同名块实例。
- 已识别的分段圆仍参与孔洞包含关系判断；若转换失败，则保留原对象并在命令行报告失败数量。
- 跳过非 `1:1` 缩放、外部参照、匿名/动态块，以及没有直接包含 `LWPOLYLINE` 的块。
- 只处理块定义直接包含的 `LWPOLYLINE`；不会递归修改嵌套块定义。
- 对外轮廓凹角生成 C 型 45 度 dogbone。
- 对被外轮廓包含的孔洞轮廓，在开启孔洞处理时处理孔洞角点。
- 普通轮廓输出新的闭合 `LWPOLYLINE`，保持原图层和基本属性。
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
- 组件间距默认 `6.0`，用于组件与组件之间。
- 边缘留边默认 `2.0`，用于组件到板框外缘之间。

### DBNEST

默认排料命令。将选中的零件按间距自动分配到一个或多个相同尺寸的矩形板框内。

运行时会输出 `DBNEST-DIAG`，包含当前版本、原始选择实体数、分组组件数、板框间距、组件间距、边缘留边、最终选用的排序策略和尾板回填状态。若看不到 `V2.1-Nest-Compact-500`，说明 AutoCAD 没有加载当前这份 `dogbone.lsp`。

排版移动、旋转和复制会使用 AutoCAD 的 `_non` 坐标输入，避免当前对象捕捉（例如交点捕捉）改写脚本计算出的基点和目标点。

流程：

1. 选择要排料的零件（支持 `LWPOLYLINE`、`INSERT` 块参照和 `CIRCLE`）。
2. 点选一个矩形闭合多段线作为板框模板（必须是 4 顶点闭合 LWPOLYLINE）。
3. 输入复制板框之间的水平间距，直接回车使用默认 `500.0`；输入 `0` 会保留默认正间距。
4. 插件会尝试面积、宽度、高度、长边等多种排序策略，使用 AABB MaxRects 空矩形算法分别试排，并选择使用板框更少、占用更紧凑的一版。
5. 每个空矩形会尝试左下、右下、左上、右上四种贴边位置；每个位置都会比较原方向和 90 度旋转方向，在可放入的位置中选择更紧凑的一种。
6. 每种试排策略完成后，会尝试把最后一块板上的零件重新塞回前面板框；如果全部能塞回去，就取消这块低占用新版面。
7. 被更大外轮廓包住的内孔、内槽和圆孔会归到同一个组件一起移动。
8. 如果当前板框放不下，会自动向右寻找空白区域，复制一个相同板框继续排。
9. 原始板框内已有 `LWPOLYLINE`、`INSERT` 或 `CIRCLE` 会作为已占用障碍避开，避免二次排版重叠。
10. 命令行显示统计：共几个组件、排入几个、剩余几个、使用几个板框。
11. 支持 `UNDO` 一步撤销。

排料使用流程：

```text
DBNSET       可选，先设置零件间距
DBNEST       选择零件 → 选择板框模板 → 输入板框间距 → 自动多板排布
```

### DBNESTM

兼容旧习惯的多板排料入口，当前与 `DBNEST` 使用同一套自动多板排版流程。

流程：

1. 选择要排料的零件（支持 `LWPOLYLINE`、`INSERT` 块参照和 `CIRCLE`）。
2. 点选一个矩形闭合多段线作为板框模板。
3. 输入复制板框之间的水平间距，直接回车使用默认 `500.0`；输入 `0` 会保留默认正间距。
4. 插件先尝试把零件排进已有板框，放不下时自动向右寻找空白区域并复制一个板框继续排。
5. 每个零件会尝试原方向和 90 度旋转方向。
6. 原始板框内已有 `LWPOLYLINE` 或 `INSERT` 会作为已占用障碍避开。
7. 命令行显示统计：共几个零件、排入几个、剩余几个、使用几个板框。
8. 支持 `UNDO` 一步撤销。

多板排料使用流程：

```text
DBNSET       可选，先设置零件间距
DBNESTM      选择零件 → 选择板框模板 → 输入板框间距 → 自动多板排布
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

- Dogbone 几何仅支持闭合 `LWPOLYLINE`；`DBAUTO` 也可通过 `1:1 INSERT` 修改块定义内直接包含的闭合 `LWPOLYLINE`。
- 支持直线段，以及 `LWPOLYLINE` 内的 bulge 圆弧段；当前自动 dogbone 只处理 sharp line-line 候选，短边场景使用专用 fallback。
- 不处理普通 `POLYLINE`、样条曲线、独立 `ARC` 实体。
- 块模式不支持缩放块、匿名/动态块、外部参照或递归处理嵌套块定义。
- 成功生成新闭合 polyline 后，默认删除原始 polyline。
- 孔洞识别基于"所选多段线之间的包含关系"。建议批量处理时同时选择外轮廓和内部孔洞轮廓。
- `DBRESTORE` 当前主要面向 V2.0/V2.1 生成的 90° C 型 dogbone 半圆。
- 排料算法为 AABB MaxRects 启发式排布，会尝试多种排序策略、空矩形四角贴边位置、0 度和 90 度两个方向，以及尾板回填消板，并会把 LWPOLYLINE 的 bulge 圆弧极值和 CIRCLE 圆孔计入包围盒，但不是全局最优排料。
- 排料会按包围盒包含关系把内孔、内槽归入外轮廓一起移动；若图中有独立小零件完全画在大零件包围盒内部，会被视为该大零件的一部分。
- `DBNESTM` 复制的新板框默认向右排列；如果候选板框区域已有图形，会自动跳过并继续向右寻找下一个空白区域。
- 排料仅基于 AABB 包围盒，不考虑零件实际轮廓的嵌套。

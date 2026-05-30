# AutoCAD for Mac Dogbone AutoLISP Plugin

当前稳定版本：`V2.0`。目标 Dogbone 类型已确认使用 `C 45 Degree Dogbone`。

`DBAUTO` 会读取闭合直线段 `LWPOLYLINE`，识别材料内角，按 C 型 45 度 dogbone 生成新的闭合 `LWPOLYLINE`。默认删除原始轮廓，避免新旧线重叠。

## 文件

- `dogbone.lsp`: 可直接加载到 AutoCAD for Mac 的 AutoLISP 插件。

## 加载方式

1. 在 AutoCAD for Mac 中打开图纸。
2. 输入 `APPLOAD`。
3. 选择本文件夹里的 `dogbone.lsp`。
4. 命令行出现 `Dogbone plugin V2.0 loaded. Commands: DBSET, DB1, DBDEBUG, DBAUTO.` 后即可使用。

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

## V2.0 限制

- 仅支持闭合 `LWPOLYLINE`。
- 仅处理直线段。
- 不处理普通 `POLYLINE`、样条曲线、圆弧段。
- 成功生成新闭合 polyline 后，默认删除原始 polyline。
- 孔洞识别基于“所选多段线之间的包含关系”。建议批量处理时同时选择外轮廓和内部孔洞轮廓。

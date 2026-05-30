# Changelog

## [1.0.0] - 2026-05-30

首次 GitHub 发布版本。代码内部版本标识为 V2.0 Stable。

- 确认目标类型为 `C 45 Degree Dogbone`。
- `DBSET` 只保留刀具直径和是否处理孔洞轮廓。
- `DBAUTO` 读取闭合直线段 `LWPOLYLINE`，生成新的闭合 `LWPOLYLINE`。
- 成功生成新轮廓后删除原始 polyline，避免重叠。
- 默认关闭调试显示和预览标记。
- `DBDEBUG` 保留为单独调试命令。
- `DB1` 保留为单角几何验证命令。
- 90 度 C 型 dogbone 使用靠近原角点的半圆，`abs(bulge) = 1.0`。

当前限制：

- 仅支持闭合 `LWPOLYLINE`。
- 仅处理直线段。
- 跳过已有 bulge 的 polyline。
- 不处理 `POLYLINE`、`SPLINE`、`ARC`、`CIRCLE`。
- 孔洞识别只做基础包含关系判断。

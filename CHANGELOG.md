# Changelog

## [2.1.0] - 2026-05-30

新增 V2.1 本地编辑能力：

- 新增 `DBADD`，通过框选区域给漏掉的尖角局部新增 dogbone。
- 新增 `DBRESTORE`，通过框选区域把已有 C 型 dogbone 还原为尖角。
- 新增 `DBRESTOREALL`，选择多段线后批量还原整条 polyline 中所有 dogbone，与 `DBAUTO` 形成生成/取消闭环。
- 不做直接修改 dogbone 大小；推荐流程为 `DBRESTORE -> DBSET -> DBADD/DBAUTO`。
- `DBADD` 可读取已经包含 dogbone bulge 的闭合 LWPOLYLINE。
- `DBRESTORE` 当前主要识别 V2.0/V2.1 生成的 90° C 型 dogbone 半圆。

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

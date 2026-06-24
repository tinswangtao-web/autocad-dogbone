# Changelog

## [Unreleased]

- 修复 `DBAUTO` 选择块参照时无法生成 dogbone 的问题。
- 支持选择比例为 `1:1` 的 `INSERT`，直接修改其共享块定义，使所有同名块实例同步更新。
- 同一块定义在一次选择中只处理一次，避免重复生成 dogbone。
- 修正首版块支持的实体归属问题：改用 `entmod` 原位更新块定义内的多段线，不再在模型空间生成独立多段线，并保持原对象为 `INSERT`。
- 当前只处理块定义直接包含的闭合直线段 `LWPOLYLINE`；缩放块、匿名/动态块、外部参照和嵌套块定义会被跳过。

## [2.1-Nest] - 2026-06-10

新增排料（Nesting）功能：

- 新增全局变量 `*db-nest-gap*`，默认间距 `6.0`。
- 新增 `DBNSET`，设置排料零件间距。
- 新增 `DBNEST`，选择零件和板框后自动按层架（Shelf）算法排布。
- 支持 `LWPOLYLINE` 和 `INSERT` 块参照作为零件。
- 块参照支持递归解析嵌套块内的 LWPOLYLINE 顶点。
- 零件按 AABB 面积从大到小排列，使用层架算法逐行填充。
- 零件可以贴着板框边缘放置，零件之间保持设定间距。
- 排不下的零件留在原位不移动。
- 操作包裹在 UNDO 组内，支持一步撤销。
- 版本号更新为 `V2.1-Nest`。

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

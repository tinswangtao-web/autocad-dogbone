# Changelog

## [Unreleased]

- `DBAUTO` 不再一概跳过带 bulge 的闭合多段线；未命中的原有圆弧段会被保留。
- 修正带弧轮廓上的错误候选：现有 C 型 dogbone 只自动应用于 sharp line-line 材料内角，不再把 line-arc 接点或外凸榫头角套用到凹角算法上。
- 新增短边 fallback：候选角若一侧短边不足以放下标准 C 型 dogbone，则保留短边端点，在长边上按实际夹角反算端点并生成刀具半径圆弧。
- 修复 AutoCAD 报错时的 undo 清理：`db:start-undo` / `db:end-undo` 改用 `command-s`，避免从 `*error*` 处理器调用普通 `command`。
- 修复短边 fallback 成功时返回布尔 `T` 的问题：AutoLISP 的 `or` 不返回实际 patch list，现改为显式 fallback helper，避免 `listp T`。
- `DBAUTO` 自动识别 SketchUp 导出的偶数对称分段圆：至少 `24` 个顶点，以对向顶点中点确定圆心，并要求对称中心及半径误差均不超过 `0.1%`。
- 分段圆不再逐顶点生成 dogbone；直接对象转换为 `CIRCLE`，块内对象原位转换为两个精确半圆 bulge 组成的闭合 `LWPOLYLINE`。
- 新增分段圆检测、转换成功和转换失败统计；转换失败时保留原对象。
- 修复 `DBAUTO` 选择块参照时无法生成 dogbone 的问题。
- 支持选择比例为 `1:1` 的 `INSERT`，直接修改其共享块定义，使所有同名块实例同步更新。
- 同一块定义在一次选择中只处理一次，避免重复生成 dogbone。
- 修正首版块支持的实体归属问题：改用 `entmod` 原位更新块定义内的多段线，不再在模型空间生成独立多段线，并保持原对象为 `INSERT`。
- 当前只处理块定义直接包含的闭合 `LWPOLYLINE`；缩放块、匿名/动态块、外部参照和嵌套块定义会被跳过。

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

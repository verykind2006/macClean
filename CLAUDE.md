# macClean

用户要在这里自己写一个小工具，专门清理 Mac 的硬盘空间。

- 背景、分类规则和踩过的坑都在本项目的自动记忆里（MEMORY.md 会自动加载）：2026-11-16 Mac mini 清理经过、可删 / 要问 / 不能动 分类、踩过的坑。
- 工具原则：**先分析、后删除**，每项删除都要用户确认；衡量效果用 `df` 前后对比，不用 du 的总和；`~/Library/CloudStorage/OneDrive-个人/` 下的文件绝不能用 rm 删。
- 两台机器：Mac mini（VKMac-Mini）和 MacBook，两边的目录结构基本相同。

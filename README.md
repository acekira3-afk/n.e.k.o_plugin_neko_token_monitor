# 猫粮 · YUI 桌面陪伴与余额挂件

导入 `.neko-plugin` 后启动。在人物旁的 ≡ 菜单打开「账户设置」，直接在猫粮窗口内配置，无需浏览器或命令行。

## 查询方式

界面始终叫「猫粮余额」，下方明确显示数据来源。

| 方式 | 含义 | 所需设置 |
| --- | --- | --- |
| DeepSeek | 官方账户余额 | API Key |
| OpenAI / GPT | 自定预算减组织已用费用，非平台余额 | Admin API Key、USD 预算与起始日期 |
| Anthropic / Claude | 自定预算减组织已用费用，非平台余额；不含 Priority Tier | 有组织费用查询权限的密钥、USD 预算与起始日期 |
| 自定义服务商 | 用户指定 HTTPS GET 接口返回的余额 | 地址、Bearer 密钥、JSON 金额字段路径 |
| 任意模型 | 手动预算，不自动扣减 | 金额、币种、模型备注 |

模型名称仅作备注；组织费用包含全部模型，不能当作单模型用量。ChatGPT/Claude 订阅额度、API 账户余额和上下文剩余量不是同一项。可用 token 仅按用户填写的综合单价估算，不代表平台承诺。

## 互动与记录

- 点人物：弹跳、显示带「喵～」的台词，并请求 NEKO 原角色回应。是否出声取决于原软件语音设置；回应请求有 30 秒冷却。
- 点气泡：切换余额与 Agent 空闲/忙碌状态。
- 记录模式期间隐藏 NEKO 原界面。退出后恢复原界面，显示摸头、询问计数。
- 摸头指点击人物；询问指点击气泡。退出时通过 NEKO 记忆导入 API 写入 **YUI** 的事实记忆。失败保留本机记录，可重试。
- 菜单可重新开始记录、重试记忆保存、收起挂件。拖动人物可移动窗口。

## 安装与平台

在 NEKO 插件中心导入 Release 中的 `neko_token_monitor.neko-plugin`，启动后自动显示。

- macOS 11+：包含 Apple Silicon / Intel 通用窗口程序；已在 macOS 验证。
- Windows 10/11 x64：包含 .NET Framework 4.8 / WebView2 窗口程序；需要 Microsoft Edge WebView2 Runtime。构建检查由 Windows runner 执行，桌面透明、恢复和语音效果仍需用户机器验证。
- Linux 暂不提供原生悬浮窗。

目前使用 NEKO 默认本机端口 48911 和猫粮端口 48923；自定义端口环境尚不支持。只适用于本机运行 NEKO。

## 隐私

查询密钥和互动记录保存在 NEKO 分配的插件数据目录，安装包不包含用户配置。macOS 配置文件权限为 0600；Windows 依赖当前用户数据目录权限。切换服务商或自定义地址时不复用旧密钥。网络只用于所选余额/费用接口及本机 NEKO 服务；不发起测试聊天消费。自定义接口不跟随重定向。

## 开发与来源

`native/widget.m` 是 macOS 源码，`native/windows/` 是 Windows 源码。`.github/workflows/native-windows.yml` 构建 Windows 文件。官方插件市场工作流负责校验和 Release 打包。

社区作品，并非 NEKO 官方插件。YUI 身份参考来自 [Project N.E.K.O](https://github.com/Project-N-E-K-O/N.E.K.O)，保留其素材许可与 NOTICE；当前 Q 版图片为 AI 辅助生成。代码采用 Apache-2.0。

API 参考：[OpenAI Costs](https://developers.openai.com/api/reference/python/resources/admin/subresources/organization/subresources/usage)、[Claude Usage and Cost](https://platform.claude.com/docs/en/manage-claude/usage-cost-api)。

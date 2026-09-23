# 猫粮 · YUI 桌面陪伴与余额挂件

导入 `.neko-plugin` 后启动。在人物旁的 ≡ 菜单打开「账户设置」，直接在猫粮窗口内配置，无需浏览器或命令行。

## 查询方式

界面始终叫「猫粮余额」，下方明确显示数据来源。

| 方式 | 含义 | 所需设置 |
| --- | --- | --- |
| Codex 当前登录账号 | 套餐剩余百分比与重置时间 | 本机安装并登录 Codex CLI / app-server |
| DeepSeek | 官方账户余额 | API Key |
| OpenAI / GPT | 自定预算减组织已用费用，非平台余额 | Admin API Key、USD 预算与起始日期 |
| Anthropic / Claude | 自定预算减组织已用费用，非平台余额；不含 Priority Tier | 有组织费用查询权限的密钥、USD 预算与起始日期 |
| 自定义服务商 | 用户指定 HTTPS GET 接口返回的余额 | 地址、Bearer 密钥、JSON 金额字段路径 |
| JEV | 本机桥接上报的输入/输出 token；无账户余额 | 连接本机 JEV 用量上报桥接 |
| 任意模型 | 手动预算，不自动扣减 | 金额、币种、模型备注 |

模型名称仅作备注；组织费用包含全部模型，不能当作单模型用量。ChatGPT/Claude 订阅额度、API 账户余额和上下文剩余量不是同一项。可用 token 仅按用户填写的综合单价估算，不代表平台承诺。

## v0.7.2 新功能

现在可在查询方式中选择 Codex 当前账号额度或 JEV 本机请求用量。Codex 默认每 5 分钟自动查询，无需在插件填写密钥；JEV 需要本机桥接主动上报，不会自动捕获任意客户端流量。详情见 [更新日志](CHANGELOG.md)。

### JEV 桥接协议

本机客户端先 GET `http://127.0.0.1:48923/api/status` 取得 `csrf`，随后使用 `X-Neko-CSRF` 请求头向 `/api/usage` POST JSON：`{"provider":"jev","request_id":"每次真实请求的唯一ID","model":"jev-latest","input_tokens":100,"output_tokens":20}`。示例数值不是实际用量。仅对成功、未缓存的真实调用上报；不要发送密钥、提示词或回答。插件离线时本版本不自动回补。

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


## 0.8.0 多模型额度总览

挂件菜单 → **模型额度总览**。每个平台独立设置并保存在本机；点击卡片的「设置 / 接入」填写，保存后自动切换展示。已配置来源继续后台查询，点「气泡展示」切换主气泡，不需要重新填写其他来源密钥。旧版本当前来源会自动迁移。

| 类型 | 来源 | 展示内容 |
| --- | --- | --- |
| 自动套餐查询 | Codex | 本机登录账号返回的额度百分比与重置时间 |
| 自动余额查询 | DeepSeek、OpenRouter、硅基流动 | 服务商账户共享余额，非单模型独立额度 |
| API 预算估算 | GPT / OpenAI API、Claude API | 自定预算减组织费用，非官方余额或订阅额度 |
| 手动额度 | ChatGPT、Claude / Claude Code、Gemini、Kimi、Qwen、豆包、GLM | 手填剩余、总量、单位、重置备注；尚未接入自动查询 |
| 本机用量 | JEV | 桥接上报累计 token，非剩余额度 |
| 其他 | 自定义 HTTPS 接口、手动金额 | 用户自己的服务商或预算 |

OpenRouter 需要 **Management Key**，普通聊天 Key 可能没有权限。硅基流动使用中国站 API Key，读取 `totalBalance`。密钥只发往固定对应平台。没有凭据时展示未连接，不推测余额；不同平台与不同币种不合并。

官方接口参考：[OpenRouter credits](https://openrouter.ai/docs/api/api-reference/credits/get-remaining-credits)、[硅基流动 OpenAPI](https://github.com/siliconflow/siliconcloud/blob/main/openapi.yaml)、[OpenAI 组织 API](https://developers.openai.com/api/reference/python/resources/admin/subresources/organization)。

# Component.sl

> 源文件：`Component.sl`

## class `Component`

- **说明**：组件基类（Unity 风格，仅含共用方法） 设计取舍： - 不引用 GameObject / Transform 等「Unity 独立类」，保持 Std 模块自包含、无循环依赖。 - 采用轻量「组件即节点」组合模型：每个 Component 持有自己的子组件列表（components）， 所有 GetComponent / 消息 API 都在这棵树上查找。真实引擎里由 GameObject 持有 Component 并设置 gameObject 反向引用；这里把共用逻辑收敛到 Component 自身，避免跨模块耦合。 - 若后续需要 Component.gameObject / Component.transform 快捷属性，由 GameObject 持有 Component 并在挂载时设置 parent / gameObject 即可，不必在本文件引入 Transform。 对照 Unity 的常用 API： GetComponent<T> / GetComponents<T> / GetComponent(Type) / GetComponent(string) GetComponentInChildren<T> / GetComponentInParent<T> GetComponentsInChildren<T> / GetComponentsInParent<T> TryGetComponent<T> / CompareTag / SendMessage / SendMessageUpwards / BroadcastMessage

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public Component parent = null` | 容器（上级组件）；由挂载时设置 |
| 字段 | `public bool enabled = true` | 是否启用（对应 Unity 的 enabled） |
| 字段 | `public string tag = "Untagged"` | 标签（对应 Unity 的 tag） |
| 字段 | `public string name = "Component"` | 名称（便于调试，对应 Unity 的 name） |
| 方法 | `void _init_()` | ── 构造 ─────────────────────────────────────────── |
| 属性 | `get bool isActiveAndEnabled()` | ── 启用状态 ─────────────────────────────────────── 自身启用且整条 parent 链都启用时才算「激活且启用」 |
| 方法 | `void setEnabled(bool value)` | 执行 setEnabled(value)，行为详见源实现。 |
| 方法 | `bool getEnabled()` | 执行 getEnabled()。 |
| 方法 | `void addComponent(Component comp)` | ── 组件挂载 ─────────────────────────────────────── |
| 方法 | `Component getComponent(Type type)` | 执行 getComponent(type)，行为详见源实现。 |
| 方法 | `Component getComponent(string typeName)` | 执行 getComponent(typeName)，行为详见源实现。 |
| 方法 | `bool compareTag(string otherTag)` | ── 标签 ─────────────────────────────────────────── |
| 方法 | `void sendMessage(string methodName)` | ── 消息（简化模型：组件可 override onMessage 响应）── 向自身及所有子组件发送 |
| 方法 | `void sendMessageUpwards(string methodName)` | 向自身及所有祖先发送 |
| 方法 | `void broadcastMessage(string methodName)` | 向自身及整棵子树广播 |
| 方法 | `void onMessage(string methodName)` | 子类可 override，以响应 SendMessage / BroadcastMessage / SendMessageUpwards |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |

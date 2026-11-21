# Prefab（预制体）

Prefab 是「一个 GameObject 子树保存成的 JSON 文件」。它和场景文件 `scene.json` **完全同构**，可以理解为「只有一个根节点的场景文件」——因此场景与 Prefab 共用同一套读写代码，格式也一致。

## 1. 文件格式

```json
{
  "version": 1,
  "scene": "Chest",
  "nodes": [
    {
      "id": 1,
      "parent": 0,
      "name": "Chest",
      "tag": "Loot",
      "layer": 5,
      "active": true,
      "transform": {
        "localPosition": [1, 2, 3],
        "localRotation": [0, 0, 0, 1],
        "localScale": [1, 1, 1]
      },
      "components": [
        { "type": "MeshFilter", "mesh": "mesh_3" },
        { "type": "BoxCollider", "center": [0, 1, 0], "size": [2, 3, 4], "isTrigger": false }
      ]
    },
    {
      "id": 2,
      "parent": 1,
      "name": "Lid"
    }
  ]
}
```

- 节点是**扁平数组**，用 `parent`（父节点 id）表达层级；`parent: 0` 表示根节点。
- 只保存**局部变换**（localPosition / localRotation / localScale），世界变换由父子链计算。
- 可序列化组件：`MeshFilter`、`MeshRenderer`、`Rigidbody`、`BoxCollider`、`SphereCollider`、`CapsuleCollider`、`SpriteRenderer`、`Light`、`Volume`，以及 `Script`（仅脚本短名）。

## 2. 可用方法

全部挂在 `SceneManager` 上（与场景加载/保存同一入口）：

| 方法 | 说明 |
|---|---|
| `string prefabToJson(GameObject root, string prefabName)` | 子树 → JSON 文本；名字为空时用根节点名 |
| `bool prefabSave(GameObject root, string path, string prefabName)` | 子树 → 文件 |
| `Scene prefabLoad(string path)` | 读文件为模板场景（不并入当前场景，可用于检查） |
| `Scene prefabLoadText(string json)` | 读文本为模板场景 |
| `GameObject prefabInstantiate(Scene template, GameObject parent)` | 从模板实例化；`parent=null` → 挂到活动场景根 |
| `GameObject instantiate(string path, GameObject parent)` | 文件 → 实例化（常用入口） |
| `GameObject instantiateText(string json, GameObject parent)` | 文本 → 实例化 |

失败时 `SceneManager.lastError` 有原因说明，返回 `null` / `false` / 空串。

## 3. 使用示例

```SLang
SceneManager sm = SceneManager()

# 保存：把场景里的一个节点子树存成 Prefab
GameObject chest = sm.activeScene.find( "Chest" )
sm.prefabSave( chest, "assets/prefabs/chest.json", "Chest" )

# 加载并实例化：挂到某个节点下
GameObject host = sm.activeScene.find( "Room" )
GameObject clone = sm.instantiate( "assets/prefabs/chest.json", host )

# 或者一次性实例化多个（每次调用都是全新对象树）
GameObject a = sm.instantiateText( prefabJson, null )
GameObject b = sm.instantiateText( prefabJson, null )
```

先注册脚本工厂再加载含 `Script` 组件的 Prefab（与场景加载相同）。

## 4. 注意事项 / 已知限制

1. **每次实例化都重新解析 JSON**，生成全新的节点与组件，多次实例化互不影响；JSON 里的 `id` 只在文件内有效，不是运行时身份。
2. **节点注册表按名字哈希**：同名实例的节点 id 相同是预期行为，不要拿 id 当实例唯一标识。
3. **`parent` 节点不在场景里时**，实例会回退挂到当前活动场景（`lastError` 不会报错）；需要严格归属时先把 parent 加入场景。
4. **Script 只保存脚本短名**，不保存脚本自定义参数；需要在 Prefab 里带参数时，由脚本自己的工厂/序列化逻辑处理。
5. **Light / Volume 已支持往返保存**：Volume 只保存显式设置过的字段（掩码语义，缺省 = 不修改）。
6. **Prefab 与场景格式相同**，用场景加载接口读 Prefab 文件也可以得到一棵完整节点树（区别只是 Prefab 通常只有一个根）。
7. 文件路径的目录必须**预先存在**，保存接口不会自动创建目录。

# CloneIterface.sl

> 源文件：`CloneIterface.sl`

## interface `IClone`

- **接口**：IClone
- **说明**：克隆契约：实现该接口的类型可通过 clone() 返回自身的一个独立副本（深/浅拷贝语义由实现决定）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `Object clone()` | 返回当前对象的副本。 |

## interface `IClone<T>`

- **接口**：IClone&lt;T&gt;
- **说明**：泛型克隆契约：强类型 clone()，返回 T 的副本。

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `T clone()` | 克隆 / 复制（clone）。 |

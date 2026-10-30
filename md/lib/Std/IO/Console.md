# IO/Console.sl

> 源文件：`IO/Console.sl`

## class `Console`

- **说明**：SLang 标准库类型 Console（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `void write(string text, params object[] param)` | Print without newline |
| 方法 | `void print(string text, params object[] param)` | Print without newline (alias) |
| 方法 | `void println(string text, params object[] param)` | Print with newline |
| 方法 | `void newLine()` | Print just a newline (C# Console.WriteLine() / Dart print("")) |
| 方法 | `void writeLine(string text, params object[] param)` | C# style alias for println (Console.WriteLine) |
| 方法 | `string input()` | Read a line from stdin and return as string |
| 方法 | `string input(string prompt)` | Read with prompt: print prompt (no newline) then read (Dart stdout.write + stdin.readLineSync) |
| 方法 | `string readLine()` | Alias for input |
| 方法 | `string readLine(string prompt)` | Read line with prompt |
| 方法 | `string readKey()` | Read a single key |
| 方法 | `string readKey(string prompt)` | Read a single key with prompt |
| 方法 | `int readInt()` | Read line and parse to Int32 (C# int.Parse(Console.ReadLine())) |
| 方法 | `int readInt(string prompt)` | Read line with prompt and parse to Int32 |
| 方法 | `double readDouble()` | Read line and parse to Float64 (C# double.Parse(Console.ReadLine())) |
| 方法 | `double readDouble(string prompt)` | Read line with prompt and parse to Float64 |
| 方法 | `void clear()` | ---- Screen / cursor control ---- Clear the whole screen (cursor returns to 0,0) |
| 方法 | `void setCursorPosition(int left, int top)` | Move the cursor to (left, top), 0-based |
| 方法 | `void setCursorVisible(bool visible)` | Show or hide the caret |
| 方法 | `void hideCursor()` | Hide the caret (games usually want this) |
| 方法 | `void showCursor()` | Show the caret again |
| 方法 | `void setForegroundColor(int color)` | ---- Color control (use the colorXxx constants below) ---- |
| 方法 | `void setBackgroundColor(int color)` | 执行 setBackgroundColor(color)，行为详见源实现。 |
| 方法 | `void resetColor()` | Reset colors to terminal default |
| 方法 | `bool keyAvailable()` | ---- Non-blocking input (real-time loops) ---- True when a key is waiting in the console input buffer (never blocks) |
| 方法 | `string readKeyDirect()` | Read one key directly from the console buffer (no Enter needed). Returns the key char, "up"/"down"/"left"/"right" for arrow keys, "" when empty. Pair with keyAvailable(): while (Console.keyAvailable()) { k = Console.readKeyDirect() } |
| 方法 | `int windowWidth()` | ---- Window size ---- Current console window width in columns |
| 方法 | `int windowHeight()` | Current console window height in rows |
| 方法 | `void sleep(int ms)` | ---- Frame pacing ---- Block the current thread for ms milliseconds (game frame delay) |
| 字段 | `static int colorBlack       = 0` | ---- ConsoleColor constants (16 colors) ---- |
| 字段 | `static int colorDarkBlue    = 1` | 字段 int（类型见签名）。 |
| 字段 | `static int colorDarkGreen   = 2` | 字段 int（类型见签名）。 |
| 字段 | `static int colorDarkCyan    = 3` | 字段 int（类型见签名）。 |
| 字段 | `static int colorDarkRed     = 4` | 字段 int（类型见签名）。 |
| 字段 | `static int colorDarkMagenta = 5` | 字段 int（类型见签名）。 |
| 字段 | `static int colorDarkYellow  = 6` | 字段 int（类型见签名）。 |
| 字段 | `static int colorGray        = 7` | 字段 int（类型见签名）。 |
| 字段 | `static int colorDarkGray    = 8` | 字段 int（类型见签名）。 |
| 字段 | `static int colorBlue        = 9` | 字段 int（类型见签名）。 |
| 字段 | `static int colorGreen       = 10` | 字段 int（类型见签名）。 |
| 字段 | `static int colorCyan        = 11` | 字段 int（类型见签名）。 |
| 字段 | `static int colorRed         = 12` | 字段 int（类型见签名）。 |
| 字段 | `static int colorMagenta     = 13` | 字段 int（类型见签名）。 |
| 字段 | `static int colorYellow      = 14` | 字段 int（类型见签名）。 |
| 字段 | `static int colorWhite       = 15` | 字段 int（类型见签名）。 |
